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

-- 3. Políticas de acesso
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
    COALESCE(NEW.raw_user_meta_data->>'role', 'operador'),
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
