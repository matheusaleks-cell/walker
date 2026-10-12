-- ============================================================
-- WALKER BANK — Religa documentos do Storage às fichas dos leads
--
-- Por quê: até 2026-10, várias telas do painel regravavam o payload do lead
-- a partir da lista "leve" (sem `arquivos`) e apagavam do banco a referência
-- aos documentos. Os ARQUIVOS continuam no bucket `walkerbank-docs`, em
--   leads/{lead_id}/rg.{ext}
--   leads/{lead_id}/contracheque.{ext}
--   leads/{lead_id}/outros_{n}.{ext}
-- e o lead_id do caminho é o id da linha em public.leads.
--
-- O que faz (só ACRESCENTA, nunca apaga nem troca um documento que já está na ficha):
--   * RG / contracheque: preenche só se o campo estiver vazio na ficha
--     (se houver mais de um arquivo, usa o mais recente);
--   * outros_N: acrescenta à lista `outros` os arquivos que ainda não estão nela;
--   * antes de alterar, guarda `arquivos` de cada lead afetado em
--     public.backup_arquivos_leads (dá para desfazer — ver final do arquivo).
--
-- Roda em transação: se algo falhar, nada muda. Pode rodar mais de uma vez.
-- Como aplicar: Supabase → SQL Editor → cole tudo → Run.
--
-- PRÉVIA (opcional, rode antes, sozinha — não altera nada): o que seria religado
--   with f as (
--     select split_part(name,'/',2) lead_id,
--            regexp_replace(split_part(name,'/',3), '\.[^.]*$', '') tipo, name
--       from storage.objects
--      where bucket_id = 'walkerbank-docs' and name like 'leads/%/%' and split_part(name,'/',4) = ''
--   )
--   select f.tipo, count(*) total_no_storage,
--          count(*) filter (where l.id is null) sem_lead_no_banco
--     from f left join public.leads l on l.id = f.lead_id
--    group by f.tipo order by f.tipo;
-- ============================================================

BEGIN;

-- Tabelas de trabalho normais (não temporárias: o SQL Editor do Supabase não
-- enxerga tabela TEMP entre comandos). São apagadas no fim deste script.
DROP TABLE IF EXISTS public.wb_tmp_docs;
DROP TABLE IF EXISTS public.wb_tmp_afetados;

-- 0. Arquivos do bucket, já com lead_id e tipo extraídos do caminho
CREATE TABLE public.wb_tmp_docs AS
SELECT split_part(o.name, '/', 2)                                   AS lead_id,
       regexp_replace(split_part(o.name, '/', 3), '\.[^.]*$', '')   AS tipo,
       split_part(o.name, '/', 3)                                   AS arquivo,
       o.name                                                       AS path,
       COALESCE(o.metadata->>'mimetype', '')                        AS mime,
       o.created_at
  FROM storage.objects o
 WHERE o.bucket_id = 'walkerbank-docs'
   AND o.name LIKE 'leads/%/%'
   AND split_part(o.name, '/', 4) = '';          -- só leads/{id}/{arquivo}
ALTER TABLE public.wb_tmp_docs ENABLE ROW LEVEL SECURITY; -- não exposta pela API enquanto existir

-- Leads que serão alterados (para backup e relatório)
CREATE TABLE public.wb_tmp_afetados AS
SELECT DISTINCT l.id
  FROM public.leads l
  JOIN public.wb_tmp_docs d ON d.lead_id = l.id
 WHERE jsonb_typeof(l.payload) = 'object'
   AND (
        (d.tipo = 'rg'
         AND COALESCE(l.payload->'arquivos'->>'identidade_cnh_rg', '') IN ('', 'null', 'presente', 'anexo_presente_no_banco'))
     OR (d.tipo = 'contracheque'
         AND COALESCE(l.payload->'arquivos'->>'contracheque', '') IN ('', 'null', 'presente', 'anexo_presente_no_banco'))
     OR (d.tipo LIKE 'outros\_%'
         AND NOT EXISTS (
               SELECT 1
                 FROM jsonb_array_elements(
                        CASE WHEN jsonb_typeof(l.payload->'arquivos'->'outros') = 'array'
                             THEN l.payload->'arquivos'->'outros' ELSE '[]'::jsonb END) e
                WHERE e->>'path' = d.path))
   );
ALTER TABLE public.wb_tmp_afetados ENABLE ROW LEVEL SECURITY;

-- 1. Backup do `arquivos` atual de cada lead afetado
CREATE TABLE IF NOT EXISTS public.backup_arquivos_leads (
  id        TEXT        NOT NULL,
  arquivos  JSONB,
  salvo_em  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, salvo_em)
);
ALTER TABLE public.backup_arquivos_leads ENABLE ROW LEVEL SECURITY; -- sem policies: só SQL Editor acessa

INSERT INTO public.backup_arquivos_leads (id, arquivos)
SELECT l.id, l.payload->'arquivos'
  FROM public.leads l
 WHERE l.id IN (SELECT id FROM public.wb_tmp_afetados);

