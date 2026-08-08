# Walker Bank — Tarefa para o Agente
## Landing Page: Crédito Consignado para Servidores Públicos

---

## CONTEXTO DO PROJETO

Construir uma landing page de captura de leads para o **Walker Bank**, um banco digital brasileiro. O produto é **crédito consignado** voltado para **servidores públicos** (INSS, Forças Armadas, Estaduais, Municipais).

O objetivo número 1 da página é **gerar simulações** — o lead escolhe o convênio, o valor e o prazo, vê a parcela estimada e clica em avançar para o formulário.

A página será veiculada via tráfego pago (Meta Ads, Google Ads), WhatsApp e disparo de e-mail/SMS.

---

## STACK TÉCNICA

- HTML5 + CSS3 + JavaScript vanilla (sem frameworks)
- Um único arquivo `index.html` autocontido
- Responsivo: mobile-first (breakpoint principal: 375px → 1280px)
- Sem dependências externas além do Google Fonts

---

## IDENTIDADE VISUAL (BRANDBOOK)

### Paleta de cores
```css
--navy:     #181b2c;   /* fundo hero e rodapé */
--cobalt:   #424e7a;   /* ícones, destaques secundários */
--gold:     #d4bc6e;   /* botões CTA, bordas de destaque */
--nardo:    #cecfd3;   /* fundos neutros, seções claras */
--white:    #ffffff;
--black:    #000000;
--dark-gold: #a69458;  /* hover do botão */
```

### Tipografia
- Display / títulos: **Playfair Display** (Google Fonts) — elegância financeira
- Corpo / UI: **DM Sans** (Google Fonts) — leitura limpa
- Tagline em caps espaçada: letter-spacing 0.15em

### Tom visual
Refinado, sério, premium. Não é banco digital jovem com neon. É instituição de confiança com design moderno. Pense: autoridade + acessibilidade.

### Logotipo
Exibir em texto: **Walker Bank** (Playfair Display, branco) + tagline **EM CADA PASSO COM VOCÊ** (DM Sans caps, letter-spacing 0.15em, dourado `#d4bc6e`).

---

## ESTRUTURA DA PÁGINA — SEÇÕES EM ORDEM

### SEÇÃO 01 — Hero (topo)

**Layout:** Fundo marinho `#181b2c` com textura sutil (pattern geométrico muito leve usando o W do logo como watermark em opacity 0.05). Logo no topo esquerdo. Nav com link âncora "Simular agora".

**Headline (testar A/B — renderizar a opção A por padrão):**
```
Crédito consignado com as menores taxas
para servidores públicos
```

**Subtítulo:**
```
Simule agora e descubra quanto você pode ter em até 2 minutos.
Sem burocracia. Parcelas direto na folha.
```

**CTA principal:**
- Botão: `Simular meu crédito agora →`
- Cor: fundo `#d4bc6e`, texto `#181b2c`, bold
- Hover: fundo `#a69458`
- Ao clicar: scroll suave até a seção do simulador

**Prova social abaixo do CTA:**
```
★★★★★  +2.000 servidores aprovados
```
Texto pequeno, branco com 70% de opacidade.

**Imagem:** Lado direito (desktop) — placeholder elegante com ícone de pessoa em ambiente profissional. Em mobile: ocultar imagem, manter apenas texto + CTA.

---

### SEÇÃO 02 — Benefícios

**Fundo:** Branco `#ffffff`

**Título da seção:**
```
Por que escolher a Walker Bank?
```

**4 cards em grid (2x2 desktop, 1 coluna mobile):**

| Ícone SVG | Título | Descrição |
|---|---|---|
| Shield (proteção) | Menor taxa do mercado | Desconto direto na folha, sem risco de inadimplência para você. |
| Clock (velocidade) | Aprovação em minutos | Sem filas, sem papelada. Tudo pelo celular ou computador. |
| Calendar (prazo) | Parcelas que cabem no bolso | Até 96 meses de prazo. Você escolhe o valor ideal. |
| Headset (suporte) | Suporte humano do início ao fim | Um especialista acompanha seu processo até o dinheiro na conta. |

**Estilo dos cards:** borda `0.5px solid #cecfd3`, radius 12px, ícone em cobalto `#424e7a` (24px), título em navy, descrição em cinza médio. Hover sutil: border-color vira `#d4bc6e`.

