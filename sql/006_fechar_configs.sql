-- ============================================================
-- WALKER BANK — fecha a tabela `configs` para quem não está logado
--
-- RODE SÓ DEPOIS de publicar o index.html/proposta.html que usam
-- public.config_publica() (criada no 005). Antes disso, o simulador do site
-- lia a `configs` inteira sem login — expondo salários, metas e comissões dos
-- operadores e a URL do bancarizador.
--
-- Depois deste script:
--   * leitura: só admin/operador (o site público usa config_publica());
--   * escrita: só admin (já era assim pelo 002).
-- Policies antigas removidas são guardadas em public.backup_policies_removidas.
-- ============================================================

BEGIN;

-- Segurança: não fecha se a função pública não existir (o site ficaria sem taxas)
DO $$
BEGIN
  IF to_regprocedure('public.config_publica()') IS NULL THEN
    RAISE EXCEPTION 'Rode o 005 antes: public.config_publica() não existe';
  END IF;
END $$;

INSERT INTO public.backup_policies_removidas (schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check)
SELECT schemaname, tablename, policyname, permissive, roles::text[], cmd, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'configs'
   AND policyname NOT IN ('Configs leitura autenticados', 'Configs insert admin', 'Configs update admin');

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT policyname FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'configs'
       AND policyname NOT IN ('Configs leitura autenticados', 'Configs insert admin', 'Configs update admin')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.configs', r.policyname);
  END LOOP;
END $$;

ALTER TABLE public.configs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Configs leitura autenticados" ON public.configs;
CREATE POLICY "Configs leitura autenticados"
  ON public.configs FOR SELECT TO authenticated
  USING (public.is_staff());

COMMIT;

SELECT tablename, policyname, cmd, roles::text
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'configs'
 ORDER BY cmd, policyname;
