-- Wave 5g-1 — Hardening do cache institucional
-- Adiciona material_scope_version como chave de invalidação explícita.
-- Invalida entradas do formato legado (7 segmentos → 8 segmentos na cache_key).
--
-- Nova cache_key: slug:forca:access_mode:scope_type:model:prompt_version:material_scope_version:question_hash
-- Legado:         slug:forca:access_mode:scope_type:model:v1:question_hash
--
-- IDEMPOTÊNCIA: ADD COLUMN IF NOT EXISTS + DELETE idempotente por contagem de segmentos.

-- ── Nova coluna: material_scope_version ───────────────────────────────────────

ALTER TABLE public.chat_response_cache
  ADD COLUMN IF NOT EXISTS material_scope_version TEXT NOT NULL DEFAULT 'v1';

COMMENT ON COLUMN public.chat_response_cache.material_scope_version IS
  'Versão do escopo de material (MATERIAL_SCOPE em chat-central). '
  'Bump ao alterar currículos disponíveis por força para invalidar o cache existente.';

-- ── Invalidar entradas com formato de chave legado ────────────────────────────
-- Entradas Wave 5g têm 7 segmentos separados por ":" (sem material_scope_version).
-- Novas entradas terão 8 segmentos. Remover as antigas para evitar nunca serem atingidas.

DELETE FROM public.chat_response_cache
WHERE array_length(string_to_array(cache_key, ':'), 1) < 8;

-- ── Índice de auditoria por versão de escopo ──────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_chat_response_cache_scope_version
  ON public.chat_response_cache (material_scope_version, instrutor_slug);
