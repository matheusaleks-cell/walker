# REGRAS DE SEGURANÇA — WALKER BANK
## Prompt obrigatório: incluir em TODO agente antes de qualquer tarefa de código

> Cole este documento no início de cada sessão de agente no Antigravity IDE.
> Nenhuma linha de código deve ser gerada sem que estas regras estejam ativas.

---

## CONTEXTO

Este sistema lida com **dados financeiros e pessoais sensíveis** de cidadãos brasileiros:
CPF, dados bancários, renda, documentos de identidade e contracheques.

Está sujeito à **LGPD** (Lei 13.709/2018) e às regulamentações do **Banco Central do Brasil**.

Uma falha de segurança neste sistema pode expor dados de clientes, gerar multas regulatórias,
responsabilidade civil e destruir a confiança na marca Walker Bank.

**Segurança não é opcional. É requisito de negócio.**

---

## PROBLEMA DOCUMENTADO

Pesquisas de 2025-2026 mostram que código gerado por IA contém:
- 45% de vulnerabilidades OWASP Top 10 (Veracode, 2025)
- 65% dos apps vibe-coded têm falhas de segurança (Escape.tech, 1.400 apps)
- 100% dos apps testados sem CSRF protection e sem security headers (Tenzai, 2025)
- Credenciais hardcoded em 3.2% dos commits com IA vs 1.5% sem IA

**Você não deve repetir esses erros. Jamais.**

---

## REGRA 0 — NUNCA FAÇA ISSO

```
❌ PROIBIDO — O agente NUNCA deve:

1. Colocar chaves, senhas ou tokens diretamente no código
   Ex: const SECRET = "minha_senha_aqui"  ← NUNCA

2. Criar endpoints sem verificar se o usuário está autenticado
   Ex: app.get('/api/propostas', (req, res) => { ... })  ← sem auth = NUNCA

3. Usar dados do usuário diretamente em queries sem sanitização
   Ex: db.query("SELECT * WHERE cpf = " + req.body.cpf)  ← NUNCA

4. Retornar erros detalhados do servidor para o cliente
   Ex: res.json({ error: err.stack })  ← NUNCA

5. Salvar CPF, conta ou agência em texto puro no banco
   Ex: cpf: "123.456.789-00"  ← NUNCA sem criptografia

6. Aceitar upload de arquivo sem validar tipo e tamanho
   Ex: upload.any()  ← NUNCA

7. Criar tokens JWT com secret fraco ou hardcoded
   Ex: jwt.sign(data, "secret")  ← NUNCA

8. Confiar em headers HTTP como X-User-ID vindos do cliente
   Ex: const userId = req.headers['x-user-id']  ← NUNCA sem validação

9. Expor stack traces, nomes de tabelas ou estrutura do banco em erros
10. Fazer commit de arquivos .env ou qualquer arquivo com credenciais
```

---

## REGRA 1 — VARIÁVEIS DE AMBIENTE

**Toda credencial, chave e configuração sensível DEVE vir de variável de ambiente.**

```javascript
// ✅ CORRETO — sempre assim
const db = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

const JWT_SECRET = process.env.JWT_SECRET;
// Validar na inicialização:
if (!JWT_SECRET) throw new Error('JWT_SECRET não configurado');

// ✅ Arquivo .env.example (commitar este — sem valores reais)
SUPABASE_URL=https://sua-instancia.supabase.co
SUPABASE_SERVICE_KEY=sua_chave_aqui
JWT_SECRET=gere_um_segredo_com_64_chars_aleatorios
MAKE_WEBHOOK_URL=https://hook.make.com/seu_webhook

// ✅ Arquivo .gitignore (SEMPRE incluir)
.env
.env.local
.env.production
*.key
*.pem
```

**Ao criar qualquer arquivo de configuração, verificar automaticamente se .gitignore existe
e se .env está listado nele. Se não estiver, adicionar antes de prosseguir.**

---

## REGRA 2 — AUTENTICAÇÃO E AUTORIZAÇÃO

**Todo endpoint privado DEVE verificar autenticação. Sem exceção.**

