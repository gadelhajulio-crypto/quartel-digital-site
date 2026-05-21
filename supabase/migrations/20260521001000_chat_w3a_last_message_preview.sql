-- Wave 3a: Adicionar last_message_preview e last_message_role à v_chat_conversas_recruta
--
-- Estratégia: LATERAL subquery em chat_mensagens usando índice já existente
-- idx_chat_mensagens_conversa_created (conversa_id, created_at)
-- Index scan + LIMIT 1 → custo O(1) por conversa, sem full scan.
--
-- Sem novos índices — idx_chat_mensagens_conversa_created já cobre o acesso.
-- Sem DROP da view — CREATE OR REPLACE preserva dependências e grants.
--
-- Campos adicionados:
--   last_message_preview TEXT|NULL — LEFT(conteudo, 120), null quando sem mensagens
--   last_message_role    TEXT|NULL — 'user' | 'assistant', null quando sem mensagens

CREATE OR REPLACE VIEW public.v_chat_conversas_recruta AS
SELECT
  cc.conversa_id,
  cc.recruta_id,
  cc.instrutor_slug,
  COALESCE(i.nome,   cc.instrutor_slug) AS instrutor_nome,
  COALESCE(i.titulo, '')               AS instrutor_titulo,
  NULL::TEXT                           AS avatar_asset_tipo,
  NULL::TEXT                           AS chat_icon_asset_tipo,
  cc.status,
  COALESCE(us.unread_count, 0)         AS unread_count,
  COALESCE(us.unread_count, 0) > 0     AS has_unread,
  cc.opened_at,
  cc.last_message_at,
  cc.updated_at,
  -- Wave 3a: preview da última mensagem (banco trunca, frontend apenas renderiza)
  lm.preview                           AS last_message_preview,
  lm.role                              AS last_message_role
FROM public.chat_conversas cc
LEFT JOIN public.instrutores i
  ON i.codigo = cc.instrutor_slug
LEFT JOIN public.chat_unread_status us
  ON us.conversa_id = cc.conversa_id
-- LATERAL: une a mensagem mais recente por conversa usando idx_chat_mensagens_conversa_created
LEFT JOIN LATERAL (
  SELECT
    LEFT(m.conteudo, 120) AS preview,
    m.role
  FROM public.chat_mensagens m
  WHERE m.conversa_id = cc.conversa_id
  ORDER BY m.created_at DESC
  LIMIT 1
) lm ON TRUE
WHERE cc.recruta_id = (
  SELECT id FROM public.recrutas WHERE auth_id = auth.uid()
);

-- Grants preservados (view substituída in-place)
GRANT SELECT ON public.v_chat_conversas_recruta TO authenticated;
