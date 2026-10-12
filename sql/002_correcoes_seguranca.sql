-- ============================================================
-- WALKER BANK — Correções de segurança (auditoria de 2026-09-30)
-- Cobre: C1 (escalada de privilégio), C2 (role vindo do cliente / e-mail
-- "raulfiuza"), C3 (configs/leads/audit_log/storage abertos) e C4 (INSERT anônimo).
--
-- Como aplicar: Supabase → SQL Editor → New query → cole tudo → Run.
-- É idempotente (pode rodar mais de uma vez) e roda em uma transação:
-- se algo falhar, nada é alterado.
--
-- ANTES DE RODAR, confirme que existe pelo menos 1 admin real:
--   select p.id, u.email, p.role from public.profiles p
--   join auth.users u on u.id = p.id where p.role = 'admin';
-- Este script NÃO rebaixa ninguém, mas depois dele só um admin existente
-- consegue promover/rebaixar usuários.
--
-- IMPORTANTE: rode junto com a versão do dashboard.html que promove o operador
-- recém-cadastrado (após o signUp). A partir deste script, todo usuário novo
-- nasce com role 'pendente' e não enxerga leads/documentos até ser liberado.
-- Assim o cadastro público (signUp com a chave publicável) deixa de dar acesso,
-- sem precisar desligar o signup (que o dashboard usa para criar operadores).
--
-- NÃO coberto aqui:
--   * Isolar leads por operador (o dashboard depende de operadores verem a
--     Base Geral; fazer isso exige mudar o front junto).
--   * Tabela `notifications`: não está versionada no repositório; as policies
--     dela devem ser revisadas no painel (Table Editor → notifications → RLS).
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 0. Helper: is_admin()
-- SECURITY DEFINER evita recursão de RLS ao consultar profiles dentro
-- de uma policy de profiles.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- is_staff(): admin OU operador ativo. Usuário 'pendente' (criado por signUp
-- público ou pelo painel e ainda não liberado por um admin) não passa.
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'operador')
  );
$$;

REVOKE ALL ON FUNCTION public.is_staff() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;

-- Novo valor de role 'pendente' (não altera ninguém que já existe).
-- Remove qualquer CHECK antigo sobre role, seja qual for o nome dele.
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.profiles'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%role%'
  LOOP
    EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check CHECK (role IN ('admin', 'operador', 'pendente'));

-- M7: colunas usadas pelo dashboard que não estavam versionadas (aditivo, não apaga nada)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS salario_base    NUMERIC DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS sonho_titulo    TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS sonho_valor     NUMERIC DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS sonho_acumulado NUMERIC DEFAULT 0;

-- ------------------------------------------------------------
-- 1. C1 — profiles: ninguém (exceto admin) altera `role` nem o `id`
-- ------------------------------------------------------------
-- A policy "Atualização do próprio perfil" continua permitindo editar
-- nome/avatar/meta/sonho do próprio perfil, mas o trigger abaixo barra
-- qualquer mudança de role por quem não é admin.
CREATE OR REPLACE FUNCTION public.protect_profile_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION 'Não é permitido alterar o id do perfil';
  END IF;

  -- auth.uid() é NULL no SQL Editor / service_role: manutenção manual liberada.
  IF NEW.role IS DISTINCT FROM OLD.role
     AND auth.uid() IS NOT NULL
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar o role';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_role ON public.profiles;
CREATE TRIGGER trg_protect_profile_role
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_role();

DROP POLICY IF EXISTS "Atualização do próprio perfil" ON public.profiles;
CREATE POLICY "Atualização do próprio perfil"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Admin atualiza qualquer perfil" ON public.profiles;
CREATE POLICY "Admin atualiza qualquer perfil"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Sem INSERT/DELETE direto em profiles pela API (o INSERT é feito pelo trigger
-- handle_new_user, que é SECURITY DEFINER e ignora RLS).

-- ------------------------------------------------------------
-- 2. C2 — handle_new_user: ignora role do metadata e a regra do e-mail
-- ------------------------------------------------------------
-- Todo usuário novo nasce 'pendente' (sem acesso a leads/documentos).
-- O dashboard, ao cadastrar um operador, já promove para o role escolhido
-- (o admin logado tem permissão). Usuário criado direto no painel do Supabase
-- precisa ter o role trocado para 'operador'/'admin' no Table Editor.
-- Quem já é admin/operador continua igual.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, nome, role, avatar)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1)),
    'pendente',
    COALESCE(NEW.raw_user_meta_data->>'avatar', upper(left(split_part(NEW.email, '@', 1), 2)))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- 3. C3 — configs: leitura para autenticados, escrita só admin
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Configs insert autenticados" ON public.configs;
DROP POLICY IF EXISTS "Configs update autenticados" ON public.configs;
DROP POLICY IF EXISTS "Configs insert admin" ON public.configs;
DROP POLICY IF EXISTS "Configs update admin" ON public.configs;

CREATE POLICY "Configs insert admin"
  ON public.configs FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin());

CREATE POLICY "Configs update admin"
  ON public.configs FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ------------------------------------------------------------
-- 4. C3/C4 — leads
-- ------------------------------------------------------------
-- 4.1 INSERT: anônimo só cria proposta nova com o status inicial da LP e
--     sem atribuição de operador. Autenticado (importador do dashboard)
--     continua livre.
DROP POLICY IF EXISTS "Inserção de leads anônimos ou autenticados" ON public.leads;
DROP POLICY IF EXISTS "Inserção de leads anônimos (LP)" ON public.leads;
DROP POLICY IF EXISTS "Inserção de leads autenticados" ON public.leads;

