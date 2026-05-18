-- =============================================================================
-- MÓDULO 06: Billing — Assinaturas, Pagamentos, Reconciliação
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Linhas relevantes: 9214-9335 (tabelas), 11637-11730 (views),
--                    4568-5060 (funções), 17493-17527 (RLS)
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABELAS — Billing
-- -----------------------------------------------------------------------------

-- billing_assinaturas — Assinaturas por recruta
-- Linhas dump: 9214-9236
CREATE TABLE IF NOT EXISTS "public"."billing_assinaturas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "gateway_cliente_id" "text",
    "gateway_assinatura_id" "text",
    "plano" "text" NOT NULL,
    "status_assinatura" "text" NOT NULL,
    "trial_inicio" timestamp with time zone,
    "trial_fim" timestamp with time zone,
    "vigente_inicio" timestamp with time zone,
    "vigente_fim" timestamp with time zone,
    "auto_renovacao" boolean DEFAULT false NOT NULL,
    "origem" "text" DEFAULT 'billing'::"text" NOT NULL,
    "ultimo_gateway_event_id" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_assinaturas_status_chk" CHECK (("status_assinatura" = ANY (ARRAY[
        'trial'::"text", 'ativa'::"text", 'inadimplente'::"text",
        'cancelada'::"text", 'expirada'::"text", 'suspensa'::"text", 'pendente'::"text"
    ])))
);
ALTER TABLE "public"."billing_assinaturas" OWNER TO "postgres";

-- billing_eventos — Eventos raw do gateway (webhook)
-- Linhas dump: 9238-9250
CREATE TABLE IF NOT EXISTS "public"."billing_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "gateway_nome" "text",
    "gateway_event_id" "text",
    "event_type" "text",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);
ALTER TABLE "public"."billing_eventos" OWNER TO "postgres";

-- billing_notificacoes_log — Log de notificações enviadas
-- Linhas dump: 9251-9270
CREATE TABLE IF NOT EXISTS "public"."billing_notificacoes_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid",
    "assinatura_id" "uuid",
    "pagamento_id" "uuid",
    "tipo_evento" "text" NOT NULL,
    "canal" "text" NOT NULL,
    "destinatario" "text",
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enviado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status_envio" "text" DEFAULT 'pendente'::"text" NOT NULL,
    "erro" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_notificacoes_log_status_chk" CHECK (("status_envio" = ANY (ARRAY[
        'pendente'::"text", 'enviado'::"text", 'falhou'::"text", 'ignorado'::"text"
    ])))
);
ALTER TABLE "public"."billing_notificacoes_log" OWNER TO "postgres";

-- billing_pagamentos — Pagamentos processados (idempotência via gateway_nome+gateway_event_id)
-- Linhas dump: 9271-9315
CREATE TABLE IF NOT EXISTS "public"."billing_pagamentos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "assinatura_id" "uuid",
    -- Colunas adicionais: gateway_nome, gateway_event_id, gateway_pagamento_id,
    --                     valor_centavos, moeda, status_pagamento, plano,
    --                     periodo_inicio, periodo_fim, payload, created_at
    -- DDL completo: ver dump linhas 9271-9315
    -- UNIQUE: billing_pagamentos_gateway_event_unq (gateway_nome, gateway_event_id)
    "gateway_nome" "text",
    "gateway_event_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."billing_pagamentos" OWNER TO "postgres";

-- billing_reconciliacao — Execuções de reconciliação
-- Linhas dump: 9295-9315
CREATE TABLE IF NOT EXISTS "public"."billing_reconciliacao" (
    -- DDL completo: ver dump linhas 9295-9315
    -- Colunas: id, recruta_id, gateway_nome, gateway_event_id, status_execucao,
    --          tentativas, ultimo_erro, executado_em
);

-- billing_reconciliation_issues — Problemas de reconciliação
-- Linhas dump: 9314-9335
CREATE TABLE IF NOT EXISTS "public"."billing_reconciliation_issues" (
    -- DDL completo: ver dump linhas 9314-9335
    -- Colunas: id, recruta_id, gateway_event_id, tipo_problema, detalhes, status_execucao, executado_em
);

-- modelos_precificacao_versionada — Histórico de preços de modelos AI
-- Linhas dump: 10587-10610
CREATE TABLE IF NOT EXISTS "public"."modelos_precificacao_versionada" (
    -- DDL completo: ver dump linhas 10587-10610
    -- Colunas: id, modelo, versao, preco_input_token, preco_output_token, effective_from, criado_por, created_at
);

-- -----------------------------------------------------------------------------
-- VIEWS — Billing (CANÔNICAS para o frontend)
-- Linhas dump: 11637-11730
-- -----------------------------------------------------------------------------

