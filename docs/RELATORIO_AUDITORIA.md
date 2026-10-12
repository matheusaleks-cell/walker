# Relatório de Auditoria — Walker Bank (Página de Captura + Mesa de Crédito)

Data: 2026-09-30 · Escopo: `index.html`, `proposta.html`, `login.html`, `dashboard.html`, `sql/*.sql`, `supabase.js`, `firebase-config.js`, `leads_mock.js`, `netlify.toml`, `.htaccess`, `scripts/`, `.gitignore`.
Método: leitura estática do código. **Nada foi executado nem testado contra o Supabase/Firebase reais**; os itens marcados "a confirmar" dependem de configuração do painel que não está no repositório.

Contexto: é um front-end estático (HTML/JS) falando direto com o Supabase usando a chave pública. Não há backend próprio. Por isso **toda a segurança depende das políticas RLS do banco**, e é aí que estão os problemas mais graves.

---

## Resumo

| Severidade | Qtde |
|---|---|
| Crítica | 4 |
| Alta | 6 |
| Média | 8 |
| Baixa / melhoria | 7 |

Prioridade imediata: C1, C2, C3 e C4.

---

## CRÍTICAS

### C1. Escalada de privilégio: qualquer usuário autenticado vira admin
`sql/supabase_profiles_setup.sql:33-36`
A policy "Atualização do próprio perfil" usa só `USING (auth.uid() = id)`, sem `WITH CHECK` e sem restringir colunas. Qualquer operador pode executar `update profiles set role='admin' where id = auth.uid()` direto pela API, usando a chave pública que está no HTML.
**Impacto:** o controle de admin no dashboard (`isCurrentUserAdmin`, `dashboard.html:3135`) lê o role do `sessionStorage`, então também é forjável no navegador (DevTools). A checagem é só de interface.
**Correção:** trocar por policy com `WITH CHECK` que impeça alterar `role` (ou mover `role` para tabela separada / usar trigger que bloqueia mudança de role por não-admin). Aplicar autorização por role nas policies de `leads`, `configs`, `audit_log`, não na UI.

### C2. Cadastro aberto + role vindo do cliente (a confirmar)
`dashboard.html:9277-9283` e trigger `handle_new_user` (`supabase_profiles_setup.sql:50-66`)
O operador é criado com `supabaseClient.auth.signUp(...)` a partir do navegador, e o trigger confia em `raw_user_meta_data->>'role'`. Se o "Allow new signups" do Supabase estiver ligado (padrão), **qualquer pessoa** pode chamar `signUp` com a chave pública e `data: { role: 'admin' }`, receber perfil admin e entrar no sistema.
Também: o trigger promove a admin qualquer e-mail que contenha `raulfiuza` (`LIKE '%raulfiuza%'`), então `raulfiuza@qualquer-dominio.com` vira admin.
**Correção:** desligar signups públicos; criar operadores por Edge Function com service role (ou convite pelo painel); o trigger deve ignorar `role` do metadata e a regra do e-mail deve sair.

### C3. RLS permissiva demais: base inteira de CPFs/documentos exposta a qualquer conta
`supabase_profiles_setup.sql:149-179`, `walkerbank_storage_setup.sql:30-45`
`leads` (nome, CPF, renda, dados bancários, PIX, mãe, RG), `audit_log` e `configs` têm `USING (true)` para todo `authenticated`. Combinado com C1/C2, qualquer conta lê, altera e **apaga** todos os leads e baixa todos os documentos do bucket `walkerbank-docs`. Não há isolamento por operador, apesar de o produto ter conceito de "operador responsável".
**Correção:** policies por role e por `operador_id`; DELETE só admin; `configs` UPDATE só admin (hoje qualquer operador altera taxas, comissões e convênios da empresa).

