-- =============================================================================
-- MÓDULO 01: Tabelas Core do Sistema
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: Tabelas fundamentais — recrutas, profiles, modulos, aulas, forcas,
--          xp_eventos, materialized views de ranking
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- forcas — Catálogo de Forças Armadas
-- Linhas dump: 10193-10205
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."forcas" (
    "id" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "cor_primaria" "text" NOT NULL,
    "cor_secundaria" "text" NOT NULL,
    "cor_fundo" "text" NOT NULL,
    "icone" "text",
    "ativo" boolean DEFAULT true
);
ALTER TABLE "public"."forcas" OWNER TO "postgres";

-- -----------------------------------------------------------------------------
-- recrutas — Perfil gamificado (tabela canônica de identidade)
-- Linhas dump: 8365-8392
-- NOTA: id ≠ auth.uid(). auth_id = auth.uid(). Usar WHERE auth_id = auth.uid()
-- NOTA: forca aceita APENAS 'marinha','exercito','aeronautica' no remoto
-- NOTA: recrutas.xp atualizado por complete_lesson; não tem registrar_xp no dump
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."recrutas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "auth_id" "uuid" NOT NULL,
    "nome" "text",
    "email" "text" NOT NULL,
    "forca" "text" NOT NULL,
    "patente" "text" DEFAULT 'Recruta'::"text",
    "plano" "text",
    "status" "text" DEFAULT 'ativo'::"text",
    "data_pagamento" timestamp without time zone,
    "validade" timestamp without time zone,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "onboarding_concluido" boolean DEFAULT false,
    "patente_virtual" "text" DEFAULT 'Recruta'::"text",
    "thread_id" "text",
    "nome_guerra" "text",
    "instructor_profile_id" "text",
    CONSTRAINT "chk_forca_valida" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "recrutas_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"])))
);
ALTER TABLE ONLY "public"."recrutas" FORCE ROW LEVEL SECURITY;
ALTER TABLE "public"."recrutas" OWNER TO "postgres";

-- NOTA IMPORTANTE: recrutas NÃO tem xp_total como campo separado no dump.
-- A coluna xp existe em profiles, mas não confirmada em recrutas neste dump.
-- Verificar: SELECT column_name FROM information_schema.columns WHERE table_name = 'recrutas';

-- -----------------------------------------------------------------------------
-- profiles — Perfil institucional
-- Linhas dump: 10868-10899
-- NOTA: Direct frontend access forbidden. Use RCC views and canonical RPCs only.
-- NOTA: instructor_profile_id CHECK constraint: apenas 'objetivo','estrategico','didatico'
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "username" "text",
    "nome" "text" NOT NULL,
    "role" "text" DEFAULT 'recruta'::"text",
    "nivel_atual" "text" DEFAULT 'Tropa Base'::"text",
    "ativo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "email" "text",
    "whatsapp" "text",
    "tipo_acesso" "text" DEFAULT 'degustacao'::"text",
    "origem" "text" DEFAULT 'app'::"text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "paid_at" timestamp with time zone,
    "xp" integer DEFAULT 0 NOT NULL,
    "forca" "text" DEFAULT 'marinha'::"text" NOT NULL,
    "patente" "text" DEFAULT 'Recruta'::"text" NOT NULL,
    "foto" "text",
    "instructor_profile_id" "text" DEFAULT 'objetivo'::"text",
    CONSTRAINT "chk_forca_profiles" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "instructor_profile_check" CHECK (("instructor_profile_id" = ANY (ARRAY['objetivo'::"text", 'estrategico'::"text", 'didatico'::"text"]))),
    CONSTRAINT "profiles_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"])))
);
ALTER TABLE "public"."profiles" OWNER TO "postgres";
COMMENT ON TABLE "public"."profiles" IS 'CORE BLOCKED TABLE. Direct frontend access forbidden. Use RCC views and canonical RPCs only. RLS enabled.';

-- -----------------------------------------------------------------------------
-- modulos — Catálogo de Módulos de Aprendizagem
-- Linhas dump: 10607-10622
-- NOTA: ordem (não "order") é a coluna de ordenação
-- NOTA: forca CHECK constraint: apenas 'marinha','exercito','aeronautica'
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."modulos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "forca" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "descricao" "text",
    "ordem" integer NOT NULL,
    "ativo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_degustacao" boolean DEFAULT false,
    CONSTRAINT "chk_forca_modulos" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "modulos_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"])))
);
ALTER TABLE "public"."modulos" OWNER TO "postgres";

-- -----------------------------------------------------------------------------
-- aulas — Catálogo de Aulas
-- Linhas dump: 9075-9088
-- NOTA CRÍTICA: coluna canônica é "modulo_id" (não "module_id")
-- NOTA: "ordem" é a coluna de ordenação (não "order")
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."aulas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "modulo_id" "uuid" NOT NULL,
    "titulo" "text" NOT NULL,
    "ordem" integer NOT NULL,
    "xp_valor" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "video_url" "text",
    "pdf_url" "text"
);
ALTER TABLE "public"."aulas" OWNER TO "postgres";

