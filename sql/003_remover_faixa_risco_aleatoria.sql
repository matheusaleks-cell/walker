-- ============================================================
-- WALKER BANK — Remove a "faixa de risco" sorteada (OPCIONAL)
--
-- Até 2026-10, a importação de planilha gravava em cada lead novo uma
-- proposta.score_faixa SORTEADA (Math.random) entre RISCO BAIXO / MÉDIO /
-- MUITO BAIXO / ALTO. Nenhum outro ponto do sistema grava esse campo, então
-- os valores existentes não têm base real.
--
-- Este script:
--   1. guarda uma cópia (id + valor) em public.backup_score_faixa — nada se perde;
--   2. remove proposta.score_faixa de todos os leads.
-- A tela passa a mostrar "-" na faixa de risco desses leads.
--
-- Como aplicar: Supabase → SQL Editor → cole tudo → Run.
-- Antes, se quiser ver quantos serão afetados:
--   select count(*) from public.leads where payload->'proposta' ? 'score_faixa';
--
-- Para desfazer (restaurar os valores antigos):
--   update public.leads l
--      set payload = jsonb_set(l.payload, '{proposta,score_faixa}', b.score_faixa)
--     from public.backup_score_faixa b
--    where b.id = l.id;
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.backup_score_faixa (
  id          TEXT PRIMARY KEY,
  score_faixa JSONB,
  salvo_em    TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.backup_score_faixa ENABLE ROW LEVEL SECURITY; -- sem policies: só SQL Editor acessa

INSERT INTO public.backup_score_faixa (id, score_faixa)
SELECT id, payload->'proposta'->'score_faixa'
  FROM public.leads
 WHERE payload->'proposta' ? 'score_faixa'
ON CONFLICT (id) DO NOTHING;

UPDATE public.leads
   SET payload = jsonb_set(payload, '{proposta}', (payload->'proposta') - 'score_faixa')
 WHERE payload->'proposta' ? 'score_faixa';

COMMIT;