---

### SEÇÃO 03 — Simulador ⚡ (seção mais importante)

**Fundo:** Cinza clarinho `#f5f6fa`

**Título:**
```
Simule seu crédito em segundos
```
**Subtítulo:**
```
Escolha seu convênio, o valor que precisa e veja as parcelas na hora.
```

**Card do simulador** (fundo branco, sombra leve, radius 16px, padding 40px):

#### Campo 1 — Convênio
Label: "Seu convênio"
Tipo: botões de seleção (pill buttons), um por opção:
- `INSS`
- `Forças Armadas`
- `Estadual`
- `Municipal`

Estado selecionado: fundo `#181b2c`, texto branco. Estado padrão: borda `#cecfd3`, texto `#424e7a`.

#### Campo 2 — Valor desejado
Label: "Quanto você precisa?"
Tipo: slider range + display do valor em tempo real
- INSS: R$ 500 a R$ 5.000
- Forças Armadas: R$ 500 a R$ 15.000
- Estadual: R$ 500 a R$ 20.000
- Municipal: R$ 500 a R$ 15.000

Display: valor grande centralizado em navy, formatado em BRL (`R$ 3.500`).

#### Campo 3 — Prazo
Label: "Em quantas parcelas?"
Tipo: botões de seleção (pill buttons):
- `24x` `36x` `48x` `72x` `96x`

Mesmo estilo dos pills do convênio.

#### Resultado (exibido após qualquer mudança, animado com fade-in)

**Cálculo da parcela:**
Usar tabela Price simplificada:
```
taxa_mensal por convênio:
  INSS: 1.80% ao mês
  Forças Armadas: 1.50% ao mês
  Estadual: 1.65% ao mês
  Municipal: 1.70% ao mês

parcela = valor * (taxa * (1 + taxa)^prazo) / ((1 + taxa)^prazo - 1)
```

**Layout do resultado:**
```
┌─────────────────────────────────────┐
│  Sua parcela estimada               │
│  R$ XXX,XX / mês     em XX parcelas │
│                                     │
│  Taxa: 1,80% ao mês                 │
│  Total financiado: R$ XX.XXX,XX     │
└─────────────────────────────────────┘
```
Parcela em destaque: 36px, bold, navy.

**CTA pós-resultado:**
```
Quero esse crédito →
```
- Botão full-width, fundo dourado `#d4bc6e`, texto navy bold
- Ao clicar: scroll até seção do formulário (Fase 3 — por ora, exibir modal placeholder com mensagem "Em breve você será redirecionado para o formulário")

**Disclaimer legal** (abaixo do card, texto pequeno 11px, cinza):
```
*Simulação meramente ilustrativa, sujeita à análise de crédito e margem consignável 
disponível. Taxas e condições podem variar conforme convênio e perfil do solicitante.
```

---

### SEÇÃO 04 — Como funciona

**Fundo:** Branco

**Título:**
```
Simples assim — 3 passos
```

**3 steps em linha (desktop) / coluna (mobile):**

```
[1] Simule          [2] Preencha         [3] Receba
Escolha o valor     Seus dados em        O dinheiro na
e o prazo ideal.    menos de 3 min.      conta aprovado.
Sem cadastro.       Tudo online.
```

Linha conectora entre os steps (desktop). Número em círculo navy, título em navy bold, texto em cinza.

---

### SEÇÃO 05 — Depoimentos

**Fundo:** `#f5f6fa`

**Título:**
```
Quem já aproveitou conta
```

**3 cards lado a lado (desktop) / scroll horizontal (mobile):**

```
Card 1:
★★★★★
"Aprovado em 1 dia e sem sair de casa.
Processo muito mais simples do que eu esperava."
— Maria S., Professora Estadual · SP

Card 2:
★★★★★
"Taxa muito melhor do que no meu banco de sempre.
Valeu muito a pena simular."
— Carlos R., Servidor Municipal · MG

Card 3:
★★★★★
"Atendimento humano de verdade. Me explicaram
tudo com calma e sem pressão."
— João P., Policial Militar · RJ
```

Estilo: card branco, borda `#cecfd3`, radius 12px, estrelas em dourado `#d4bc6e`.

---

### SEÇÃO 06 — Convênios atendidos

**Fundo:** Navy `#181b2c`

