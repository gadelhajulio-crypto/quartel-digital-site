BEGIN;

SELECT plan(29);

SELECT ok(to_regclass('public.v_admin_pagamentos_confirmados') IS NOT NULL, 'payments view exists');
SELECT ok(to_regclass('public.v_admin_alertas') IS NOT NULL, 'alerts view exists');
SELECT ok(to_regclass('public.v_admin_atividade_recente') IS NOT NULL, 'activity view exists');

SELECT ok((SELECT count(*) = 3 AND bool_and(
  (attnum = 1 AND attname = 'amount_cents' AND atttypid = 'bigint'::regtype) OR
  (attnum = 2 AND attname = 'currency' AND atttypid = 'text'::regtype) OR
  (attnum = 3 AND attname = 'occurred_at' AND atttypid = 'timestamptz'::regtype)
) FROM pg_attribute WHERE attrelid = 'public.v_admin_pagamentos_confirmados'::regclass AND attnum > 0 AND NOT attisdropped), 'payments columns are exact');
SELECT ok((SELECT count(*) = 4 AND bool_and(
  (attnum = 1 AND attname = 'source' AND atttypid = 'text'::regtype) OR
  (attnum = 2 AND attname = 'status' AND atttypid = 'text'::regtype) OR
  (attnum = 3 AND attname = 'occurred_at' AND atttypid = 'timestamptz'::regtype) OR
  (attnum = 4 AND attname = 'description' AND atttypid = 'text'::regtype)
) FROM pg_attribute WHERE attrelid = 'public.v_admin_alertas'::regclass AND attnum > 0 AND NOT attisdropped), 'alerts columns are exact');
SELECT ok((SELECT count(*) = 3 AND bool_and(
  (attnum = 1 AND attname = 'domain' AND atttypid = 'text'::regtype) OR
  (attnum = 2 AND attname = 'status' AND atttypid = 'text'::regtype) OR
  (attnum = 3 AND attname = 'occurred_at' AND atttypid = 'timestamptz'::regtype)
) FROM pg_attribute WHERE attrelid = 'public.v_admin_atividade_recente'::regclass AND attnum > 0 AND NOT attisdropped), 'activity columns are exact');

SELECT ok((SELECT reloptions @> ARRAY['security_barrier=true']::text[] FROM pg_class WHERE oid = 'public.v_admin_pagamentos_confirmados'::regclass), 'payments view is security barrier');
SELECT ok((SELECT reloptions @> ARRAY['security_barrier=true']::text[] FROM pg_class WHERE oid = 'public.v_admin_alertas'::regclass), 'alerts view is security barrier');
SELECT ok((SELECT reloptions @> ARRAY['security_barrier=true']::text[] FROM pg_class WHERE oid = 'public.v_admin_atividade_recente'::regclass), 'activity view is security barrier');

SELECT ok(not has_table_privilege('anon', 'public.v_admin_pagamentos_confirmados', 'SELECT'), 'anon has no payments SELECT');
SELECT ok(not has_table_privilege('authenticated', 'public.v_admin_alertas', 'SELECT'), 'authenticated has no alerts SELECT');
SELECT ok(not has_table_privilege('anon', 'public.v_admin_atividade_recente', 'SELECT'), 'anon has no activity SELECT');
SELECT ok(not has_table_privilege('authenticated', 'public.v_admin_pagamentos_confirmados', 'SELECT'), 'authenticated has no payments SELECT');
SELECT ok(not has_table_privilege('anon', 'public.v_admin_alertas', 'SELECT'), 'anon has no alerts SELECT');
SELECT ok(not has_table_privilege('authenticated', 'public.v_admin_atividade_recente', 'SELECT'), 'authenticated has no activity SELECT');
SELECT ok(not exists (SELECT 1 FROM pg_class AS c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS acl WHERE acl.grantee = 0 AND acl.privilege_type = 'SELECT' AND c.oid = 'public.v_admin_pagamentos_confirmados'::regclass), 'PUBLIC has no payments SELECT');
SELECT ok(not exists (SELECT 1 FROM pg_class AS c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS acl WHERE acl.grantee = 0 AND acl.privilege_type = 'SELECT' AND c.oid = 'public.v_admin_alertas'::regclass), 'PUBLIC has no alerts SELECT');
SELECT ok(not exists (SELECT 1 FROM pg_class AS c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) AS acl WHERE acl.grantee = 0 AND acl.privilege_type = 'SELECT' AND c.oid = 'public.v_admin_atividade_recente'::regclass), 'PUBLIC has no activity SELECT');
SELECT ok(has_table_privilege('service_role', 'public.v_admin_pagamentos_confirmados', 'SELECT'), 'service_role has payments SELECT');
SELECT ok(has_table_privilege('service_role', 'public.v_admin_alertas', 'SELECT'), 'service_role has alerts SELECT');
SELECT ok(has_table_privilege('service_role', 'public.v_admin_atividade_recente', 'SELECT'), 'service_role has activity SELECT');