```javascript
// ✅ Middleware de autenticação — aplicar em TODAS as rotas privadas
async function autenticar(req, reply) {
  const token = req.headers.authorization?.split(' ')[1];

  if (!token) {
    return reply.status(401).send({ erro: 'Não autorizado' });
  }

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.operador = payload;
  } catch {
    return reply.status(401).send({ erro: 'Token inválido ou expirado' });
  }
}

// ✅ Aplicar em rotas protegidas
fastify.get('/api/propostas', { preHandler: autenticar }, handler);
fastify.put('/api/propostas/:id', { preHandler: autenticar }, handler);

// ✅ Verificar se o operador tem permissão para o recurso específico
// Nunca assumir que "estar logado" = "pode ver tudo"
async function verificarPermissao(operadorId, propostaId) {
  // Operador só vê propostas atribuídas a ele (exceto admin/supervisor)
}
```

**Rotas PÚBLICAS permitidas (sem auth):**
- `POST /api/proposta` — receber proposta do formulário público
- `GET /health` — health check

**Todas as outras rotas exigem token JWT válido.**

---

## REGRA 3 — VALIDAÇÃO DE INPUTS

**Nunca confiar em dados vindos do cliente. Validar TUDO no servidor.**

```javascript
// ✅ Instalar e usar biblioteca de validação
// npm install zod

import { z } from 'zod';

const schemaPropostaLead = z.object({
  nome: z.string().min(3).max(200).regex(/^[a-zA-ZÀ-ÿ\s]+$/),
  cpf: z.string().regex(/^\d{11}$/, 'CPF deve ter 11 dígitos sem formatação'),
  data_nascimento: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  celular: z.string().regex(/^\d{10,11}$/),
  email: z.string().email().max(254),
});

const schemaDadosFuncionais = z.object({
  convenio: z.enum(['inss', 'mil', 'est', 'mun']),
  matricula: z.string().min(4).max(50).regex(/^\d+$/),
  salario_liquido: z.number().positive().max(999999),
  uf_orgao: z.enum(['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA',
                     'MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN',
                     'RS','RO','RR','SC','SP','SE','TO']),
});

// ✅ Validar antes de qualquer operação
const resultado = schemaPropostaLead.safeParse(req.body);
if (!resultado.success) {
  return reply.status(400).send({
    erro: 'Dados inválidos',
    detalhes: resultado.error.flatten().fieldErrors
    // Não expor detalhes internos — só erros de campo
  });
}
```

---

## REGRA 4 — PROTEÇÃO CONTRA INJEÇÃO

**Nunca construir queries com concatenação de strings.**

```javascript
// ❌ ERRADO — SQL Injection
const resultado = await db.query(
  "SELECT * FROM propostas WHERE cpf = '" + cpf + "'"
);

// ✅ CORRETO — Supabase com parâmetros (proteção automática)
const { data, error } = await supabase
  .from('propostas')
  .select('*')
  .eq('cpf_hash', hashCPF(cpf));

// ✅ Se usar queries raw, SEMPRE com parâmetros
const { data } = await supabase.rpc('buscar_por_cpf', { cpf_param: cpf });
```

---

## REGRA 5 — CRIPTOGRAFIA DE DADOS SENSÍVEIS

**CPF, agência e conta bancária NUNCA em texto puro no banco.**

```javascript
import crypto from 'crypto';

const ENCRYPTION_KEY = Buffer.from(process.env.ENCRYPTION_KEY, 'hex');
// ENCRYPTION_KEY deve ser 32 bytes (64 chars hex) gerado com:
// node -e "console.log(crypto.randomBytes(32).toString('hex'))"

// ✅ Criptografar antes de salvar
function criptografar(texto) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', ENCRYPTION_KEY, iv);
  const criptografado = Buffer.concat([
    cipher.update(texto, 'utf8'),
    cipher.final()
  ]);
  const authTag = cipher.getAuthTag();
  return {
    iv: iv.toString('hex'),
    dados: criptografado.toString('hex'),
    tag: authTag.toString('hex')
  };
}

// ✅ Hash do CPF para busca (não é reversível — use para índice)
function hashCPF(cpf) {
  const cpfLimpo = cpf.replace(/\D/g, '');
  return crypto
    .createHmac('sha256', process.env.CPF_HASH_SECRET)
    .update(cpfLimpo)
    .digest('hex');
}

// ✅ Na tabela: salvar cpf_hash (para busca) + cpf_encrypted (para exibir)
// Nunca salvar CPF em texto plano
```