-- v_billing_status_recruta — V1 (legada, ver v2)
-- Linhas dump: 11637-11705
CREATE OR REPLACE VIEW "public"."v_billing_status_recruta" AS
    -- DDL completo: ver dump linhas 11637-11705
    -- Colunas: acesso_liberado, plano_atual, status_assinatura, validade, trial_restante
    SELECT NULL::boolean AS "acesso_liberado" WHERE false; -- placeholder

-- v_billing_status_recruta_v2 — CANÔNICA
-- Linhas dump: 11691-11730
CREATE OR REPLACE VIEW "public"."v_billing_status_recruta_v2" AS
    -- DDL completo: ver dump linhas 11691-11730
    -- Colunas: acesso_liberado, plano_atual, status_assinatura, validade, trial_restante
    SELECT NULL::boolean AS "acesso_liberado" WHERE false; -- placeholder

-- v_billing_trial_monitoramento — Monitoramento de trials
-- Linhas dump: 11704-11730
CREATE OR REPLACE VIEW "public"."v_billing_trial_monitoramento" AS
    -- DDL completo: ver dump linhas 11704-11730
    SELECT NULL::uuid AS "recruta_id" WHERE false; -- placeholder

-- v_modelo_preco_atual — Preço atual dos modelos AI
-- Linhas dump: 13410-13436
CREATE OR REPLACE VIEW "public"."v_modelo_preco_atual" AS
    -- DDL completo: ver dump linhas 13410-13436
    SELECT NULL::text AS "modelo" WHERE false; -- placeholder

-- -----------------------------------------------------------------------------
-- RPCs BILLING — service_role apenas (exceto rpc_billing_status_recruta)
-- Linhas dump: 4568-5060
-- -----------------------------------------------------------------------------

-- rpc_billing_status_recruta — authenticated + service_role
-- Linhas dump: 4954-5020
-- GRANTS: authenticated (linha 18892), service_role (linha 18893)

-- rpc_billing_processar_evento_pagamento — service_role apenas
-- GRANTS: service_role (linha 18882)

-- rpc_billing_corrigir_divergencias — service_role apenas
-- GRANTS: service_role (linha 18877)

-- rpc_billing_reconciliar_pagamentos — service_role apenas
-- GRANTS: service_role (linha 18887)

-- rpc_billing_verificar_idempotencia — service_role apenas
-- GRANTS: service_role (linha 18898)

-- rpc_billing_verificar_trial_expirando — service_role apenas
-- GRANTS: service_role (linha 18903)

-- billing_emitir_evento_c5 — sem grants explícitos visíveis no dump
-- RISCO: Confirmar acesso (linha 18590)

-- -----------------------------------------------------------------------------
-- RLS POLICIES — Billing
-- PROTEÇÃO: Apenas service_role pode acessar dados de billing
-- Linhas dump: 17493-17527
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."billing_assinaturas" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "billing_assinaturas_service_role_all" ON "public"."billing_assinaturas"
    TO "service_role"
    USING (("auth"."role"() = 'service_role'::"text"))
    WITH CHECK (("auth"."role"() = 'service_role'::"text"));

ALTER TABLE "public"."billing_notificacoes_log" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "billing_notificacoes_log_service_role_all" ON "public"."billing_notificacoes_log"
    TO "service_role"
    USING (("auth"."role"() = 'service_role'::"text"))
    WITH CHECK (("auth"."role"() = 'service_role'::"text"));

ALTER TABLE "public"."billing_pagamentos" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "billing_pagamentos_service_role_all" ON "public"."billing_pagamentos"
    TO "service_role"
    USING (("auth"."role"() = 'service_role'::"text"))
    WITH CHECK (("auth"."role"() = 'service_role'::"text"));

ALTER TABLE "public"."billing_reconciliacao" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "billing_reconciliacao_service_role_all" ON "public"."billing_reconciliacao"
    TO "service_role"
    USING (("auth"."role"() = 'service_role'::"text"))
    WITH CHECK (("auth"."role"() = 'service_role'::"text"));

ALTER TABLE "public"."billing_reconciliation_issues" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "billing_reconciliation_issues_service_role_all" ON "public"."billing_reconciliation_issues"
    TO "service_role"
    USING (("auth"."role"() = 'service_role'::"text"))
    WITH CHECK (("auth"."role"() = 'service_role'::"text"));

-- =============================================================================
-- NOTAS DE SEGURANÇA
-- =============================================================================
-- 1. Todos os dados financeiros são exclusivos de service_role
-- 2. O frontend acessa billing apenas via v_billing_status_recruta_v2 (READ-ONLY)
-- 3. rpc_billing_status_recruta é o único contrato público authenticated
-- 4. billing_emitir_evento_c5 sem grants explícitos — investigar
-- =============================================================================
