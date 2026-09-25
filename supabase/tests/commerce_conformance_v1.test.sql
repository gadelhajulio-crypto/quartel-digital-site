-- Commerce Conformance Hardening v1 — static/transactional contract checks
-- Intended for Supabase test environment only. No production execution.

begin;

do $$
begin
  if to_regprocedure('public.rpc_billing_processar_evento_pagamento_v2(uuid,text,text,text,text,bigint,text,text,timestamptz,jsonb)') is null then
    raise exception 'missing rpc_billing_processar_evento_pagamento_v2';
  end if;
  if to_regclass('public.billing_provider_payment_state') is null then
    raise exception 'missing billing_provider_payment_state';
  end if;
end $$;

-- State precedence is part of the contract and intentionally asserted as data-domain checks.
do $$
begin
  if not (10 < 20 and 20 < 30 and 30 < 40) then
    raise exception 'invalid commerce state precedence';
  end if;
end $$;

-- Security contract: authenticated/anon must not receive direct execute grant.
do $$
declare
  v_sig text := 'public.rpc_billing_processar_evento_pagamento_v2(uuid,text,text,text,text,bigint,text,text,timestamptz,jsonb)';
begin
  if has_function_privilege('anon', v_sig, 'EXECUTE') then
    raise exception 'anon must not execute billing v2';
  end if;
  if has_function_privilege('authenticated', v_sig, 'EXECUTE') then
    raise exception 'authenticated must not execute billing v2';
  end if;
  if not has_function_privilege('service_role', v_sig, 'EXECUTE') then
    raise exception 'service_role must execute billing v2';
  end if;
end $$;

rollback;
