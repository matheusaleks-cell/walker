-- ============================================================
-- WALKER BANK — Diagnóstico: quais leads não aparecem no dashboard (e por quê)
-- Somente LEITURA. Rode no SQL Editor do Supabase; devolve UMA tabela só
-- (o editor mostra apenas o resultado do último comando, por isso é uma query única).
-- ============================================================
with n as (
  select id, status, convenio, created_at, nome, payload,
         coalesce(cpf, '') as cpf,
         regexp_replace(coalesce(cpf, ''), '\D', '', 'g') as d
    from public.leads
),
vis as (  -- o que a Base Geral considera
  select * from n where status in ('Consulta de Margem', 'Importado')
),
alvo as ( -- lead do AM que sabemos que existe (MARCELO FRAZAO CORREA)
  select created_at from n where id = 'f9789c1c-4185-4b72-bcdb-5a7dd6b33013'
)
select ord, verificacao, qtd, exemplo from (

  select 1 ord, 'Total de leads no banco' verificacao, count(*) qtd, null::text exemplo from n
  union all
  select 2, 'Aparecem na Base Geral (status Importado / Consulta de Margem)', count(*), null from vis

  -- Hipótese principal: janela de 200 leads mais novos carregada ao abrir o dashboard
  union all
  select 3, 'Leads MAIS NOVOS que o lead do AM (se > 200, ele fica fora da carga inicial)',
         count(*), null from n, alvo where n.created_at > alvo.created_at

  -- Datas das importações em massa (empurram os antigos para fora da janela)
  union all
  select 4, 'Criados em ' || created_at::date::text, count(*), null
    from n where created_at > now() - interval '60 days' group by created_at::date

  -- Status que o dashboard não reconhece em nenhuma tela
  union all
  select 5, 'Status desconhecido: ' || coalesce(status, '(nulo)'), count(*), min(cpf)
    from n
   where status is null
      or status not in ('Consulta de Margem','Importado','Prospectado','Agendado','Recebida','Novo',
                        'Pendente','Em Análise','Aguardando Assinatura','Aguardando Averbação',
                        'Aprovada','Aprovado','Recusada','Recusado','Paga','Em Digitação','Descartado')
   group by status

  -- Problemas de CPF que quebram a busca (a busca compara os dígitos digitados com o CPF gravado)
  union all
  select 6, 'CPF vazio ou com menos de 8 dígitos', count(*), min(id) from n where length(d) < 8
  union all
  select 7, 'CPF SEM zeros à esquerda (8–10 dígitos): busca pelo CPF completo não acha', count(*), min(cpf)
    from n where length(d) between 8 and 10
  union all
  select 8, 'CPF com pontos/traço (formatado)', count(*), min(cpf) from n where cpf ~ '\D'
  union all
  select 9, 'CPF com mais de 11 dígitos', count(*), min(cpf) from n where length(d) > 11

  -- Duplicidade (a Base Geral junta por CPF; excedente = linhas repetidas)
  union all
  select 10, 'Linhas repetidas por CPF entre os visíveis', coalesce(sum(c - 1), 0), null
    from (select d, count(*) c from vis group by d having count(*) > 1) x

  -- Dados que deixam o lead "sem cara" na lista
  union all
  select 11, 'Visíveis sem nome', count(*), min(cpf) from vis where coalesce(trim(nome), '') = ''
  union all
  select 12, 'Visíveis com payload que não é objeto JSON', count(*), min(id)
    from vis where jsonb_typeof(payload) is distinct from 'object'
  union all
  select 13, 'Visíveis sem convênio (somem do filtro por convênio)', count(*), min(cpf)
    from vis where coalesce(trim(convenio), '') = ''

  -- Quantos há por convênio entre os visíveis (confira com as planilhas: AM 18.040 / 9.002 etc.)
  union all
  select 14, 'Base Geral por convênio: ' || coalesce(nullif(convenio, ''), '(vazio)'), count(*), null
    from vis group by convenio

  -- Leads do AM por status (todos os status)
  union all
  select 15, 'AM (convênio govam) com status ' || coalesce(status, '(nulo)'), count(*), null
    from n where convenio = 'govam' group by status

) t
order by ord, qtd desc, verificacao;