### C4. INSERT anônimo sem validação em `leads` (spam, poisoning e XSS armazenado)
`supabase_profiles_setup.sql:163-166` + `proposta.html:3047-3058`
`anon` pode inserir qualquer linha com `WITH CHECK (true)`: ID, `status`, `payload` JSONB arbitrário, sem limite de tamanho ou de taxa. Um atacante pode (a) encher o banco/CRM de leads falsos, (b) inserir leads já com status avançado ("Aprovada") ou atribuídos a um operador, (c) injetar HTML/JS em campos que o dashboard renderiza via `innerHTML` (ver A1). O reCAPTCHA do Firebase só protege o SMS, não o insert.
**Correção:** passar o envio por Edge Function (validação, rate limit, captcha/Turnstile, CPF, tamanho) e remover INSERT anônimo direto; se mantiver, forçar `status='Aguardando Averbação'` via `WITH CHECK` e limitar o payload.

---

## ALTAS

### A1. XSS armazenado no dashboard (parcial)
`dashboard.html` tem ~161 usos de `innerHTML`. Há `escapeHtml` (`:3858`) aplicado em vários pontos (nome do lead, observação), mas **não em todos**: por exemplo os `<option>` com `op.nome` (`:3241, 3249, 3255`) e demais campos de `payload` renderizados em templates. Como o `payload` é 100% controlado por um anônimo (C4), qualquer campo não escapado executa JS na sessão de um admin/operador, com acesso ao token Supabase (em `localStorage`) e à API completa.
**Correção:** auditar todos os templates com dados de `payload`/perfil; preferir `textContent`/criação de nós; adicionar CSP (ver M4). Não auditei os 161 pontos um a um — recomendo um passe dedicado.

### A2. "Modo demonstração" abre o dashboard sem autenticação
`login.html:461-465`, `dashboard.html:3063-3069`
O botão "demo" grava `walker_admin_session` e `walker_demo_mode` no `sessionStorage` e entra no dashboard. O guard do dashboard também aceita qualquer valor em `localStorage` na chave `sb-…-auth-token` ou simplesmente `walker_admin_session=true`, sem validar sessão real. Ou seja, o "login" do front é só cosmético.
Os dados reais só ficam protegidos se o RLS estiver correto (não está — C3), e o demo carrega `leads_mock.js` e leads do `localStorage`.
**Correção:** remover o botão demo de produção (ou condicionar a hostname local); o guard deve chamar `supabase.auth.getSession()` e redirecionar se vazio, antes de renderizar.

### A3. `leads_mock.js`, `dashboard.html`, `docs/`, `sql/` públicos; possível dado real
`leads_mock.js` tem 52 CPFs/telefones/e-mails, comentado como "importado do Excel" — se vier de dados reais, é vazamento de PII a qualquer visitante (`/leads_mock.js`). O `netlify.toml` não define `publish`/`build`, então o **diretório inteiro** é publicado (se deploy via CLI/arrastar, isso inclui `dados-planilhas/` com CSV/XLSX de tomadores, `sql/`, `docs/`, `scripts/`, `.claude/`). O `.gitignore` só protege o Git, não deploy manual.
**Correção:** confirmar se os mocks são fictícios; criar pasta `public/` e `publish = "public"`; nunca deixar planilhas de clientes dentro da pasta do site.

### A4. Assinatura por SMS é 100% client-side e contornável
`proposta.html:2542-2580, 2990`
A validação do código roda no navegador e o flag `assinatura_sms_validada` é enviado pelo próprio cliente no payload, sem nenhuma prova server-side (o servidor nunca vê o token do Firebase). Qualquer um pode forjar `true`, ou pular via "assinatura manual" (`:2478`). Para operação de crédito, isso não tem valor probatório e não atende exigência de assinatura eletrônica.
Outros pontos: telefone verificado não é comparado com o `celular` enviado; se o Firebase falhar, cai no fallback demo (bloqueado fora de localhost, ok), mas o código demo é exibido na tela (`:2503`) — garantir que nunca ocorra em produção.
**Correção:** verificar o ID token do Firebase (ou usar OTP server-side) numa Edge Function e gravar o resultado no servidor.

