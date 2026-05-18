-- =============================================================================
-- MÓDULO 08: Storage, Assets Institucionais e Instrutores
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Linhas relevantes: 10222-10298 (institutional_assets), 10298-10327 (instrutores),
--                    13080-13149 (views), 14511-14640 (storage.*),
--                    17901-17960 (RLS)
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABELAS — Storage nativo Supabase
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL
);
ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";
COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';

CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb"
);
ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";
COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';

-- -----------------------------------------------------------------------------
-- TABELAS — Assets Institucionais (public schema)
-- Linhas dump: 10222-10265
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "public"."institutional_assets" (
    -- DDL completo: ver dump linhas 10222-10242
    -- Colunas: asset_id, tipo, url, forca, versao, ativo, checksum, cache_policy, created_at, asset_key
    -- NOTA: asset_key é o identificador lógico usado por instrutores.avatar_asset_tipo etc.
);
-- Ver dump remoto para DDL completo de institutional_assets

CREATE TABLE IF NOT EXISTS "public"."institutional_notices" (
    -- DDL completo: ver dump linhas 10250-10265
    -- Colunas: id, title, body, created_at, priority, deep_link, ativo
);

CREATE TABLE IF NOT EXISTS "public"."institutional_notice_reads" (
    -- DDL completo: ver dump linhas 10240-10252
    -- Colunas: id, notice_id, recruta_id, read_at
);

CREATE TABLE IF NOT EXISTS "public"."instructor_messages" (
    -- DDL completo: ver dump linhas 10273-10290
    -- Colunas: id, title, body, created_at, deep_link, ativo
);

CREATE TABLE IF NOT EXISTS "public"."instructor_message_reads" (
    -- DDL completo: ver dump linhas 10263-10278
    -- Colunas: id, message_id, recruta_id, read_at
);

-- -----------------------------------------------------------------------------
-- TABELAS — Instrutores (Wave 1 RCC-0.5)
-- Linhas dump: 10298-10327
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "public"."instrutores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "descricao" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "ordem_exibicao" integer DEFAULT 100 NOT NULL,
    "avatar_asset_tipo" "text",
    "chat_icon_asset_tipo" "text",
    "whatsapp_asset_tipo" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "card_selected_asset_tipo" "text",
    "card_idle_asset_tipo" "text"
);
ALTER TABLE "public"."instrutores" OWNER TO "postgres";
COMMENT ON TABLE "public"."instrutores" IS 'RCC-0.5 Wave 1: catálogo de personas visuais institucionais de instrutores. Não representa IA nem provider.';
COMMENT ON COLUMN "public"."instrutores"."slug" IS 'Slug institucional lógico usado por recrutas.instructor_profile_id. Valores Wave 1: objetivo, estrategico, didatico.';

-- -----------------------------------------------------------------------------
-- VIEWS — Assets e Instrutores
-- Linhas dump: 13080-13149
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW "public"."v_institutional_assets" AS
 SELECT "asset_id",
    "tipo",
    "url",
    "forca",
    "versao",
    "ativo",
    "checksum",
    "cache_policy",
    "created_at",
    "asset_key"
   FROM "public"."institutional_assets"
  WHERE ("ativo" = true);
ALTER VIEW "public"."v_institutional_assets" OWNER TO "postgres";

CREATE OR REPLACE VIEW "public"."v_institutional_notices" AS
 SELECT "id" AS "notice_id",
    "title",
    "body",
    "created_at",
    "priority",
    "deep_link",
    false AS "is_read"
   FROM "public"."institutional_notices" "n";
ALTER VIEW "public"."v_institutional_notices" OWNER TO "postgres";

CREATE OR REPLACE VIEW "public"."v_instructor_messages" AS
 SELECT "id" AS "message_id",
    "title",
    "body",
    "created_at",
    "deep_link",
    false AS "is_read"
   FROM "public"."instructor_messages" "m";
ALTER VIEW "public"."v_instructor_messages" OWNER TO "postgres";

CREATE OR REPLACE VIEW "public"."v_instrutores_app" WITH ("security_invoker"='true') AS
 SELECT "i"."id" AS "instrutor_id",
    "i"."slug",
    "i"."codigo",
    "i"."nome",
    "i"."titulo",
    "i"."descricao",
    "ia"."url" AS "avatar_url",
    "ci"."url" AS "chat_icon_url",
    "wa"."url" AS "whatsapp_avatar_url",
    "cs"."url" AS "card_selected_url",
    "cid"."url" AS "card_idle_url",
    "i"."ordem_exibicao",
    "i"."ativo"
   FROM ((((("public"."instrutores" "i"
     LEFT JOIN "public"."v_institutional_assets" "ia" ON (("ia"."asset_key" = "i"."avatar_asset_tipo")))
     LEFT JOIN "public"."v_institutional_assets" "ci" ON (("ci"."asset_key" = "i"."chat_icon_asset_tipo")))
     LEFT JOIN "public"."v_institutional_assets" "wa" ON (("wa"."asset_key" = "i"."whatsapp_asset_tipo")))
     LEFT JOIN "public"."v_institutional_assets" "cs" ON (("cs"."asset_key" = "i"."card_selected_asset_tipo")))
     LEFT JOIN "public"."v_institutional_assets" "cid" ON (("cid"."asset_key" = "i"."card_idle_asset_tipo")))
  WHERE ("i"."ativo" = true);
ALTER VIEW "public"."v_instrutores_app" OWNER TO "postgres";

-- -----------------------------------------------------------------------------
-- RLS POLICIES — Assets e Instrutores
-- Linhas dump: 17901-17960
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."institutional_assets" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "institutional_assets_select_active" ON "public"."institutional_assets"
    FOR SELECT TO "authenticated" USING (("ativo" = true));

ALTER TABLE "public"."instrutores" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "instrutores_select_authenticated" ON "public"."instrutores"
    FOR SELECT TO "authenticated" USING (("ativo" = true));
CREATE POLICY "instrutores_no_direct_insert" ON "public"."instrutores"
    FOR INSERT TO "authenticated" WITH CHECK (false);
CREATE POLICY "instrutores_no_direct_update" ON "public"."instrutores"
    FOR UPDATE TO "authenticated" USING (false) WITH CHECK (false);
CREATE POLICY "instrutores_no_direct_delete" ON "public"."instrutores"
    FOR DELETE TO "authenticated" USING (false);

ALTER TABLE "public"."institutional_notices" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."institutional_notice_reads" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."instructor_messages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."instructor_message_reads" ENABLE ROW LEVEL SECURITY;

-- RLS STORAGE
ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- BUCKETS INSTITUCIONAIS CONHECIDOS
-- =============================================================================
-- Bucket: avatars (criado por migration 20240114221000_storage_avatars.sql)
-- Bucket: institutional-assets (criado para assets Wave 1)
--
-- NOTA: Os dados de buckets (INSERT INTO storage.buckets) são de dados, não DDL.
-- Verificar com: SELECT id, name, public FROM storage.buckets;
-- =============================================================================
