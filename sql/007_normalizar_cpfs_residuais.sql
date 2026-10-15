-- ============================================================
-- WALKER BANK — Limpeza dos casos residuais encontrados no diagnóstico de 2026-10-15
--   * 1 CPF gravado sem zeros à esquerda (ex.: 9453443840)
--   * 1 CPF gravado formatado (ex.: 407.839.522-87)
--   * 1 lead de teste com status 'x' e CPF 00000000000
-- Idempotente. Rode primeiro o SELECT de conferência (abaixo) e depois o bloco BEGIN..COMMIT.
-- ============================================================

-- Conferência: o que será alterado
select id, cpf, nome, status
  from public.leads
 where (cpf ~ '\D' or length(cpf) < 11)
    or (status = 'x' and cpf = '00000000000');

BEGIN;

-- 1. CPF só com dígitos e 11 posições (coluna e cópia dentro do payload)
update public.leads
   set cpf = lpad(regexp_replace(cpf, '\D', '', 'g'), 11, '0'),
       payload = case
         when jsonb_typeof(payload) = 'object' and payload ? 'lead' and jsonb_typeof(payload->'lead') = 'object'
           then jsonb_set(payload, '{lead,cpf}',
                          to_jsonb(lpad(regexp_replace(cpf, '\D', '', 'g'), 11, '0')))
         else payload end
 where (cpf ~ '\D' or length(cpf) < 11)
   and length(regexp_replace(cpf, '\D', '', 'g')) between 8 and 11;

-- 2. Lead de teste: sai da lista sem apagar o registro (reversível)
update public.leads
   set status = 'Descartado'
 where status = 'x' and cpf = '00000000000';

COMMIT;