### A5. Dados sensíveis em texto/`console.log` e em `localStorage`
`proposta.html:3083` faz `console.log("Enviando proposta payload:", payload)` com CPF, dados bancários e PIX; o mesmo lead completo é gravado em `localStorage["walker_leads"]` do computador do cliente (`:3022-3026`) e nunca removido (em PC compartilhado/lan house fica lá). O dashboard também guarda leads, configs, audit_log e o perfil em storage do navegador.
**Correção:** remover logs de PII; não persistir o lead no localStorage do cliente após o envio; limitar o que o dashboard cacheia.

### A6. Fallback base64 grava documentos dentro do banco
`proposta.html:2901-2914, 2932-2939`
Se o upload ao Storage falha, RG/contracheque vão como base64 dentro de `leads.payload`, legíveis por qualquer authenticated e sem as restrições do bucket (tipo/10 MB). Também aumenta muito o payload (risco de estourar limites e lentidão do `select`).
**Correção:** falhar o envio e pedir nova tentativa; nunca embutir binário no JSON.

---

## MÉDIAS

### M1. Trilha de auditoria falsificável e sem valor para LGPD
`audit_log` aceita INSERT de qualquer autenticado com `operador_id` livre, e leitura por todos. Não é imutável (sem policy de UPDATE/DELETE, mas o admin do Supabase edita) e o log local (`walker_audit_log`) está no `localStorage`. Não registra leitura de CPF/documento de forma confiável. Preencher `operador_id` via `default auth.uid()` e restringir leitura a admin.

### M2. Upload anônimo no Storage sem controle de caminho/volume
`walkerbank-docs`: anon pode gravar qualquer `leads/%`, sem vínculo a um lead existente, sem rate limit. Vetor de abuso de armazenamento e de arquivos maliciosos (o bucket limita MIME, mas o `contentType` é definido pelo cliente). O `leadId` é `Math.random().toString(36)` (`:2880`), ~46 bits e não criptográfico; usar `crypto.randomUUID()`.

### M3. Login com rate limit só no cliente
`login.html:467-517`: contador em `localStorage`, apagável com um clique/curl. O bloqueio real depende do rate limit do Supabase Auth. Senha mínima de 6 caracteres (`:335, 635`); sem MFA para um sistema com dados financeiros/CPF.

### M4. Sem cabeçalhos de segurança
Nem `netlify.toml` nem `.htaccess` definem CSP, `X-Frame-Options`/`frame-ancestors`, `X-Content-Type-Options`, `Referrer-Policy`, HSTS. Dashboard e login são embutíveis em iframe (clickjacking). Recomendado CSP restritiva, especialmente por causa de A1.

### M5. Scripts de terceiros sem SRI e com versão flutuante
`dashboard.html:19` (`chart.js` sem versão fixa), `:25` (xlsx 0.18.5, versão com vulnerabilidades conhecidas de prototype pollution/ReDoS — atualizar), `index.html:2400-2403` (`unpkg.com/scrollreveal` sem versão; floating-ui de jsdelivr). Sem `integrity`. Um comprometimento do CDN executa código na página que manipula credenciais. Fixar versões + SRI, ou servir localmente.

### M6. `supabase.js` de ~100 mil tokens, minificado e commitado
É uma cópia local do SDK; não dá para saber a versão nem receber patches de segurança. Trocar por dependência versionada/CDN com SRI.

### M7. Schema divergente do código (bugs de produção)
O dashboard usa a tabela `notifications` (`proposta.html:3066`) e colunas `salario_base`, `sonho_titulo`, `sonho_valor`, `sonho_acumulado` em `profiles` (`dashboard.html:3208`), mas **nenhuma está nos SQLs do repositório**. O próprio código tem fallback com aviso "Execute a migração SQL". Em um banco novo, notificações falham silenciosamente (`catch` só loga) e o painel de operadores degrada. Além disso, `notifications` não tem RLS versionada — se criada sem RLS, é aberta. Versionar migrações completas.