SELECT ok((SELECT array_agg(format('%s|%s|%s', amount_cents, currency, occurred_at) ORDER BY occurred_at DESC) FROM public.v_admin_pagamentos_confirmados) = ARRAY[
  '1250|BRL|2026-09-16 10:00:00+00',
  '0|USD|2026-09-15 10:00:00+00',
  '9000|BRL|2020-01-01 10:00:00+00'
]::text[], 'payments map amount, currency, and created_at exactly');
SELECT is((SELECT count(*) FROM public.v_admin_pagamentos_confirmados WHERE amount_cents = 500 OR amount_cents = 700), 0::bigint, 'pending and failed payments are excluded');
SELECT ok(not exists (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'v_admin_pagamentos_confirmados' AND column_name IN ('id', 'recruta_id', 'assinatura_id', 'payload', 'status_pagamento')), 'payments expose no identifiers, status, or payload');

SELECT ok((SELECT array_agg(format('%s|%s|%s|%s', source, status, occurred_at, description) ORDER BY occurred_at) FROM public.v_admin_alertas) = ARRAY[
  'billing_reconciliation_issues|erro|2026-09-16 13:00:00+00|Divergência de reconciliação',
  'billing_reconciliation_issues|pendente|2026-09-16 14:00:00+00|Divergência de reconciliação',
  'billing_reconciliacao|erro|2026-09-16 16:00:00+00|Execução de reconciliação',
  'billing_notificacoes_log|falhou|2026-09-16 18:00:00+00|Notificação de cobrança',
  'eventos_institucionais|failed|2026-09-16 20:00:00+00|Evento institucional'
]::text[], 'alerts preserve source filters, timestamps, and fixed descriptions');
SELECT ok(not exists (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'v_admin_alertas' AND column_name IN ('id', 'recruta_id', 'assinatura_id', 'pagamento_id', 'gateway_event_id', 'destinatario', 'detalhes', 'observacao', 'erro', 'titulo', 'descricao', 'payload', 'error', 'correlation_id', 'idempotency_key')), 'alerts expose no identifiers or free text');
SELECT ok(not exists (SELECT 1 FROM public.v_admin_alertas WHERE description NOT IN ('Divergência de reconciliação', 'Execução de reconciliação', 'Notificação de cobrança', 'Evento institucional')), 'alerts descriptions are fixed');

SELECT ok((SELECT array_agg(format('%s|%s|%s', domain, status, occurred_at) ORDER BY occurred_at) FROM public.v_admin_atividade_recente) = ARRAY[
  'auth|failed|2026-09-16 20:01:00+00',
  'auth|processed|2026-09-16 21:01:00+00'
]::text[], 'activity maps domain, status, and timestamp_evento');
SELECT ok(not exists (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'v_admin_atividade_recente' AND column_name IN ('id_evento', 'description', 'metadata', 'titulo', 'descricao', 'payload')), 'activity exposes no event id or free text');

SELECT * FROM finish();
ROLLBACK;