CREATE POLICY "Inserção de leads anônimos (LP)"
  ON public.leads FOR INSERT
  TO anon
  WITH CHECK (
    status = 'Aguardando Averbação'
    AND payload ->> 'operador_id'   IS NULL
    AND payload ->> 'operador_nome' IS NULL
    AND length(nome) BETWEEN 1 AND 200
    AND length(cpf)  BETWEEN 11 AND 14
    AND pg_column_size(payload) < 5 * 1024 * 1024   -- 5 MB (cobre o fallback base64 atual)
  );

CREATE POLICY "Inserção de leads autenticados"
  ON public.leads FOR INSERT
  TO authenticated
  WITH CHECK (public.is_staff());

-- Leitura/edição: só admin e operador (usuário 'pendente' não vê nada).
-- Mantém a visão da Base Geral para operadores, como o dashboard espera.
DROP POLICY IF EXISTS "Leitura de leads autenticados" ON public.leads;
CREATE POLICY "Leitura de leads autenticados"
  ON public.leads FOR SELECT
  TO authenticated
  USING (public.is_staff());

DROP POLICY IF EXISTS "Atualização de leads autenticados" ON public.leads;
CREATE POLICY "Atualização de leads autenticados"
  ON public.leads FOR UPDATE
  TO authenticated
  USING (public.is_staff())
  WITH CHECK (public.is_staff());

-- 4.2 DELETE: só admin
DROP POLICY IF EXISTS "Exclusão de leads autenticados" ON public.leads;
DROP POLICY IF EXISTS "Exclusão de leads admin" ON public.leads;
CREATE POLICY "Exclusão de leads admin"
  ON public.leads FOR DELETE
  TO authenticated
  USING (public.is_admin());

-- 4.3 Índices (B7): cpf para busca/duplicidade, status e created_at para o dashboard.
--     Não cria UNIQUE em cpf: a mesma pessoa pode ter mais de uma proposta.
CREATE INDEX IF NOT EXISTS idx_leads_cpf        ON public.leads (cpf);
CREATE INDEX IF NOT EXISTS idx_leads_status     ON public.leads (status);
CREATE INDEX IF NOT EXISTS idx_leads_created_at ON public.leads (created_at DESC);

-- ------------------------------------------------------------
-- 5. M1 — audit_log: operador_id não pode ser forjado
-- ------------------------------------------------------------
-- Operador só grava log no próprio nome. O admin pode gravar em nome de
-- outro operador porque o modo "Visualizar como" do dashboard atribui a ação
-- ao operador visualizado (exigir auth.uid() aqui faria esses logs sumirem).
-- Leitura continua para a equipe porque o histórico do lead é exibido para operadores.
DROP POLICY IF EXISTS "Inserção de audit_log autenticados" ON public.audit_log;
CREATE POLICY "Inserção de audit_log autenticados"
  ON public.audit_log FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_admin()
    OR (public.is_staff() AND operador_id = auth.uid()::text)
  );

DROP POLICY IF EXISTS "Leitura de audit_log autenticados" ON public.audit_log;
CREATE POLICY "Leitura de audit_log autenticados"
  ON public.audit_log FOR SELECT
  TO authenticated
  USING (public.is_staff());

-- ------------------------------------------------------------
-- 6. C3 — Storage walkerbank-docs: remoção só admin
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Autenticados podem deletar documentos" ON storage.objects;
DROP POLICY IF EXISTS "Admin pode deletar documentos" ON storage.objects;
CREATE POLICY "Admin pode deletar documentos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'walkerbank-docs' AND public.is_admin());

DROP POLICY IF EXISTS "Autenticados podem ler documentos" ON storage.objects;
CREATE POLICY "Autenticados podem ler documentos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'walkerbank-docs' AND public.is_staff());

DROP POLICY IF EXISTS "Autenticados podem atualizar documentos" ON storage.objects;
CREATE POLICY "Autenticados podem atualizar documentos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'walkerbank-docs' AND public.is_staff())
  WITH CHECK (bucket_id = 'walkerbank-docs' AND public.is_staff());

-- ------------------------------------------------------------
-- 7. Bucket: aceita também foto de iPhone (HEIC/HEIF). Não remove nenhum tipo
--    já aceito; só acrescenta. Limite de 10MB por arquivo mantido.
-- ------------------------------------------------------------
UPDATE storage.buckets
   SET allowed_mime_types = ARRAY(
         SELECT DISTINCT unnest(
           COALESCE(allowed_mime_types, ARRAY[]::text[])
           || ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/pdf', 'image/heic', 'image/heif']
         )
       )
 WHERE id = 'walkerbank-docs'
   AND allowed_mime_types IS NOT NULL; -- NULL = já aceita tudo; não restringir

COMMIT;

-- ------------------------------------------------------------
-- VERIFICAÇÃO (rode depois, separado)
-- ------------------------------------------------------------
-- select tablename, policyname, cmd, roles from pg_policies
--  where schemaname in ('public','storage')
--    and tablename in ('profiles','configs','leads','audit_log','objects')
--  order by tablename, cmd;
--
-- Teste manual: logado como operador, no console do navegador:
--   await supabaseClient.from('profiles').update({role:'admin'}).eq('id', (await supabaseClient.auth.getUser()).data.user.id)
--   → deve retornar erro "Apenas administradores podem alterar o role".