---

## REGRA 6 — UPLOAD DE ARQUIVOS

**Validar tipo, tamanho e conteúdo. Nunca servir arquivos de upload diretamente.**

```javascript
// ✅ Configuração segura de upload
const TIPOS_PERMITIDOS = ['image/jpeg', 'image/png', 'application/pdf'];
const TAMANHO_MAXIMO = 10 * 1024 * 1024; // 10MB

async function validarArquivo(file) {
  // Verificar pelo magic bytes, não só pela extensão
  const tipoReal = await fileTypeFromBuffer(file.buffer);

  if (!tipoReal || !TIPOS_PERMITIDOS.includes(tipoReal.mime)) {
    throw new Error('Tipo de arquivo não permitido');
  }

  if (file.size > TAMANHO_MAXIMO) {
    throw new Error('Arquivo muito grande (máximo 10MB)');
  }

  // Renomear arquivo — nunca usar o nome original do usuário
  const nomeSeguro = `${crypto.randomUUID()}.${tipoReal.ext}`;
  return nomeSeguro;
}

// ✅ Salvar no Supabase Storage com caminho que inclui proposta_id
// Nunca salvar na pasta raiz ou com nome previsível
const path = `documentos/${proposta_id}/${nomeSeguro}`;
```

---

## REGRA 7 — HEADERS DE SEGURANÇA HTTP

**Todo servidor deve incluir estes headers em TODAS as respostas.**

```javascript
// ✅ Registrar plugin de headers no Fastify
fastify.addHook('onSend', (req, reply, payload, done) => {
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.header('X-Frame-Options', 'DENY');
  reply.header('X-XSS-Protection', '1; mode=block');
  reply.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin');
  reply.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  reply.header(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' fonts.googleapis.com; font-src fonts.gstatic.com; img-src 'self' data:; connect-src 'self'"
  );
  done();
});
```

---

## REGRA 8 — RATE LIMITING

**Proteger todos os endpoints contra abuso e força bruta.**

```javascript
// ✅ npm install @fastify/rate-limit

await fastify.register(import('@fastify/rate-limit'), {
  global: true,
  max: 100,           // 100 requests
  timeWindow: '1 minute',
  errorResponseBuilder: () => ({
    erro: 'Muitas requisições. Aguarde um momento.'
  })
});

// Limite mais restrito para endpoint público de proposta
fastify.post('/api/proposta', {
  config: { rateLimit: { max: 10, timeWindow: '1 minute' } }
}, handler);

// Limite para autenticação — evitar brute force
fastify.post('/api/auth/login', {
  config: { rateLimit: { max: 5, timeWindow: '15 minutes' } }
}, handler);
```

---

## REGRA 9 — CORS

**Nunca usar CORS aberto (`*`) em produção.**

```javascript
// ✅ npm install @fastify/cors

await fastify.register(import('@fastify/cors'), {
  origin: [
    'https://walkerbank.com.br',
    'https://www.walkerbank.com.br',
    // Em desenvolvimento apenas:
    ...(process.env.NODE_ENV === 'development' ? ['http://localhost:3000'] : [])
  ],
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
});

// ❌ NUNCA em produção:
// origin: '*'
// origin: true
```

---

## REGRA 10 — TRATAMENTO DE ERROS

**Nunca expor detalhes internos. Logar no servidor, mensagem genérica para o cliente.**

```javascript
// ✅ Handler global de erros no Fastify
fastify.setErrorHandler((error, req, reply) => {
  // Logar internamente com detalhes completos
  fastify.log.error({
    err: error,
    url: req.url,
    method: req.method,
    operador: req.operador?.id
  });

  // Para o cliente: mensagem genérica
  if (error.statusCode >= 400 && error.statusCode < 500) {
    return reply.status(error.statusCode).send({
      erro: error.message // Erros de validação podem ser detalhados
    });
  }

  // Erros 500: nunca expor stack trace
  return reply.status(500).send({
    erro: 'Erro interno. Por favor, tente novamente.'
    // Não incluir: error.message, error.stack, nomes de tabelas, etc.
  });
});
```

---

## REGRA 11 — LOGS DE AUDITORIA LGPD

