-- ============================================================
-- WALKER BANK — Setup da tabela de perfis de usuários
-- Execute este script no SQL Editor do Supabase
-- (Dashboard → SQL Editor → New Query → Cole e execute)
-- ============================================================

-- 1. Cria a tabela de perfis
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID        REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  nome        TEXT        NOT NULL DEFAULT 'Usuário',
  role        TEXT        NOT NULL DEFAULT 'operador' CHECK (role IN ('admin', 'operador')),
  avatar      TEXT,
  meta_mensal NUMERIC     DEFAULT 100000,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Habilita RLS (Row Level Security)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 3. Políticas de acesso para a tabela profiles
-- Remove se já existirem para evitar o erro 42710
DROP POLICY IF EXISTS "Leitura de perfis autenticados" ON public.profiles;
DROP POLICY IF EXISTS "Atualização do próprio perfil" ON public.profiles;
DROP POLICY IF EXISTS "Admin atualiza qualquer perfil" ON public.profiles;

-- Qualquer usuário autenticado pode ler todos os perfis (para listar operadores)
CREATE POLICY "Leitura de perfis autenticados"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (true);

-- Usuários podem atualizar o próprio perfil
CREATE POLICY "Atualização do próprio perfil"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

-- Admin pode atualizar qualquer perfil (necessário para gestão de operadores no dashboard)
CREATE POLICY "Admin atualiza qualquer perfil"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 4. Trigger: cria automaticamente um perfil quando um novo usuário é criado no Auth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, nome, role, avatar)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1)),
    CASE 
      WHEN NEW.email LIKE '%raulfiuza%' THEN 'admin'
      ELSE COALESCE(NEW.raw_user_meta_data->>'role', 'operador')
    END,
    COALESCE(NEW.raw_user_meta_data->>'avatar', upper(left(split_part(NEW.email, '@', 1), 2)))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 5. Tabela de configurações globais do sistema (HBI, comissões, convênios, etc.)
CREATE TABLE IF NOT EXISTS public.configs (
  id    TEXT  PRIMARY KEY,
  data  JSONB NOT NULL DEFAULT '{}'
);
ALTER TABLE public.configs ENABLE ROW LEVEL SECURITY;

-- Remove se já existirem para evitar o erro 42710
DROP POLICY IF EXISTS "Configs leitura autenticados" ON public.configs;
DROP POLICY IF EXISTS "Configs insert autenticados" ON public.configs;
DROP POLICY IF EXISTS "Configs update autenticados" ON public.configs;

CREATE POLICY "Configs leitura autenticados"
  ON public.configs FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Configs insert autenticados"
  ON public.configs FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Configs update autenticados"
  ON public.configs FOR UPDATE
  TO authenticated
  USING (true);

-- 6. Sincronização Retroativa de Usuários Órfãos
-- Insere perfis para usuários que já foram cadastrados no Auth mas ainda não têm perfil correspondente
INSERT INTO public.profiles (id, nome, role, avatar)
SELECT
  id,
  COALESCE(raw_user_meta_data->>'nome', split_part(email, '@', 1)),
  CASE 
    WHEN email LIKE '%raulfiuza%' THEN 'admin'
    ELSE COALESCE(raw_user_meta_data->>'role', 'operador')
  END,
  COALESCE(raw_user_meta_data->>'avatar', upper(left(split_part(email, '@', 1), 2)))
FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- 7. Força atualização do papel (role) de admin para usuários existentes contendo 'raulfiuza'
UPDATE public.profiles
SET role = 'admin'
WHERE id IN (
  SELECT id FROM auth.users WHERE email LIKE '%raulfiuza%'
);

-- ============================================================
-- PASSO MANUAL APÓS EXECUTAR:
--
-- 1. Vá em Authentication → Users no Supabase
-- 2. Localize seu usuário admin (ex: matheusaleks@gmail.com)
-- 3. Vá em Table Editor → profiles → encontre a linha do seu usuário
-- 4. Altere o campo "role" de 'operador' para 'admin'
--
-- Para criar um operador:
-- 1. Authentication → Users → Invite User (ou Add User)
-- 2. Informe o e-mail do operador
-- 3. O perfil é criado automaticamente com role = 'operador'
-- 4. Edite o campo "nome" e "avatar" na tabela profiles se quiser
-- ============================================================

-- 8. Tabela de leads (propostas de crédito consignado e consultas de margem)
CREATE TABLE IF NOT EXISTS public.leads (
  id               TEXT        PRIMARY KEY, -- ID pode ser UUID ou texto estruturado (ex: lead-import-...)
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  nome             TEXT        NOT NULL,
  cpf              TEXT        NOT NULL,
  status           TEXT        NOT NULL DEFAULT 'Recebida',
  convenio         TEXT,
  valor_solicitado NUMERIC,
  payload          JSONB       NOT NULL DEFAULT '{}'
);

-- Habilita RLS para a tabela de leads
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;

-- Políticas de acesso para a tabela de leads
DROP POLICY IF EXISTS "Leitura de leads autenticados" ON public.leads;
DROP POLICY IF EXISTS "Inserção de leads anônimos ou autenticados" ON public.leads;
DROP POLICY IF EXISTS "Atualização de leads autenticados" ON public.leads;

-- Qualquer usuário autenticado (operador/admin) pode ler todos os leads
CREATE POLICY "Leitura de leads autenticados"
  ON public.leads FOR SELECT
  TO authenticated
  USING (true);

-- Qualquer usuário (mesmo anônimo na LP de captura) pode criar um lead
CREATE POLICY "Inserção de leads anônimos ou autenticados"
  ON public.leads FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Usuários autenticados (operadores/admins) podem atualizar os leads
CREATE POLICY "Atualização de leads autenticados"
  ON public.leads FOR UPDATE
  TO authenticated
  USING (true);

-- Usuários autenticados (operadores/admins) podem excluir leads
DROP POLICY IF EXISTS "Exclusão de leads autenticados" ON public.leads;
CREATE POLICY "Exclusão de leads autenticados"
  ON public.leads FOR DELETE
  TO authenticated
  USING (true);

-- 9. Tabela de auditoria (log de acessos a dados sensíveis - LGPD)
CREATE TABLE IF NOT EXISTS public.audit_log (
  id           BIGSERIAL   PRIMARY KEY,
  tipo         TEXT        NOT NULL,
  operador_id  TEXT,
  proposta_id  TEXT,
  detalhes     JSONB       DEFAULT '{}',
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Inserção de audit_log autenticados" ON public.audit_log;
CREATE POLICY "Inserção de audit_log autenticados"
  ON public.audit_log FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Leitura de audit_log autenticados" ON public.audit_log;
CREATE POLICY "Leitura de audit_log autenticados"
  ON public.audit_log FOR SELECT
  TO authenticated
  USING (true);

