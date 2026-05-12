-- =============================================================
-- RCC-0.5 / Wave 1 — Registro de Assets Institucionais
-- Bucket: institutional-assets (público)
-- Tabelas: institutional_assets, instrutores
-- =============================================================

-- ── 1. institutional_assets ───────────────────────────────────
-- DELETE + INSERT idempotente (evita ON CONFLICT sem constraint UNIQUE)

DELETE FROM public.institutional_assets
WHERE tipo IN (
  'ramos-avatar-circle','rocha-avatar-circle','sara-avatar-circle',
  'ramos-card-idle','rocha-card-idle','sara-card-idle',
  'ramos-card-selected','rocha-card-selected','sara-card-selected',
  'ramos-chat-icon','rocha-chat-icon','sara-chat-icon',
  'ramos-whatsapp','rocha-whatsapp','sara-whatsapp'
);

INSERT INTO public.institutional_assets
  (tipo, url, forca, versao, ativo, checksum, cache_policy)
VALUES
  -- avatars
  ('ramos-avatar-circle',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/avatars/ramos-avatar-circle.png',
   NULL, 1, true,
   'bd9e847bf3248c9feb4de24be7535022979caa72505ea069e270a47daab3d631',
   'public,max-age=31536000,immutable'),

  ('rocha-avatar-circle',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/avatars/rocha-avatar-circle.png',
   NULL, 1, true,
   '65b604b0617f236e631275c8a679f3a24964af3dfd69b85889cd1ea0d1f75699',
   'public,max-age=31536000,immutable'),

  ('sara-avatar-circle',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/avatars/sara-avatar-circle.png',
   NULL, 1, true,
   '7be02017dd2639d0e77ed04e4f52ba240daea0d04eddd31b9e3d98b1ae2cfe75',
   'public,max-age=31536000,immutable'),

  -- cards idle
  ('ramos-card-idle',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/cards/ramos-card-idle.png',
   NULL, 1, true,
   '1a5e34555501311b4ba5ad70a6cbf758d418f55ca0fe9435c270d561bf49fd20',
   'public,max-age=31536000,immutable'),

  ('rocha-card-idle',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/cards/rocha-card-idle.png',
   NULL, 1, true,
   '2aecb814c53b29a4e2bfab06b7d29ef10637bfd10ee6285b91895f0e21a08f81',
   'public,max-age=31536000,immutable'),

  ('sara-card-idle',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/cards/sara-card-idle.png',
   NULL, 1, true,
   '0bb56e55823bff034a9844e0f64bd054f3e5c9c87c9756baf05c20966357ffc3',
   'public,max-age=31536000,immutable'),

  -- cards selected
  ('ramos-card-selected',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/cards/ramos-card-selected.png',
   NULL, 1, true,
   '2a4deed20126b94de0cc3a3b5420474200e41ef9fb6830cd147ba428d563670d',
   'public,max-age=31536000,immutable'),

  ('rocha-card-selected',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/cards/rocha-card-selected.png',
   NULL, 1, true,
   '165d79b417dc2b1506c9e0db9bba9873ec54bff11f44923711faaac6e8d39c16',
   'public,max-age=31536000,immutable'),

  ('sara-card-selected',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/cards/sara-card-selected.png',
   NULL, 1, true,
   '42e863e4868c6765d48e6aa9d71c26f13b2a8ab16e0125b428f5c71e68a597bc',
   'public,max-age=31536000,immutable'),

  -- chat icons
  ('ramos-chat-icon',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/chat/ramos-chat-icon.png',
   NULL, 1, true,
   '914f0488b58a946a5fec9337a73051a41ed16de18c0dca0a2c6b7979fb5b7613',
   'public,max-age=31536000,immutable'),

  ('rocha-chat-icon',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/chat/rocha-chat-icon.png',
   NULL, 1, true,
   '69de345be1e87292d5828c710df8493782a3c1f8ea462525961a3d93d14019b8',
   'public,max-age=31536000,immutable'),

  ('sara-chat-icon',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/chat/sara-chat-icon.png',
   NULL, 1, true,
   '64c39693bc0a317992b21cb23aa339056c7b6c1911b654b2ee3bf2ab85b6dd26',
   'public,max-age=31536000,immutable'),

  -- whatsapp
  ('ramos-whatsapp',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/whatsapp/ramos-whatsapp.png',
   NULL, 1, true,
   '602c2157f9810581d5d53def17a26a68b8b468d27345cadf219209b468d57719',
   'public,max-age=31536000,immutable'),

  ('rocha-whatsapp',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/whatsapp/rocha-whatsapp.png',
   NULL, 1, true,
   '3cd4b18acc3b546ead69b9f41208f29cb53d201b8bcb6a807b2dfd5327c274ed',
   'public,max-age=31536000,immutable'),

  ('sara-whatsapp',
   'https://fjwvtzvfbhubxicsmbdz.supabase.co/storage/v1/object/public/institutional-assets/instructors/whatsapp/sara-whatsapp.png',
   NULL, 1, true,
   'd8957a83b40e5fca165f64ffb5b12ba0443bab2d2869b5f250caeb7b48e8ffd7',
   'public,max-age=31536000,immutable');


-- ── 2. instrutores ────────────────────────────────────────────
-- DELETE + INSERT idempotente

DELETE FROM public.instrutores
WHERE slug IN ('ramos', 'rocha', 'sara');

INSERT INTO public.instrutores
  (slug, codigo, nome, titulo, descricao, ativo, ordem_exibicao,
   avatar_asset_tipo, chat_icon_asset_tipo, whatsapp_asset_tipo,
   card_selected_asset_tipo, card_idle_asset_tipo)
VALUES
  ('ramos', 'objetivo',
   'Sargento Ramos', 'Sargento',
   'Direto ao ponto. Missão cumprida. Focado em resultados e eficiência operacional.',
   true, 1,
   'ramos-avatar-circle', 'ramos-chat-icon', 'ramos-whatsapp',
   'ramos-card-selected',  'ramos-card-idle'),

  ('rocha', 'estrategico',
   'Sargento Rocha', 'Sargento',
   'Cada decisão tem um plano. Visão analítica e planejamento de longo prazo.',
   true, 2,
   'rocha-avatar-circle', 'rocha-chat-icon', 'rocha-whatsapp',
   'rocha-card-selected',  'rocha-card-idle'),

  ('sara', 'didatico',
   'Sargento Sara', 'Sargento',
   'Aprende quem treina com método. Ensino progressivo e suporte contínuo.',
   true, 3,
   'sara-avatar-circle', 'sara-chat-icon', 'sara-whatsapp',
   'sara-card-selected',  'sara-card-idle');


-- ── 3. Validação ──────────────────────────────────────────────
-- Executar após o INSERT para confirmar registro:
--
-- SELECT tipo, url, ativo, versao, cache_policy
-- FROM public.v_institutional_assets
-- WHERE tipo IN (
--   'ramos-avatar-circle','rocha-avatar-circle','sara-avatar-circle',
--   'ramos-card-selected','ramos-card-idle',
--   'rocha-card-selected','rocha-card-idle',
--   'sara-card-selected','sara-card-idle',
--   'ramos-chat-icon','rocha-chat-icon','sara-chat-icon',
--   'ramos-whatsapp','rocha-whatsapp','sara-whatsapp'
-- )
-- ORDER BY tipo;
--
-- SELECT slug, nome, avatar_url, chat_icon_url, whatsapp_avatar_url,
--        card_selected_url, card_idle_url
-- FROM public.v_instrutores_app
-- ORDER BY ordem_exibicao;
