# Plano de Próximas Migrations — Quartel Digital
**Data:** 2026-05-16
**Sequência recomendada:** aplicar em ordem numérica

---

> **REGRA:** Nenhuma migration neste plano deve ser aplicada sem:
> 1. Leitura do DDL atual do remoto (pg_dump ou Supabase Studio)
> 2. Teste em branch/ambiente de staging
> 3. Aprovação institucional
>
> As migrations marcadas `[CAPTURE]` devem ser geradas via `pg_dump --schema-only` do banco remoto, não criadas manualmente.

---

## Migration 01 — Correção Crítica de Segurança: complete_lesson

**Arquivo:** `20260516001000_fix_complete_lesson_use_auth_uid.sql`
**Prioridade:** 🔴 CRÍTICO
**Risco:** ALTO — breaking change de assinatura da RPC

**Objetivo:** Eliminar o bypass de XP via `p_recruta_id` externo.

**Objetos afetados:**
- `complete_lesson` — reescrever para usar `auth.uid()` internamente
- `progressService.ts` — atualizar chamada para não passar `p_recruta_id`

**Lógica da migration:**
```sql
-- Dropar versão antiga (assinatura diferente para permitir CREATE OR REPLACE)
DROP FUNCTION IF EXISTS public.complete_lesson(uuid, uuid);

CREATE OR REPLACE FUNCTION public.complete_lesson(
  p_lesson_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_recruta_id uuid := auth.uid();
  v_xp integer;
BEGIN
  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT xp INTO v_xp FROM public.aulas WHERE id = p_lesson_id;

  INSERT INTO public.recruta_progresso (recruta_id, lesson_id, status, xp_granted)
  VALUES (v_recruta_id, p_lesson_id, 'completed', COALESCE(v_xp, 0))
  ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

  UPDATE public.recrutas
  SET xp = COALESCE(xp, 0) + COALESCE(v_xp, 0)
  WHERE id = v_recruta_id;
END;
$$;
```

**Mudança no frontend:**
```typescript
// progressService.ts — ANTES:
await supabase.rpc('complete_lesson', { p_recruta_id: userId, p_lesson_id: lessonId });

// DEPOIS:
await supabase.rpc('complete_lesson', { p_lesson_id: lessonId });
```

**Rollback:**
```sql
DROP FUNCTION IF EXISTS public.complete_lesson(uuid);
-- Recriar versão anterior com (p_recruta_id, p_lesson_id)
```

**Testes necessários:**
- Tentar completar aula de outro recruta (deve falhar com AUTH_REQUIRED ou apenas afetar o próprio usuário)
- Completar aula do próprio usuário (deve funcionar)
- Idempotência: completar mesma aula duas vezes (segunda deve ser no-op)

---

## Migration 02 — SET search_path em Funções SECURITY DEFINER

**Arquivo:** `20260516002000_fix_definer_functions_search_path.sql`
**Prioridade:** 🟠 ALTO
**Risco:** BAIXO — apenas ALTER, sem mudança de lógica

**Objetivo:** Blindar todas as funções SECURITY DEFINER contra schema injection.

**Objetos afetados:** ~18 funções DEFINER

```sql
-- Aplicar SET search_path a todas as funções SECURITY DEFINER
ALTER FUNCTION public.check_total_release() SET search_path = public, pg_catalog;
ALTER FUNCTION public.verificar_liberacao_total() SET search_path = public, pg_catalog;
ALTER FUNCTION public.registrar_xp(integer, text, text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.get_student_next_lesson(uuid) SET search_path = public, pg_catalog;
ALTER FUNCTION public.grant_medal(uuid, text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.promover_recruta(uuid, text, text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_auth_claim_active_client_session(text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_auth_resolve_session_state(text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_auth_revoke_client_session(uuid) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_complete_onboarding(text, text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_set_instructor_profile(text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_update_instructor_profile(text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_start_module(uuid) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_complete_module(uuid) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_mark_notice_read(uuid) SET search_path = public, pg_catalog;
ALTER FUNCTION public.rpc_mark_instructor_message_read(uuid) SET search_path = public, pg_catalog;
ALTER FUNCTION public.consumir_evento_c5(uuid) SET search_path = public, pg_catalog;
-- Adicionar complete_lesson após migration 01
```

