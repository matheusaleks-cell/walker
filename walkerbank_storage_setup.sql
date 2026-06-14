-- ============================================================
-- WALKER BANK — Setup do Supabase Storage para documentos
-- Execute este script no SQL Editor do Supabase
-- (Dashboard → SQL Editor → New Query → Cole e execute)
-- ============================================================

-- 1. Cria o bucket privado para documentos de leads
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'walkerbank-docs',
  'walkerbank-docs',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- 2. Políticas de acesso ao bucket

-- Anônimos podem fazer upload (proposta.html não exige login)
CREATE POLICY "Anon pode fazer upload de documentos"
ON storage.objects FOR INSERT
TO anon
WITH CHECK (
  bucket_id = 'walkerbank-docs'
  AND name LIKE 'leads/%'
);

-- Usuários autenticados (dashboard) podem ler/gerar URLs assinadas
CREATE POLICY "Autenticados podem ler documentos"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'walkerbank-docs');

-- Usuários autenticados podem substituir documentos (upsert no dashboard)
CREATE POLICY "Autenticados podem atualizar documentos"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'walkerbank-docs');

-- Usuários autenticados podem deletar documentos
CREATE POLICY "Autenticados podem deletar documentos"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'walkerbank-docs');

-- ============================================================
-- NOTA:
-- Os arquivos são organizados por lead:
--   leads/{lead_id}/rg.{ext}
--   leads/{lead_id}/contracheque.{ext}
--   leads/{lead_id}/outros_0.{ext}
--   leads/{lead_id}/outros_1.{ext}  ...
--
-- Os campos arquivos.identidade_cnh_rg e arquivos.contracheque
-- dentro do payload JSONB agora armazenam o PATH no storage
-- (ex: "leads/proposta-abc123/rg.jpg"), não mais base64.
-- O dashboard gera URLs assinadas (1h) para exibir/baixar.
-- ============================================================