### M8. Upsert de `configs` de linha única sem controle de concorrência
`configs` tem uma linha `default` reescrita inteira (`upsert({id:'default', data: cfg})`, ex. `:9316, 9433`), a partir de uma cópia local do `localStorage`. Dois admins/operadores editando ao mesmo tempo, ou uma cópia antiga em cache, **sobrescrevem** taxas, comissões, convênios e operadores do outro (last-write-wins). Como qualquer operador tem UPDATE (C3), um cache antigo pode zerar configurações da empresa.

---

## BAIXAS / MELHORIAS

- **B1.** Chave Firebase e chave publishable do Supabase estão expostas no cliente — é esperado, mas o comentário em `firebase-config.js` afirma que estão "restritas por domínio". Confirmar no console: restrição de HTTP referrer na API key, domínios autorizados e App Check; sem isso, o SMS pode ser abusado por terceiros (custo/limite de cota).
- **B2.** `dashboard.html` (13.9 mil linhas, ~161 innerHTML, lógica de negócio, cálculo de comissão, tudo em um arquivo) é de difícil manutenção e teste; sem testes automatizados nem build.
- **B3.** Cálculo financeiro no cliente (parcela, CET, total financiado, taxa) e enviado no payload: o servidor confia nos valores do navegador. Recalcular no servidor antes de gravar/aprovar. `taxa_juros_mensal` também aceita fallback do `localStorage` do cliente.
- **B4.** Sem consentimento verificável/registro de versão do termo LGPD: só `consentimento_lgpd: true/false` no payload, sem data/IP/versão do texto e sem política de retenção/exclusão de dados.
- **B5.** `.htaccess` e `netlify.toml` fazem o mesmo roteamento (duplicado, dois hosts); o `RewriteCond ^[A-Z]{3,}\s([^.]+)\.html` pode redirecionar caminhos com ponto no diretório. Escolher uma plataforma.
- **B6.** `scripts/dev_server.js` e `.py` sem risco em produção, mas o normalize do path é fraco (`replace(/^(\.\.[\/\\])+/)`); só usar em localhost.
- **B7.** Validações no formulário só de front (CPF, telefone, e-mail); duplicidade de CPF/proposta não é tratada no banco (sem `UNIQUE`/índices em `cpf`, nem índice em `status`/`created_at` para as consultas do dashboard, que tende a ficar lento com volume).

---

## Ordem de correção sugerida

1. **Hoje:** desligar signups públicos no Supabase (C2); confirmar/remover `leads_mock.js` e planilhas do deploy (A3); revisar quais dados reais já estão no ar.
2. **Esta semana:** reescrever RLS (C1, C3, C4) com roles reais e `WITH CHECK`; remover o modo demo do build de produção (A2); tirar PII de logs/localStorage (A5, A6).
3. **Em seguida:** Edge Function para envio de propostas e verificação de SMS/OTP server-side (A4, C4); CSP + cabeçalhos + SRI (M4, M5); auditar `innerHTML` (A1).
4. **Depois:** migrações versionadas (M7), auditoria confiável (M1), testes e modularização do dashboard (B2).

## Limitações desta auditoria

- Análise estática; não testei o ambiente Supabase/Firebase publicado nem tentei explorar nada.
- Não li linha a linha os 13.9 mil de `dashboard.html`; A1, B2 e possíveis falhas de regra de negócio (comissão, metas, funil) merecem revisão dedicada.
- Não verifiquei se os dados de `leads_mock.js` e `dados-planilhas/` são reais ou fictícios.
- Configurações do painel (signups, SMTP, restrições de chave, políticas efetivamente aplicadas) podem diferir dos `.sql` do repositório.