**Rollback:** `ALTER FUNCTION nome RESET search_path;`

**Testes necessários:** Executar cada RPC e verificar funcionamento idêntico.

---

## Migration 03 — Corrigir Trigger de Auditoria: SECURITY DEFINER

**Arquivo:** `20260516003000_fix_audit_trigger_security_definer.sql`
**Prioridade:** 🟠 ALTO
**Risco:** BAIXO

**Objetivo:** Corrigir `fn_insert_audit_evento_smart` para executar com privilégios suficientes para inserir em `chat_audit_log`.

```sql
CREATE OR REPLACE FUNCTION public.fn_insert_audit_evento_smart()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_forca text;
    v_access text;
BEGIN
    SELECT forca, tipo_acesso INTO v_forca, v_access
    FROM public.profiles WHERE id = NEW.recruta_id;

    INSERT INTO public.chat_audit_log (
        session_id, timestamp_utc, user_id, recruta_id,
        source, response_category, force, access_mode
    ) VALUES (
        NEW.session_id, NEW.timestamp_utc, NEW.recruta_id, NEW.recruta_id,
        NEW.source, NEW.categoria,
        COALESCE(v_forca, 'unknown'),
        CASE WHEN v_access = 'completo' THEN 'full' ELSE 'free' END
    );
    RETURN NEW;
END;
$$;
```

**Rollback:** `CREATE OR REPLACE FUNCTION fn_insert_audit_evento_smart() ... (sem SECURITY DEFINER)`

---

## Migration 04 — Idempotência de registrar_xp

**Arquivo:** `20260516004000_make_registrar_xp_idempotent.sql`
**Prioridade:** 🟠 ALTO
**Risco:** MÉDIO — backfill de dados existentes necessário

**Objetivo:** Impedir duplicação de XP via retry/replay de bônus de módulo.

**Pré-requisito:** Auditar `xp_eventos` remoto para verificar se há source_id duplicados antes de adicionar o UNIQUE constraint.

```sql
-- 1. Verificar duplicatas (executar antes como leitura):
-- SELECT user_id, source_id, COUNT(*) FROM xp_eventos
-- WHERE source_id IS NOT NULL
-- GROUP BY user_id, source_id HAVING COUNT(*) > 1;

-- 2. Se não houver duplicatas:
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_xp_eventos_user_source
ON public.xp_eventos (user_id, source_id)
WHERE source_id IS NOT NULL;

-- 3. Atualizar registrar_xp para ON CONFLICT DO NOTHING
CREATE OR REPLACE FUNCTION public.registrar_xp(
    p_amount INTEGER,
    p_description TEXT,
    p_source_id TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_new_total INTEGER;
BEGIN
    -- Inserção idempotente: source_id duplicado é ignorado
    INSERT INTO public.xp_eventos (user_id, amount, description, source_id)
    VALUES (v_user_id, p_amount, p_description, p_source_id)
    ON CONFLICT (user_id, source_id) WHERE source_id IS NOT NULL DO NOTHING;

    -- Retorna total atualizado
    SELECT COALESCE(xp_total, 0) INTO v_new_total
    FROM public.recrutas WHERE id = v_user_id;

    -- Atualizar xp_total apenas se insert ocorreu
    IF FOUND THEN
        UPDATE public.recrutas
        SET xp_total = COALESCE(xp_total, 0) + p_amount
        WHERE id = v_user_id
        RETURNING xp_total INTO v_new_total;
    END IF;

    RETURN v_new_total;
END;
$$;
```

**Rollback:** `DROP INDEX idx_xp_eventos_user_source; (recriar função sem ON CONFLICT)`

---

## Migration 05 — Criar v_app_bootstrap_institucional_rcc

**Arquivo:** `20260516005000_create_v_app_bootstrap_institucional_rcc.sql`
**Prioridade:** 🔴 CRÍTICO (app falha no cold start)
**Risco:** BAIXO

**Objetivo:** Criar alias/view com nome que `bootstrapService.ts` espera.