**Registrar todas as ações sobre dados sensíveis com timestamp do servidor.**

```javascript
// ✅ Logar sempre que dados sensíveis são acessados ou modificados
async function logarAcesso(tipo, operadorId, propostaId, detalhes = {}) {
  await supabase.from('audit_log').insert({
    tipo,              // 'acesso_documento' | 'mudanca_status' | 'exportacao'
    operador_id: operadorId,
    proposta_id: propostaId,
    ip: req.ip,
    detalhes,
    created_at: new Date().toISOString() // Sempre servidor, nunca cliente
  });
}

// ✅ Usar em:
// - Abertura de documento (RG, contracheque)
// - Mudança de status de proposta
// - Acesso ao CPF descriptografado
// - Login/logout de operadores
// - Exportação de dados
```

---

## REGRA 12 — SIGNED URLS PARA DOCUMENTOS

**Documentos nunca públicos. Sempre URLs temporárias com expiração.**

```javascript
// ✅ Gerar URL assinada com expiração de 60 minutos
async function gerarUrlDocumento(path, operadorId, propostaId) {
  // Logar acesso antes de gerar URL
  await logarAcesso('acesso_documento', operadorId, propostaId, { path });

  const { data, error } = await supabase
    .storage
    .from('documentos')
    .createSignedUrl(path, 3600); // 3600 segundos = 60 minutos

  if (error) throw new Error('Erro ao gerar acesso ao documento');

  return data.signedUrl;
}

// ❌ NUNCA retornar URL pública permanente de documentos
```

---

## CHECKLIST — ANTES DE CADA COMMIT

O agente deve verificar automaticamente:

```
SEGURANÇA — verificar antes de finalizar qualquer tarefa:

[ ] Nenhuma credencial hardcoded no código
    → buscar por: password, secret, key, token seguidos de = "..."

[ ] Arquivo .env está no .gitignore

[ ] Todos os endpoints privados têm middleware de autenticação

[ ] Inputs do usuário são validados com Zod antes de usar

[ ] Nenhuma query construída com concatenação de string

[ ] CPF e dados bancários criptografados antes de salvar

[ ] Upload valida tipo pelo magic bytes, não pela extensão

[ ] Headers de segurança configurados

[ ] Rate limiting ativo nos endpoints públicos

[ ] CORS configurado com origins específicos (não *)

[ ] Erros 500 não expõem stack trace para o cliente

[ ] Ações sobre dados sensíveis registradas em audit_log

[ ] Documentos acessados via signed URL com expiração

[ ] JWT_SECRET tem no mínimo 64 caracteres aleatórios

[ ] ENCRYPTION_KEY tem exatamente 32 bytes (64 chars hex)
```

---

## DEPENDÊNCIAS DE SEGURANÇA OBRIGATÓRIAS

```json
{
  "dependencies": {
    "zod": "^3.x",
    "jsonwebtoken": "^9.x",
    "file-type": "^19.x",
    "@fastify/rate-limit": "^9.x",
    "@fastify/cors": "^9.x",
    "@fastify/helmet": "^11.x",
    "@fastify/multipart": "^8.x"
  },
  "devDependencies": {
    "dotenv": "^16.x"
  }
}
```

---

## REFERÊNCIAS DOS PROBLEMAS REAIS DOCUMENTADOS

Estes são os incidentes que motivam estas regras:

| Caso real | Problema | Impacto |
|---|---|---|
| Quittr (app de hábitos) | Firebase database público | 39.000+ usuários expostos |
| Lovable platform scan | Secrets e API keys expostos | 175 instâncias de dados pessoais vazados |
| Base44 platform | Bypass de autenticação via app_id público | Acesso não autorizado a apps privados |
| Moltbook (rede social IA) | Vulnerabilidades críticas | Credenciais de usuários expostas em semanas |
| Tenzai study (15 apps) | 69 vulnerabilidades, 100% sem CSRF | Todos os 5 top tools afetados |

> Fonte: Escape.tech (1.400 apps), Georgia Tech Vibe Security Radar,
> Veracode GenAI Report 2025, Wiz Research, Tenzai December 2025

---

*Walker Bank — Prompt de segurança obrigatório para todos os agentes*
*Versão 1.0 — Baseado em OWASP Top 10 2025 + incidentes documentados de vibe coding*
