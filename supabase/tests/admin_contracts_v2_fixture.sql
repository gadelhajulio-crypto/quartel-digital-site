BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
END
$$;

CREATE TABLE public.billing_pagamentos (
  id uuid PRIMARY KEY,
  status_pagamento text NOT NULL,
  valor_centavos bigint NOT NULL,
  moeda text NOT NULL,
  created_at timestamptz NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE public.billing_reconciliation_issues (
  id uuid PRIMARY KEY,
  status_execucao text NOT NULL,
  created_at timestamptz NOT NULL,
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE public.billing_reconciliacao (
  id uuid PRIMARY KEY,
  status_execucao text NOT NULL,
  executado_em timestamptz NOT NULL,
  observacao text
);

CREATE TABLE public.billing_notificacoes_log (
  id uuid PRIMARY KEY,
  status_envio text NOT NULL,
  created_at timestamptz NOT NULL,
  destinatario text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE public.eventos_institucionais (
  id uuid PRIMARY KEY,
  tipo text NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL,
  emitido_em timestamptz NOT NULL,
  titulo text NOT NULL,
  descricao text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  idempotency_key text,
  correlation_id text,
  error jsonb,
  referencia_id uuid
);

CREATE TABLE public.c5_taxonomia_eventos (
  tipo_evento text PRIMARY KEY,
  evento_analitico text NOT NULL,
  dominio_analitico text NOT NULL,
  ativo boolean NOT NULL DEFAULT true
);

CREATE VIEW public.v_c5_eventos_dominios_v3 AS
SELECT
  ei.id AS id_evento,
  coalesce(ct.dominio_analitico, 'outros'::text) AS dominio_analitico,
  ei.status,
  ei.emitido_em AS timestamp_evento,
  ei.payload AS metadata,
  ei.titulo,
  ei.descricao
FROM public.eventos_institucionais AS ei
LEFT JOIN public.c5_taxonomia_eventos AS ct
  ON ct.tipo_evento = ei.tipo
 AND ct.ativo;

ALTER TABLE public.billing_pagamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_reconciliation_issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_reconciliacao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_notificacoes_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos_institucionais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.c5_taxonomia_eventos ENABLE ROW LEVEL SECURITY;

CREATE POLICY billing_pagamentos_blocked_select
  ON public.billing_pagamentos FOR SELECT TO anon, authenticated
  USING (false);
CREATE POLICY billing_reconciliation_issues_blocked_select
  ON public.billing_reconciliation_issues FOR SELECT TO anon, authenticated
  USING (false);
CREATE POLICY billing_reconciliacao_blocked_select
  ON public.billing_reconciliacao FOR SELECT TO anon, authenticated
  USING (false);
CREATE POLICY billing_notificacoes_log_blocked_select
  ON public.billing_notificacoes_log FOR SELECT TO anon, authenticated
  USING (false);
CREATE POLICY eventos_institucionais_blocked_select
  ON public.eventos_institucionais FOR SELECT TO anon, authenticated
  USING (false);
CREATE POLICY c5_taxonomia_eventos_blocked_select
  ON public.c5_taxonomia_eventos FOR SELECT TO anon, authenticated
  USING (false);

GRANT SELECT ON TABLE
  public.billing_pagamentos,
  public.billing_reconciliation_issues,
  public.billing_reconciliacao,
  public.billing_notificacoes_log,
  public.eventos_institucionais,
  public.c5_taxonomia_eventos
TO anon, authenticated;

REVOKE ALL ON TABLE
  public.billing_pagamentos,
  public.billing_reconciliation_issues,
  public.billing_reconciliacao,
  public.billing_notificacoes_log,
  public.eventos_institucionais,
  public.c5_taxonomia_eventos
FROM service_role;

INSERT INTO public.c5_taxonomia_eventos (tipo_evento, evento_analitico, dominio_analitico)
VALUES ('login', 'login', 'auth');

INSERT INTO public.billing_pagamentos (id, status_pagamento, valor_centavos, moeda, created_at, payload)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'confirmado', 1250, 'BRL', '2026-09-16 10:00:00+00', '{"private":"payment"}'),
  ('00000000-0000-0000-0000-000000000002', 'confirmado', 0, 'USD', '2026-09-15 10:00:00+00', '{"private":"zero"}'),
  ('00000000-0000-0000-0000-000000000003', 'confirmado', 9000, 'BRL', '2020-01-01 10:00:00+00', '{"private":"old"}'),
  ('00000000-0000-0000-0000-000000000004', 'pendente', 500, 'BRL', '2026-09-16 11:00:00+00', '{"private":"pending"}'),
  ('00000000-0000-0000-0000-000000000005', 'falhou', 700, 'EUR', '2026-09-16 12:00:00+00', '{"private":"failed"}');

INSERT INTO public.billing_reconciliation_issues (id, status_execucao, created_at, detalhes)
VALUES
  ('00000000-0000-0000-0000-000000000011', 'erro', '2026-09-16 13:00:00+00', '{"private":"issue-error"}'),
  ('00000000-0000-0000-0000-000000000012', 'pendente', '2026-09-16 14:00:00+00', '{"private":"issue-pending"}'),
  ('00000000-0000-0000-0000-000000000013', 'sucesso', '2026-09-16 15:00:00+00', '{"private":"issue-success"}');

INSERT INTO public.billing_reconciliacao (id, status_execucao, executado_em, observacao)
VALUES
  ('00000000-0000-0000-0000-000000000021', 'erro', '2026-09-16 16:00:00+00', 'private reconciliation error'),
  ('00000000-0000-0000-0000-000000000022', 'sucesso', '2026-09-16 17:00:00+00', 'private reconciliation success');

INSERT INTO public.billing_notificacoes_log (id, status_envio, created_at, destinatario, payload)
VALUES
  ('00000000-0000-0000-0000-000000000031', 'falhou', '2026-09-16 18:00:00+00', 'synthetic-destination', '{"private":"notification"}'),
  ('00000000-0000-0000-0000-000000000032', 'enviado', '2026-09-16 19:00:00+00', 'synthetic-destination', '{"private":"sent"}');

INSERT INTO public.eventos_institucionais
  (id, tipo, status, created_at, emitido_em, titulo, descricao, payload, idempotency_key, correlation_id, error, referencia_id)
VALUES
  ('00000000-0000-0000-0000-000000000041', 'login', 'failed', '2026-09-16 20:00:00+00', '2026-09-16 20:01:00+00', 'Private title', 'Private description', '{"private":"event-failed"}', 'private-key-1', 'private-correlation-1', '{"private":"error"}', '00000000-0000-0000-0000-000000000099'),
  ('00000000-0000-0000-0000-000000000042', 'login', 'processed', '2026-09-16 21:00:00+00', '2026-09-16 21:01:00+00', 'Private title 2', 'Private description 2', '{"private":"event-processed"}', 'private-key-2', 'private-correlation-2', NULL, '00000000-0000-0000-0000-000000000098');

COMMIT;