-- -----------------------------------------------------------------------------
-- xp_eventos — Ledger de XP (append-only, service_role apenas)
-- Linhas dump: 10756-10770
-- NOTA CRÍTICA: A tabela no dump usa 'quantidade' (não 'amount' nem 'xp')
-- NOTA CRÍTICA: recruta_id é a coluna primária (não user_id)
-- NOTA: Comparar com MEMORY.md que diz user_id/amount como originais — drift!
-- NOTA: Colunas 'user_id', 'amount', 'xp' podem existir como aliases adicionados
--       por migration 20260503001000 mas NÃO aparecem no DDL do dump
-- PROTEÇÃO: xp_eventos_insert_block — authenticated não pode fazer INSERT direto
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."xp_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "forca" "text" NOT NULL,
    "quantidade" integer NOT NULL,
    "origem" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "referencia_id" "uuid",
    CONSTRAINT "xp_eventos_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "xp_eventos_quantidade_check" CHECK (("quantidade" > 0))
);
ALTER TABLE "public"."xp_eventos" OWNER TO "postgres";

-- -----------------------------------------------------------------------------
-- Materialized Views de Ranking
-- Linhas dump: 10772-10807
-- NOTA: mv_xp_mensal_recruta usa 'mes_referencia' e 'xp_total'
--       (diferente de MEMORY.md que diz 'month_ref' e 'xp_mensal')
-- NOTA: mv_ranking_mensal usa 'posicao' (não 'rank_position')
-- NOTA: Requerem REFRESH agendado — não há pg_cron configurado nas migrations
-- -----------------------------------------------------------------------------

CREATE MATERIALIZED VIEW "public"."mv_xp_mensal_recruta" AS
 SELECT "recruta_id",
    "forca",
    ("date_trunc"('month'::"text", "created_at"))::"date" AS "mes_referencia",
    "sum"("quantidade") AS "xp_total"
   FROM "public"."xp_eventos" "xe"
  GROUP BY "recruta_id", "forca", ("date_trunc"('month'::"text", "created_at"))
  WITH NO DATA;
ALTER MATERIALIZED VIEW "public"."mv_xp_mensal_recruta" OWNER TO "postgres";

CREATE MATERIALIZED VIEW "public"."mv_ranking_mensal" AS
 SELECT "recruta_id",
    "forca",
    "mes_referencia",
    "xp_total",
    "rank"() OVER (PARTITION BY "forca", "mes_referencia" ORDER BY "xp_total" DESC) AS "posicao"
   FROM "public"."mv_xp_mensal_recruta" "x"
  WITH NO DATA;
ALTER MATERIALIZED VIEW "public"."mv_ranking_mensal" OWNER TO "postgres";

CREATE MATERIALIZED VIEW "public"."mv_campeao_mensal" AS
 SELECT "recruta_id",
    "forca",
    "mes_referencia"
   FROM "public"."mv_ranking_mensal" "r"
  WHERE ("posicao" = 1)
  WITH NO DATA;
ALTER MATERIALIZED VIEW "public"."mv_campeao_mensal" OWNER TO "postgres";

-- -----------------------------------------------------------------------------
-- recruta_status — Status gamificado (nível, xp, patente)
-- Linhas dump: 8350-8363
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "public"."recruta_status" (
    "recruta_id" "uuid" NOT NULL,
    "nivel" integer DEFAULT 1 NOT NULL,
    "xp" integer DEFAULT 0 NOT NULL,
    "ultima_atividade" "date",
    "dias_consecutivos" integer DEFAULT 0,
    "honra_maxima" boolean DEFAULT false,
    "atualizado_em" timestamp with time zone DEFAULT "now"(),
    "patente" "text" DEFAULT 'ASPIRANTE'::"text" NOT NULL
);
ALTER TABLE "public"."recruta_status" OWNER TO "postgres";

-- =============================================================================
-- NOTAS DE DIVERGÊNCIA CRÍTICAS
-- =============================================================================
-- 1. xp_eventos.quantidade no dump ≠ xp_eventos.amount na MEMORY.md (ver DRIFT_REPORT.md)
-- 2. xp_eventos não tem coluna 'xp' no DDL do dump (pode existir como alias adicionado por ALTER)
-- 3. mv_xp_mensal_recruta.mes_referencia ≠ MEMORY.md month_ref (ver DRIFT_REPORT.md)
-- 4. mv_ranking_mensal.posicao ≠ MEMORY.md rank_position (ver DRIFT_REPORT.md)
-- 5. recrutas.xp_total: não encontrado como campo no dump (possível campo não no DDL?)
-- =============================================================================
