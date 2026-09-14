begin;

select plan(16);

select ok(
  (
    select count(*) = 2
       and bool_and(
         (attnum = 1
           and attname::text collate "C" = 'recrutas_total'::text collate "C"
           and atttypid = 'bigint'::regtype)
         or
         (attnum = 2
           and attname::text collate "C" = 'recrutas_ativos'::text collate "C"
           and atttypid = 'bigint'::regtype)
       )
    from pg_attribute
    where attrelid = 'public.v_admin_recruta_metricas'::regclass
      and attnum > 0
      and not attisdropped
  ),
  'view exposes exactly the two aggregate bigint columns'
);

select is(
  (select count(*) from public.v_admin_recruta_metricas),
  1::bigint,
  'view always returns exactly one row'
);

select results_eq(
  $$
    select recrutas_total, recrutas_ativos
    from public.v_admin_recruta_metricas
  $$,
  $$
    select count(*)::bigint,
           count(*) filter (where lower(coalesce(status, '')) = 'ativo')::bigint
    from public.recrutas
  $$,
  'view aggregates the base table with the approved active rule'
);

select ok(
  has_table_privilege('service_role', 'public.v_admin_recruta_metricas', 'SELECT'),
  'service_role has SELECT on the view'
);

select ok(
  not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    where c.oid = 'public.v_admin_recruta_metricas'::regclass
      and acl.grantee <> c.relowner
      and (
        acl.grantee <> 'service_role'::regrole
        or acl.privilege_type <> 'SELECT'
      )
  ),
  'service_role is the only non-owner grantee and has only SELECT'
);

set local role service_role;
select is(
  (select count(*) from public.v_admin_recruta_metricas),
  1::bigint,
  'service_role can execute SELECT on the view'
);
reset role;

select ok(
  not has_table_privilege('anon', 'public.v_admin_recruta_metricas', 'SELECT'),
  'anon has no SELECT on the view'
);

set local role anon;
select throws_ok(
  $$select * from public.v_admin_recruta_metricas$$,
  '42501',
  null,
  'anon cannot execute SELECT on the view'
);
reset role;

select ok(
  not has_table_privilege('authenticated', 'public.v_admin_recruta_metricas', 'SELECT'),
  'authenticated has no SELECT on the view'
);

set local role authenticated;
select throws_ok(
  $$select * from public.v_admin_recruta_metricas$$,
  '42501',
  null,
  'authenticated cannot execute SELECT on the view'
);
reset role;

select ok(
  not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    where c.oid = 'public.v_admin_recruta_metricas'::regclass
      and acl.grantee = 0
  ),
  'PUBLIC has no privilege grant on the view'
);

select ok(
  (select reloptions @> array['security_invoker=true']::text[]
   from pg_class where oid = 'public.v_admin_recruta_metricas'::regclass),
  'view has security_invoker=true'
);

select ok(
  (select reloptions @> array['security_barrier=true']::text[]
   from pg_class where oid = 'public.v_admin_recruta_metricas'::regclass),
  'view has security_barrier=true'
);

select results_eq(
  $$
    select count(*)::bigint,
           count(*) filter (where lower(coalesce(status, '')) = 'ativo')::bigint
    from (select null::text as status where false) empty_recrutas
  $$,
  $$
    values (0::bigint, 0::bigint)
  $$,
  'zero-recruta input produces one row with zero total and active counts'
);

select is(
  (
    with sample(status) as (
      values ('ativo'::text), ('ATIVO'), ('Ativo'), ('inativo'), (null::text)
    )
    select count(*)::bigint from sample
  ),
  5::bigint,
  'status fixture contains all five test cases'
);

select is(
  (
    with sample(status) as (
      values ('ativo'::text), ('ATIVO'), ('Ativo'), ('inativo'), (null::text)
    )
    select count(*) filter (where lower(coalesce(status, '')) = 'ativo')::bigint
    from sample
  ),
  3::bigint,
  'active rule is case-insensitive and excludes inactive and NULL statuses'
);

select * from finish();
rollback;
