-- ============================================================
-- WALKER BANK — URGENTE: fecha a leitura anônima da tabela leads
--
-- Teste de 2026-10-12 com a chave pública (sem login) conseguiu LER a tabela
-- `leads` (nome, CPF...) e a `configs`. O script 002 criou as policies
-- corretas, mas há policies ANTIGAS, com outros nomes (criadas no painel),
-- que continuam liberando acesso. No Postgres basta UMA policy permitir.
--
-- Este script:
--   1. guarda a definição de TODAS as policies que vai remover em
--      public.backup_policies_removidas (dá para recriar se precisar);
--   2. remove de `leads`, `audit_log` e do bucket `walkerbank-docs` toda policy
--      que não seja uma das criadas pelos scripts 002/005;
--   3. recria as policies corretas (idempotente);
--   4. cria public.config_publica(): devolve SÓ convênios e taxa de juros,
--      que é o que a página inicial e a de proposta precisam. A tabela
--      `configs` ainda NÃO é fechada aqui (o site atual lê direto dela);
--      isso é feito no 006, depois de publicar o código novo.
--
-- Como aplicar: SQL Editor → New query → cole TUDO → Run.
-- No fim aparece a lista das policies que ficaram em cada tabela.
-- ============================================================

BEGIN;

-- 1. Backup das policies que serão removidas
CREATE TABLE IF NOT EXISTS public.backup_policies_removidas (
  schemaname  TEXT,
  tablename   TEXT,
  policyname  TEXT,
  permissive  TEXT,
  roles       TEXT[],
  cmd         TEXT,
  qual        TEXT,
  with_check  TEXT,
  removida_em TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.backup_policies_removidas ENABLE ROW LEVEL SECURITY; -- sem policies: só SQL Editor

CREATE TABLE public.wb_tmp_policies_alvo AS
SELECT p.schemaname, p.tablename, p.policyname, p.permissive, p.roles::text[] AS roles, p.cmd, p.qual, p.with_check
  FROM pg_policies p
 WHERE (p.schemaname = 'public' AND p.tablename = 'leads' AND p.policyname NOT IN (
          'Inserção de leads anônimos (LP)',
          'Inserção de leads autenticados',
          'Leitura de leads autenticados',
          'Atualização de leads autenticados',
          'Exclusão de leads admin'))
    OR (p.schemaname = 'public' AND p.tablename = 'audit_log' AND p.policyname NOT IN (
          'Inserção de audit_log autenticados',
          'Leitura de audit_log autenticados'))
    OR (p.schemaname = 'storage' AND p.tablename = 'objects'
        AND (coalesce(p.qual, '') ILIKE '%walkerbank-docs%' OR coalesce(p.with_check, '') ILIKE '%walkerbank-docs%')
        AND p.policyname NOT IN (
          'Anon pode fazer upload de documentos',
          'Autenticados podem ler documentos',
          'Autenticados podem atualizar documentos',
          'Admin pode deletar documentos'));
ALTER TABLE public.wb_tmp_policies_alvo ENABLE ROW LEVEL SECURITY;

INSERT INTO public.backup_policies_removidas (schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check)
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  FROM public.wb_tmp_policies_alvo;

-- 2. Remove as policies antigas
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT schemaname, tablename, policyname FROM public.wb_tmp_policies_alvo LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;

DROP TABLE public.wb_tmp_policies_alvo;

-- 3. Garante RLS ligado e as policies corretas
ALTER TABLE public.leads     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Inserção de leads anônimos (LP)" ON public.leads;
CREATE POLICY "Inserção de leads anônimos (LP)"
  ON public.leads FOR INSERT
  TO anon
  WITH CHECK (
    status = 'Aguardando Averbação'
    AND payload ->> 'operador_id'   IS NULL
    AND payload ->> 'operador_nome' IS NULL
    AND length(nome) BETWEEN 1 AND 200
    AND length(cpf)  BETWEEN 11 AND 14
    AND pg_column_size(payload) < 5 * 1024 * 1024
  );

DROP POLICY IF EXISTS "Inserção de leads autenticados" ON public.leads;
CREATE POLICY "Inserção de leads autenticados"
  ON public.leads FOR INSERT TO authenticated
  WITH CHECK (public.is_staff());

DROP POLICY IF EXISTS "Leitura de leads autenticados" ON public.leads;
CREATE POLICY "Leitura de leads autenticados"
  ON public.leads FOR SELECT TO authenticated
  USING (public.is_staff());

DROP POLICY IF EXISTS "Atualização de leads autenticados" ON public.leads;
CREATE POLICY "Atualização de leads autenticados"
  ON public.leads FOR UPDATE TO authenticated
  USING (public.is_staff()) WITH CHECK (public.is_staff());

DROP POLICY IF EXISTS "Exclusão de leads admin" ON public.leads;
CREATE POLICY "Exclusão de leads admin"
  ON public.leads FOR DELETE TO authenticated
  USING (public.is_admin());

-- 4. Configuração pública mínima para o site (sem salários, metas, comissões, URLs internas)
CREATE OR REPLACE FUNCTION public.config_publica()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
           'convenios',  COALESCE(data->'convenios', '{}'::jsonb),
           'taxa_juros', data->'taxa_juros'
         )
    FROM public.configs
   WHERE id = 'default';
$$;
REVOKE ALL ON FUNCTION public.config_publica() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.config_publica() TO anon, authenticated;

COMMIT;

-- 5. Resultado: policies que ficaram (último comando = o que o SQL Editor mostra)
SELECT tablename, policyname, cmd, roles::text
  FROM pg_policies
 WHERE (schemaname = 'public' AND tablename IN ('leads', 'audit_log', 'configs'))
    OR (schemaname = 'storage' AND tablename = 'objects')
 ORDER BY tablename, cmd, policyname;

-- ------------------------------------------------------------
-- Ver o que foi removido:
--   select tablename, policyname, cmd, roles, qual, with_check, removida_em
--     from public.backup_policies_removidas order by removida_em desc;
-- ------------------------------------------------------------