```sql
-- Alias para a view existente com o nome que o bootstrapService espera
CREATE OR REPLACE VIEW public.v_app_bootstrap_institucional_rcc AS
SELECT * FROM public.v_app_bootstrap_institucional;

-- GRANT para authenticated
GRANT SELECT ON public.v_app_bootstrap_institucional_rcc TO authenticated;
```

**Rollback:** `DROP VIEW IF EXISTS public.v_app_bootstrap_institucional_rcc;`

---

## Migration 06 — Remover INSERT direto em xp_eventos

**Arquivo:** `20260516006000_fix_xp_eventos_rls_remove_direct_insert.sql`
**Prioridade:** 🟠 ALTO
**Risco:** BAIXO — apenas remove policy

**Objetivo:** Forçar todo INSERT em `xp_eventos` a passar por DEFINER RPCs.

```sql
DROP POLICY IF EXISTS "Recruta pode inserir eventos para si mesmo" ON public.xp_eventos;

-- Garantir que SELECT ainda funciona
-- (policy "Recruta vê apenas seus eventos" deve permanecer)
```

**Rollback:** `CREATE POLICY "Recruta pode inserir eventos para si mesmo" ON xp_eventos FOR INSERT WITH CHECK (auth.uid() = user_id);`

---

## Migration 07 — Agendar REFRESH das Materialized Views

**Arquivo:** `20260516007000_schedule_mv_refresh_pg_cron.sql`
**Prioridade:** 🟠 ALTO
**Risco:** MÉDIO — requer extensão `pg_cron` ativa no projeto Supabase

**Pré-requisito:** Verificar se `pg_cron` está disponível: `SELECT * FROM pg_extension WHERE extname = 'pg_cron';`

```sql
-- Habilitar pg_cron se não estiver
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Agendar REFRESH a cada hora (minuto 0 de cada hora)
SELECT cron.schedule(
    'refresh-mv-ranking-hourly',
    '0 * * * *',
    $$
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_xp_mensal_recruta;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_ranking_mensal;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_campeao_mensal;
    $$
);
```

**Rollback:** `SELECT cron.unschedule('refresh-mv-ranking-hourly');`

**Nota:** Se `pg_cron` não estiver disponível, implementar via Edge Function com trigger de cron no config.toml.

---

## Migration 08 [CAPTURE] — Baseline Schema de Tabelas Core

**Arquivo:** `20260516008000_capture_baseline_schema.sql`
**Prioridade:** 🔴 CRÍTICO
**Risco:** Somente leitura — migration de documentação

**Objetivo:** Capturar e versionar o DDL das tabelas que existem no remoto sem DDL local.

**Procedimento:**
```bash
# Executar no ambiente onde supabase CLI tem acesso ao remoto:
supabase db dump --schema public --table recrutas > /tmp/recrutas.sql
supabase db dump --schema public --table profiles > /tmp/profiles.sql
supabase db dump --schema public --table recruta_modulos > /tmp/recruta_modulos.sql
supabase db dump --schema public --table instrutores > /tmp/instrutores.sql
supabase db dump --schema public --table institutional_assets > /tmp/institutional_assets.sql
```

A migration deve ser criada com `CREATE TABLE IF NOT EXISTS` para ser idempotente.

---

## Migration 09 [CAPTURE] — Chat Objects DDL

**Arquivo:** `20260516009000_capture_chat_objects.sql`
**Prioridade:** 🔴 CRÍTICO
**Risco:** Somente documentação

**Objetivo:** Capturar DDL de todas as tabelas, views e RPCs do sistema de chat.

**Objetos a capturar:**
- Tabelas base: `chat_conversas` (ou equivalente), `chat_mensagens`, tabela de unread
- Views: `v_chat_conversas_recruta`, `v_chat_mensagens_recruta`, `v_chat_unread_status`
- RPCs: `rpc_chat_open_conversation`, `rpc_chat_send_message`, `rpc_chat_mark_read`
- View: `v_instrutores_app`

---

## Migration 10 [CAPTURE] — Views _v2

**Arquivo:** `20260516010000_capture_v2_views.sql`
**Prioridade:** 🟠 ALTO
**Risco:** Somente documentação

**Objetivo:** Capturar DDL das views com sufixo `_v2` que o app consome.

