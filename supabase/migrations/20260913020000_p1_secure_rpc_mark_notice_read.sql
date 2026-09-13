-- ==============================================================================
-- P1 — Fechamento de rpc_mark_notice_read (identidade confiada do cliente)
-- ==============================================================================
-- Achado: rpc_mark_notice_read(p_notice_id uuid, p_recruta_id uuid) nunca
-- validava p_recruta_id contra o chamador. Além disso, a função nunca teve
-- nenhum GRANT/REVOKE explícito no schema — EXECUTE permanecia no default do
-- Postgres, concedido a PUBLIC (alcançável até por anon, não só authenticated).
-- Confirmado por leitura de schema (dump 2026-09-12, SHA-256
-- 2a471d0e41e1c73bc967a80e873b87638c0e6c7258487c93f3a31b8fe88b1701), sem
-- consulta a dados reais nem invocação da função.
--
-- Consumidor real confirmado no repositório: src/hooks/useInstitutionalNotices.ts
-- chama supabase.rpc('rpc_mark_notice_read', { p_notice_id: noticeId }) — só
-- com 1 parâmetro. A assinatura de 2 parâmetros não tem default, então essa
-- chamada já falha hoje contra a assinatura antiga. A assinatura canônica de
-- 1 parâmetro criada aqui corrige esse bug funcional e fecha o IDOR ao mesmo
-- tempo, resolvendo recruta_id exclusivamente a partir de auth.uid().
--
-- A assinatura antiga de 2 parâmetros NÃO é removida nesta rodada (mapeamento
-- de consumidores em VPS/n8n é inconclusivo — fora do escopo desta sessão).
-- Em vez de remover, ela passa a validar p_recruta_id contra auth.uid() e
-- lança exceção em caso de divergência — deixa de confiar cegamente no
-- parâmetro, mas continua chamável por quem hoje a chama corretamente.
-- ==============================================================================

-- ── 1. Assinatura antiga (2 parâmetros) — protegida, não removida ────────────

CREATE OR REPLACE FUNCTION public.rpc_mark_notice_read(p_notice_id uuid, p_recruta_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_recruta_id uuid;
BEGIN
  SELECT id INTO v_caller_recruta_id
  FROM public.recrutas
  WHERE auth_id = auth.uid();

  IF v_caller_recruta_id IS NULL OR v_caller_recruta_id <> p_recruta_id THEN
    RAISE EXCEPTION 'RECRUTA_ID_MISMATCH' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.institutional_notice_reads (notice_id, recruta_id)
  VALUES (p_notice_id, p_recruta_id)
  ON CONFLICT (notice_id, recruta_id) DO NOTHING;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_mark_notice_read(uuid, uuid) FROM PUBLIC;
-- Nenhum GRANT direto a anon foi encontrado no schema para esta assinatura
-- (o acesso vinha só do default de PUBLIC, já revogado acima); o REVOKE
-- abaixo é incluído mesmo assim, de forma explícita e sem efeito colateral,
-- para não depender de inferência sobre o estado herdado de PUBLIC.
REVOKE EXECUTE ON FUNCTION public.rpc_mark_notice_read(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_mark_notice_read(uuid, uuid) TO authenticated;

-- ── 2. Assinatura canônica (1 parâmetro) — a que o cliente já chama ──────────

CREATE OR REPLACE FUNCTION public.rpc_mark_notice_read(p_notice_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_recruta_id uuid;
BEGIN
  SELECT id INTO v_recruta_id
  FROM public.recrutas
  WHERE auth_id = auth.uid();

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'RECRUTA_NOT_FOUND' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.institutional_notice_reads (notice_id, recruta_id)
  VALUES (p_notice_id, v_recruta_id)
  ON CONFLICT (notice_id, recruta_id) DO NOTHING;

  RETURN true;
END;
$$;

-- Obrigatório: CREATE/CREATE OR REPLACE FUNCTION concede EXECUTE a PUBLIC por
-- padrão. Revogar e conceder explicitamente só a authenticated.
REVOKE EXECUTE ON FUNCTION public.rpc_mark_notice_read(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_mark_notice_read(uuid) TO authenticated;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- CREATE OR REPLACE FUNCTION public.rpc_mark_notice_read(p_notice_id uuid, p_recruta_id uuid)
-- RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
-- BEGIN
--   INSERT INTO public.institutional_notice_reads (notice_id, recruta_id)
--   VALUES (p_notice_id, p_recruta_id)
--   ON CONFLICT (notice_id, recruta_id) DO NOTHING;
--   RETURN true;
-- END;
-- $$;
-- GRANT EXECUTE ON FUNCTION public.rpc_mark_notice_read(uuid, uuid) TO PUBLIC;
-- DROP FUNCTION IF EXISTS public.rpc_mark_notice_read(uuid);

-- ==============================================================================
-- TESTES (não executados nesta migration; ver plano de teste em anexo à PR)
-- ==============================================================================
-- Como recruta A: rpc_mark_notice_read(p_notice_id) -> true
-- Como recruta A: rpc_mark_notice_read(p_notice_id, <recruta_id de B>) -> erro 42501
-- Como anon (sem sessão): rpc_mark_notice_read(p_notice_id) -> erro de permissão (EXECUTE negado)
