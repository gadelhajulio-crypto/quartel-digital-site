-- =============================================================================
-- Migration:  20260516004000_p0_m4_block_xp_events_legacy_insert.sql
-- Classificação: P0-M4 — Segurança
-- Data:       2026-05-16
-- Autor:      institutional-audit-2026-05-16
-- Revisão:    AGUARDANDO APROVAÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- OBJETIVO
-- --------
-- Bloquear INSERT direto em public.xp_events por usuários authenticated e anon,
-- eliminando o vetor de manipulação do sistema XP legado sem afetar as funções
-- SECURITY DEFINER que ainda usam a tabela como ledger de idempotência.
--
-- CONTEXTO
-- --------
-- A tabela public.xp_events é o ledger do sistema XP legado (pré-RCC).
-- Ela coexiste com a tabela canônica public.xp_eventos, mas os dois sistemas são
-- completamente independentes — sem sincronização, shadow write ou dual-read.
--
-- A política "Usuário cria XP events" (FOR INSERT WITH CHECK auth.uid() = user_id)
-- permite que qualquer usuário autenticado insira registros diretamente na tabela,
-- sem passar por nenhuma RPC DEFINER. Isso viabiliza dois vetores de ataque no
-- sistema legado:
--
--   1. DoS de idempotência: inserir registro falso de evento concluído para
--      bloquear conceder_xp_* de conceder XP legítimo no período.
--   2. DoS de limite diário: inflar SUM(xp) artificialmente para atingir o
--      teto de 200 XP/dia e impedir concessão legítima.
--
-- Embora o sistema legado não alimente o frontend atual (zero referências em
-- src/, app/, supabase/functions/), a política aberta representa padrão inseguro
-- que deve ser corrigido preventivamente.
--
-- POR QUE SECURITY DEFINER NÃO É AFETADO
-- ----------------------------------------
-- As 7 funções conceder_xp_* são SECURITY DEFINER com owner = postgres.
-- O role postgres tem atributo SUPERUSER, que bypassa RLS incondicionalmente
-- em PostgreSQL. Portanto, qualquer política WITH CHECK (false) aplicada à
-- tabela não afeta essas funções — elas continuam lendo e inserindo normalmente.
--
-- Funções afetadas (DEFINER, service_role only — NÃO ALTERADAS por esta migration):
--   - conceder_xp_modulo(p_user_id, p_modulo_id)            [dump ln 1389]
--   - conceder_xp_revisao_recomendada(p_user_id, p_revisao_id) [dump ln 1479]
--   - conceder_xp_revisao_voluntaria(p_user_id, p_revisao_id)  [dump ln 1567]
--   - conceder_xp_simulado(p_user_id, p_simulado_id, p_pct)    [dump ln 1655]
--   - conceder_xp_streak_5_dias(p_user_id)                  [dump ln 1755]
--   - conceder_xp_uso_diario(p_user_id)                     [dump ln 1848]
--   - conceder_xp_whatsapp(p_user_id)                       [dump ln 1926]
--
-- O QUE NÃO MUDA
-- ---------------
-- - Estrutura da tabela xp_events (DDL, colunas, tipos)
-- - FK xp_events.user_id → auth.users(id)
-- - GRANT para service_role
-- - As funções conceder_xp_*
-- - A tabela canônica xp_eventos e todas as suas policies
-- - Nenhum hook, tela ou serviço do app mobile é afetado
--
-- AUDITORIA DE REFERÊNCIA
-- ------------------------
-- Pesquisa realizada em 2026-05-16 (ver XP_EVENTS_LEGACY_AUDIT.md):
--   grep src/**          → 0 ocorrências de xp_events
--   grep app/**          → 0 ocorrências de xp_events
--   grep supabase/functions/** → 0 ocorrências de xp_events
--   grep supabase/migrations/** → 0 ocorrências de xp_events
--   Views que referenciam xp_events → NENHUMA
--   Materialized views  → NENHUMA
--   Triggers em xp_events → NENHUM
--   FK entrante em xp_events → NENHUMA
--   Cron jobs → NENHUM
--
-- PRÉ-CONDIÇÃO PENDENTE (NÃO VERIFICÁVEL VIA DUMP)
-- -------------------------------------------------
-- Confirmar manualmente que nenhum dashboard externo (Metabase, Retool,
-- Supabase Studio queries salvas) faz SELECT ou INSERT em xp_events em produção.
--
-- RISCO
-- -----
-- | Dimensão                      | Avaliação                                     |
-- |-------------------------------|-----------------------------------------------|
-- | Impacto no frontend           | ZERO — nenhuma referência em src/ ou app/     |
-- | Impacto nas funções DEFINER   | ZERO — SUPERUSER bypassa RLS                  |
-- | Impacto em Edge Functions     | ZERO — nenhuma referência confirmada           |
-- | Reversibilidade               | IMEDIATA — DROP POLICY + recriar a original   |
-- | Risco da migration em si      | BAIXO — apenas DDL de policy, sem dados       |
--
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Remover a política permissiva de INSERT
-- -----------------------------------------------------------------------------
-- Policy original (dump ln 17415):
--   CREATE POLICY "Usuário cria XP events" ON "public"."xp_events"
--       FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));
--
-- Esta é a única policy de INSERT existente na tabela. Removê-la elimina
-- o acesso direto de usuários authenticated.

DROP POLICY IF EXISTS "Usuário cria XP events" ON public.xp_events;

-- -----------------------------------------------------------------------------
-- STEP 2: Garantir idempotência — remover policies de bloqueio se já existirem
-- (caso a migration seja reexecutada ou aplicada em staging múltiplas vezes)
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "xp_events_insert_block"  ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_update"      ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_delete"      ON public.xp_events;

-- -----------------------------------------------------------------------------
-- STEP 3: Criar policy de bloqueio de INSERT para authenticated e anon
-- -----------------------------------------------------------------------------
-- WITH CHECK (false) = nenhuma linha satisfaz a condição → INSERT sempre rejeitado.
-- TO authenticated, anon = aplica apenas a esses roles.
-- service_role tem BYPASSRLS → não é afetado (e não está listado aqui).
-- owner postgres tem SUPERUSER → também não é afetado.

CREATE POLICY "xp_events_insert_block"
    ON public.xp_events
    FOR INSERT
    TO authenticated, anon
    WITH CHECK (false);

-- -----------------------------------------------------------------------------
-- STEP 4: Criar policy de bloqueio de UPDATE para authenticated e anon
-- -----------------------------------------------------------------------------
-- Previne atualização de registros existentes, caso algum usuário tenha
-- permissão de UPDATE via grant direto (improvável, mas blindagem preventiva).

CREATE POLICY "xp_events_no_update"
    ON public.xp_events
    FOR UPDATE
    TO authenticated, anon
    USING (false);

-- -----------------------------------------------------------------------------
-- STEP 5: Criar policy de bloqueio de DELETE para authenticated e anon
-- -----------------------------------------------------------------------------
-- Previne deleção de registros pelo usuário (e.g., apagar evidências de INSERT
-- indevido feito antes desta migration).

CREATE POLICY "xp_events_no_delete"
    ON public.xp_events
    FOR DELETE
    TO authenticated, anon
    USING (false);

-- -----------------------------------------------------------------------------
-- NOTA: SELECT não é alterado
-- -----------------------------------------------------------------------------
-- Não existe policy de SELECT em xp_events no dump (ln 17413–17416, apenas INSERT).
-- Com RLS habilitado e sem policy de SELECT, authenticated já vê zero linhas
-- por padrão (deny-by-default do PostgreSQL). Nenhuma policy de SELECT é criada
-- para não ampliar acesso inadvertidamente.

-- =============================================================================
-- TESTES SQL PÓS-APPLY (executar após migration — NÃO parte da migration)
-- =============================================================================
--
-- TESTE 1 — Policy permissiva foi removida?
--
--   SELECT polname
--   FROM pg_policies
--   WHERE schemaname = 'public'
--     AND tablename  = 'xp_events'
--     AND polname    = 'Usuário cria XP events';
--   -- Esperado: zero linhas
--
-- TESTE 2 — Policies de bloqueio foram criadas?
--
--   SELECT polname, polcmd, polroles::text
--   FROM pg_policies
--   WHERE schemaname = 'public'
--     AND tablename  = 'xp_events'
--   ORDER BY polname;
--   -- Esperado: 3 linhas:
--   --   xp_events_insert_block | i | {authenticated,anon}
--   --   xp_events_no_delete    | d | {authenticated,anon}
--   --   xp_events_no_update    | u | {authenticated,anon}
--
-- TESTE 3 — INSERT direto bloqueado para authenticated?
--   (executar como usuário authenticated com um user_id válido)
--
--   INSERT INTO public.xp_events (user_id, tipo, xp, periodo)
--   VALUES (auth.uid(), 'test_block', 1, '2026-05');
--   -- Esperado: ERROR: new row violates row-level security policy for table "xp_events"
--
-- TESTE 4 — service_role ainda consegue INSERT?
--   (executar como service_role — confirmar que funções DEFINER não quebram)
--
--   INSERT INTO public.xp_events (user_id, tipo, xp, periodo)
--   VALUES ('<uuid_valido>', 'test_service', 1, '2026-05');
--   -- Esperado: INSERT bem-sucedido (service_role bypassa RLS)
--   -- Limpar após teste:
--   DELETE FROM public.xp_events WHERE tipo = 'test_service';
--
-- TESTE 5 — Funções conceder_xp_* ainda funcionam?
--   (executar como service_role)
--
--   SELECT * FROM public.conceder_xp_uso_diario('<uuid_de_recruta_valido>');
--   -- Esperado: JSON com xp_concedido e motivo — sem erro de permissão
--   -- (pode retornar xp_concedido=0 se já concedido hoje — isso é normal)
--
-- TESTE 6 — RLS está habilitado na tabela?
--
--   SELECT relname, relrowsecurity
--   FROM pg_class
--   WHERE relname = 'xp_events'
--     AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
--   -- Esperado: relrowsecurity = true
--
-- TESTE 7 — Grants para service_role preservados?
--
--   SELECT grantee, privilege_type
--   FROM information_schema.role_table_grants
--   WHERE table_schema = 'public'
--     AND table_name   = 'xp_events'
--     AND grantee      = 'service_role';
--   -- Esperado: ALL (ou múltiplas linhas com SELECT, INSERT, UPDATE, DELETE, etc.)
--
-- =============================================================================
-- ROLLBACK (executar APENAS se a migration precisar ser revertida)
-- =============================================================================
--
-- Passo 1 — Remover as policies de bloqueio criadas por esta migration:
--
--   DROP POLICY IF EXISTS "xp_events_insert_block" ON public.xp_events;
--   DROP POLICY IF EXISTS "xp_events_no_update"    ON public.xp_events;
--   DROP POLICY IF EXISTS "xp_events_no_delete"    ON public.xp_events;
--
-- Passo 2 — Recriar a policy permissiva original:
--
--   CREATE POLICY "Usuário cria XP events"
--       ON public.xp_events
--       FOR INSERT
--       WITH CHECK (auth.uid() = user_id);
--
-- Verificação pós-rollback:
--
--   SELECT polname, polcmd
--   FROM pg_policies
--   WHERE schemaname = 'public' AND tablename = 'xp_events';
--   -- Esperado: apenas "Usuário cria XP events" com cmd = i
--
-- =============================================================================
-- REFERÊNCIAS
-- =============================================================================
-- Dump remoto (tabela):    supabase/remote/supabase_remote_schema.sql ln 14497–14508
-- Dump remoto (policy):    supabase/remote/supabase_remote_schema.sql ln 17413–17416
-- Dump remoto (grants):    supabase/remote/supabase_remote_schema.sql ln 19959–19961
-- Dump remoto (funções):   supabase/remote/supabase_remote_schema.sql ln 1389–2010
-- Auditoria completa:      supabase/baseline/XP_EVENTS_LEGACY_AUDIT.md
-- Risk matrix (P0-M4):     supabase_risk_matrix.md
-- Decision Packet (P0-M4): supabase/baseline/P0_DECISION_PACKET.md §2
-- =============================================================================