**Objetos:**
- `vw_rdm_lessons_v2`
- `vw_recruta_module_progress_v2`
- `v_billing_status_recruta_v2`
- `v_iea_atual_v2`
- `v_elegibilidade_elite_v2`
- `v_classificacao_final_ciclo_v2`
- `v_app_bootstrap_institucional_rcc`

---

## Migration 11 — Mover Bônus de Módulo para rpc_complete_module

**Arquivo:** `20260516011000_move_module_xp_bonus_to_rpc.sql`
**Prioridade:** 🟠 ALTO
**Risco:** MÉDIO — requer atualização do frontend

**Objetivo:** Eliminar chamada a `registrar_xp` pelo cliente após completar módulo.

```sql
CREATE OR REPLACE FUNCTION public.rpc_complete_module(
    p_modulo_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_recruta_id uuid := auth.uid();
    v_already_completed boolean;
BEGIN
    IF p_modulo_id IS NULL THEN RETURN; END IF;

    -- Verificar se já foi completado (para idempotência do bônus de XP)
    SELECT (status = 'completed') INTO v_already_completed
    FROM public.recruta_modulos
    WHERE recruta_id = v_recruta_id AND modulo_id = p_modulo_id;

    UPDATE public.recruta_modulos
    SET completed_at = now(), status = 'completed'
    WHERE recruta_id = v_recruta_id
      AND modulo_id  = p_modulo_id
      AND status    != 'completed';

    -- Conceder bônus XP apenas se não estava completado antes
    IF NOT COALESCE(v_already_completed, false) AND FOUND THEN
        INSERT INTO public.xp_eventos (user_id, amount, description, source_id)
        VALUES (v_recruta_id, 500, 'Módulo Concluído', p_modulo_id::text)
        ON CONFLICT (user_id, source_id) WHERE source_id IS NOT NULL DO NOTHING;

        UPDATE public.recrutas
        SET xp_total = COALESCE(xp_total, 0) + 500
        WHERE id = v_recruta_id;
    END IF;
END;
$$;
```

**Mudança no frontend:**
```typescript
// progressService.ts — remover chamada a registerXp após rpc_complete_module
// O bônus agora é responsabilidade da RPC
```

**Dependência:** Migration 04 (idempotência de xp_eventos) deve ser aplicada antes.

---

## Migration 12 — Corrigir FK de c9_aula_quiz_tentativas

**Arquivo:** `20260516012000_fix_c9_tentativas_fk_recrutas.sql`
**Prioridade:** 🟡 MÉDIO
**Risco:** MÉDIO — requer verificação de dados existentes

```sql
-- Verificar se todos os recruta_id em tentativas existem em recrutas:
-- SELECT COUNT(*) FROM c9_aula_quiz_tentativas t
-- WHERE NOT EXISTS (SELECT 1 FROM recrutas r WHERE r.id = t.recruta_id);

-- Se zerado, prosseguir:
ALTER TABLE public.c9_aula_quiz_tentativas
    DROP CONSTRAINT IF EXISTS c9_aula_quiz_tentativas_recruta_id_fkey;

ALTER TABLE public.c9_aula_quiz_tentativas
    ADD CONSTRAINT c9_aula_quiz_tentativas_recruta_id_fkey
    FOREIGN KEY (recruta_id) REFERENCES public.recrutas(id) ON DELETE CASCADE;
```

---

## Migration 13 — Remover arquivo inválido RP Page

**Arquivo:** Não é uma migration SQL — é uma limpeza de repositório.

```bash
# Remover da pasta de migrations (não é arquivo SQL)
git rm "supabase/migrations/RP Page"
git commit -m "chore(migrations): remove invalid non-SQL file from migrations folder"
```

---

## Checklist de Aplicação

Para cada migration acima, executar na ordem:

```
[ ] 1. Ler DDL atual do remoto (Supabase Studio ou pg_dump)
[ ] 2. Verificar dependências (tabelas/views existem no remoto)
[ ] 3. Aplicar em staging/branch
[ ] 4. Executar testes listados na migration
[ ] 5. Verificar logs de edge functions relacionadas
[ ] 6. Aplicar em produção em janela de manutenção
[ ] 7. Monitorar logs por 24h após aplicação
[ ] 8. Atualizar MEMORY.md com novo estado das migrations
```