-- 2. Garante que `arquivos` é um objeto (pode estar ausente ou null)
UPDATE public.leads l
   SET payload = jsonb_set(l.payload, '{arquivos}', '{}'::jsonb, true)
 WHERE l.id IN (SELECT id FROM public.wb_tmp_afetados)
   AND jsonb_typeof(l.payload->'arquivos') IS DISTINCT FROM 'object';

-- 3. RG (mais recente) — só onde está vazio
UPDATE public.leads l
   SET payload = jsonb_set(l.payload, '{arquivos,identidade_cnh_rg}', to_jsonb(d.path), true)
  FROM (SELECT DISTINCT ON (lead_id) lead_id, path
          FROM public.wb_tmp_docs WHERE tipo = 'rg'
         ORDER BY lead_id, created_at DESC) d
 WHERE d.lead_id = l.id
   AND l.id IN (SELECT id FROM public.wb_tmp_afetados)
   AND COALESCE(l.payload->'arquivos'->>'identidade_cnh_rg', '') IN ('', 'null', 'presente', 'anexo_presente_no_banco');

-- 4. Contracheque (mais recente) — só onde está vazio
UPDATE public.leads l
   SET payload = jsonb_set(l.payload, '{arquivos,contracheque}', to_jsonb(d.path), true)
  FROM (SELECT DISTINCT ON (lead_id) lead_id, path
          FROM public.wb_tmp_docs WHERE tipo = 'contracheque'
         ORDER BY lead_id, created_at DESC) d
 WHERE d.lead_id = l.id
   AND l.id IN (SELECT id FROM public.wb_tmp_afetados)
   AND COALESCE(l.payload->'arquivos'->>'contracheque', '') IN ('', 'null', 'presente', 'anexo_presente_no_banco');

-- 5. Outros documentos — acrescenta à lista os que faltam (mesmo formato da página de proposta)
UPDATE public.leads l
   SET payload = jsonb_set(
         l.payload, '{arquivos,outros}',
         (CASE WHEN jsonb_typeof(l.payload->'arquivos'->'outros') = 'array'
               THEN l.payload->'arquivos'->'outros' ELSE '[]'::jsonb END) || n.novos,
         true)
  FROM (
        SELECT d.lead_id,
               jsonb_agg(jsonb_build_object('nome', d.arquivo, 'tipo', d.mime, 'path', d.path)
                         ORDER BY d.path) AS novos
          FROM public.wb_tmp_docs d
          JOIN public.leads l2 ON l2.id = d.lead_id
         WHERE d.tipo LIKE 'outros\_%'
           AND jsonb_typeof(l2.payload) = 'object'
           AND NOT EXISTS (
                 SELECT 1
                   FROM jsonb_array_elements(
                          CASE WHEN jsonb_typeof(l2.payload->'arquivos'->'outros') = 'array'
                               THEN l2.payload->'arquivos'->'outros' ELSE '[]'::jsonb END) e
                  WHERE e->>'path' = d.path)
         GROUP BY d.lead_id
       ) n
 WHERE n.lead_id = l.id;

-- Limpa as tabelas de trabalho
DROP TABLE public.wb_tmp_docs;
DROP TABLE public.wb_tmp_afetados;

COMMIT;

-- 6. Relatório (último comando = é o que o SQL Editor mostra)
SELECT 'leads com documento religado nesta execução' AS item,
       count(*)::text AS total
  FROM public.backup_arquivos_leads
 WHERE salvo_em = (SELECT max(salvo_em) FROM public.backup_arquivos_leads)
   AND salvo_em > NOW() - INTERVAL '10 minutes'
UNION ALL
SELECT 'arquivos no storage sem lead no banco (proposta que não chegou a ser salva)',
       count(*)::text
  FROM storage.objects o
 WHERE o.bucket_id = 'walkerbank-docs'
   AND o.name LIKE 'leads/%/%'
   AND NOT EXISTS (SELECT 1 FROM public.leads l WHERE l.id = split_part(o.name, '/', 2));

-- ------------------------------------------------------------
-- Arquivos ÓRFÃOS (documento enviado, mas o lead não existe no banco —
-- geralmente proposta cujo envio falhou depois do upload). Não são apagados.
-- Para listar e avaliar manualmente:
--   select o.name, o.created_at from storage.objects o
--    where o.bucket_id = 'walkerbank-docs' and o.name like 'leads/%/%'
--      and not exists (select 1 from public.leads l where l.id = split_part(o.name,'/',2))
--    order by o.created_at desc;
--
-- DESFAZER (volta `arquivos` ao estado salvo na última execução):
--   update public.leads l set payload = jsonb_set(l.payload, '{arquivos}', coalesce(b.arquivos, 'null'::jsonb), true)
--     from (select distinct on (id) id, arquivos from public.backup_arquivos_leads order by id, salvo_em desc) b
--    where b.id = l.id;
-- ------------------------------------------------------------