**Título (branco):**
```
Convênios atendidos
```

**4 badges lado a lado:**
```
[ INSS ]   [ Forças Armadas ]   [ Servidor Estadual ]   [ Servidor Municipal ]
```
Badge: borda `#d4bc6e`, texto dourado, fundo transparente. Radius 40px (pill).

---

### SEÇÃO 07 — FAQ

**Fundo:** Branco

**Título:**
```
Dúvidas frequentes
```

**Accordion — 5 perguntas (abrir/fechar com JS):**

1. **Preciso ter conta na Walker Bank para contratar?**
   Não. Qualquer servidor público elegível pode simular e contratar.

2. **O crédito afeta minha margem consignável?**
   Sim. O desconto em folha respeita o limite legal de 35% da remuneração bruta.

3. **Em quanto tempo o dinheiro cai na conta?**
   Após aprovação, em até 1 dia útil.

4. **Meu nome sujo impede a aprovação?**
   Não necessariamente. O consignado tem aprovação facilitada por ter desconto em folha.

5. **Posso quitar antecipadamente?**
   Sim, com redução proporcional dos juros.

Estilo accordion: borda inferior `#cecfd3`, pergunta em navy bold, ícone `+` / `−` em dourado. Animação de abertura suave.

---

### SEÇÃO 08 — CTA Final (rodapé)

**Fundo:** Navy `#181b2c`

**Conteúdo centralizado:**
```
Pronto para dar o próximo passo?

Simule agora, sem compromisso.
Em minutos você sabe exatamente quanto pode ter.

[ Simular meu crédito → ]

🔒 Dados protegidos pela LGPD    ✓ Banco autorizado pelo Banco Central
```

Botão: mesmo estilo do hero (dourado). Selos em branco 60% de opacidade, texto pequeno.

**Rodapé inferior (abaixo do CTA):**
```
Walker Bank © 2025  |  Todos os direitos reservados
Política de Privacidade  |  Termos de Uso
```
Texto mínimo, cinza claro sobre navy.

---

## COMPORTAMENTOS JAVASCRIPT OBRIGATÓRIOS

1. **Scroll suave** para âncoras (`#simulador`, `#formulario`)
2. **Simulador reativo:** qualquer mudança em convênio, valor ou prazo → recalcular e atualizar resultado instantaneamente (sem botão "calcular")
3. **Animação fade-in** no resultado do simulador ao atualizar
4. **Accordion FAQ** com abertura/fechamento animado
5. **Sticky header** leve: ao rolar, header fica fixo com fundo navy e sombra sutil
6. **UTM preservation:** capturar parâmetros UTM da URL (`utm_source`, `utm_medium`, `utm_campaign`, `utm_content`) e armazenar em `sessionStorage` para repassar ao formulário
7. **Scroll reveal:** seções entram com fade-up suave ao aparecerem na viewport (`IntersectionObserver`)

---

## PARÂMETROS UTM A PRESERVAR

```javascript
// Ao carregar a página, capturar e salvar:
const params = ['utm_source','utm_medium','utm_campaign','utm_content','utm_term'];
params.forEach(p => {
  const val = new URLSearchParams(window.location.search).get(p);
  if (val) sessionStorage.setItem(p, val);
});
```

---

## MODAL PLACEHOLDER (formulário — Fase 3)

Ao clicar em "Quero esse crédito", exibir modal centralizado com:
```
Quase lá!

Em breve você será redirecionado para preencher
seus dados e finalizar a contratação.

[Fechar]
```
Modal: fundo branco, overlay navy 80% opacity, radius 16px, botão fechar dourado.

---

## CRITÉRIOS DE QUALIDADE

- [ ] Pixel-perfect em mobile (375px) e desktop (1280px)
- [ ] Simulador calcula corretamente para todos os convênios e prazos
- [ ] Nenhum texto cortado ou overflow horizontal
- [ ] Animações não causam layout shift
- [ ] Accordion FAQ funciona sem bugs
- [ ] UTMs são capturados e salvos em sessionStorage
- [ ] CLS (Cumulative Layout Shift) mínimo — reservar espaço para o resultado do simulador

---

## ARQUIVO DE SAÍDA

- `index.html` — página completa autocontida
- Testar no browser integrado do Antigravity após gerar
- Verificar simulador com diferentes combinações de convênio + valor + prazo
