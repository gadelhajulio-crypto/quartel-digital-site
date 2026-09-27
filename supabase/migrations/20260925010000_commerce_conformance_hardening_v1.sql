-- Commerce Conformance Hardening v1
-- Additive pre-production migration. Does not replace the legacy billing RPC.
-- Offer: one-time purchase -> 365 days access.
-- Renewal: extend from greatest(now(), current vigente_fim).

create table if not exists public.billing_provider_payment_state (
  id uuid primary key default gen_random_uuid(),
  gateway_nome text not null,
  gateway_pagamento_id text not null,
  recruta_id uuid not null references public.recrutas(id),
  state text not null,
  state_rank smallint not null,
  last_gateway_event_id text not null,
  last_event_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_provider_payment_state_state_chk
    check (state in ('pending','failed','succeeded','refunded','disputed')),
  constraint billing_provider_payment_state_rank_chk
    check (state_rank between 10 and 40),
  constraint billing_provider_payment_state_uq
    unique (gateway_nome, gateway_pagamento_id)
);

alter table public.billing_provider_payment_state enable row level security;
revoke all on table public.billing_provider_payment_state from anon, authenticated;
grant select, insert, update on table public.billing_provider_payment_state to service_role;

create or replace function public.rpc_billing_processar_evento_pagamento_v2(
  p_recruta_id uuid,
  p_gateway_event_id text,
  p_gateway_pagamento_id text,
  p_event_kind text,
  p_gateway_nome text default 'stripe',
  p_valor_centavos bigint default 0,
  p_moeda text default 'BRL',
  p_offer_id text default 'quartel_365d',
  p_event_at timestamptz default now(),
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment_id uuid;
  v_assinatura_id uuid;
  v_current_state text;
  v_current_rank smallint;
  v_next_state text;
  v_next_rank smallint;
  v_access_status text;
  v_start timestamptz;
  v_end timestamptz;
  v_transition_applied boolean := false;
begin
  if p_recruta_id is null then
    return jsonb_build_object('ok', false, 'erro', 'RECRUTA_ID_OBRIGATORIO');
  end if;
  if coalesce(btrim(p_gateway_event_id), '') = '' then
    return jsonb_build_object('ok', false, 'erro', 'GATEWAY_EVENT_ID_OBRIGATORIO');
  end if;
  if coalesce(btrim(p_gateway_pagamento_id), '') = '' then
    return jsonb_build_object('ok', false, 'erro', 'GATEWAY_PAGAMENTO_ID_OBRIGATORIO');
  end if;
  if p_valor_centavos < 0 then
    return jsonb_build_object('ok', false, 'erro', 'VALOR_INVALIDO');
  end if;
  if p_offer_id <> 'quartel_365d' then
    return jsonb_build_object('ok', false, 'erro', 'OFFER_NAO_SUPORTADA');
  end if;

  select bp.id into v_payment_id
  from public.billing_pagamentos bp
  where bp.gateway_nome = p_gateway_nome
    and bp.gateway_event_id = p_gateway_event_id
  limit 1;

  if v_payment_id is not null then
    return jsonb_build_object('ok', true, 'idempotente', true, 'pagamento_id', v_payment_id);
  end if;

  select x.state, x.state_rank
    into v_current_state, v_current_rank
  from public.billing_provider_payment_state x
  where x.gateway_nome = p_gateway_nome
    and x.gateway_pagamento_id = p_gateway_pagamento_id
  for update;

  case p_event_kind
    when 'payment.pending' then v_next_state := 'pending'; v_next_rank := 10;
    when 'payment.failed' then v_next_state := 'failed'; v_next_rank := 20;
    when 'payment.succeeded' then v_next_state := 'succeeded'; v_next_rank := 30;
    when 'payment.refunded' then v_next_state := 'refunded'; v_next_rank := 40;
    when 'payment.disputed' then v_next_state := 'disputed'; v_next_rank := 40;
    when 'checkout.expired' then
      insert into public.billing_eventos(gateway_nome,gateway_event_id,event_type,payload)
      values (p_gateway_nome,p_gateway_event_id,p_event_kind,
              jsonb_build_object('recruta_id',p_recruta_id,'offer_id',p_offer_id,'gateway_pagamento_id',p_gateway_pagamento_id));
      return jsonb_build_object('ok', true, 'access_mutated', false, 'event_kind', p_event_kind);
    else
      return jsonb_build_object('ok', false, 'erro', 'EVENT_KIND_NAO_SUPORTADO');
  end case;

  -- refund/dispute outrank success. Equal-rank adverse states remain adverse.
  if v_current_rank is null or v_next_rank > v_current_rank
     or (v_next_rank = v_current_rank and v_current_state = v_next_state) then
    v_transition_applied := true;
  end if;

  insert into public.billing_eventos(gateway_nome,gateway_event_id,event_type,payload)
  values (p_gateway_nome,p_gateway_event_id,p_event_kind,
          jsonb_build_object('recruta_id',p_recruta_id,'offer_id',p_offer_id,'gateway_pagamento_id',p_gateway_pagamento_id,
                             'transition_applied',v_transition_applied));

  if v_transition_applied then
    insert into public.billing_provider_payment_state(
      gateway_nome,gateway_pagamento_id,recruta_id,state,state_rank,last_gateway_event_id,last_event_at,metadata
    ) values (
      p_gateway_nome,p_gateway_pagamento_id,p_recruta_id,v_next_state,v_next_rank,p_gateway_event_id,p_event_at,
      jsonb_build_object('offer_id',p_offer_id)
    )
    on conflict (gateway_nome,gateway_pagamento_id) do update
      set state=excluded.state,state_rank=excluded.state_rank,last_gateway_event_id=excluded.last_gateway_event_id,
          last_event_at=excluded.last_event_at,metadata=excluded.metadata,updated_at=now();
  end if;

  select ba.id into v_assinatura_id
  from public.billing_assinaturas ba
  where ba.recruta_id = p_recruta_id
  for update;

  if v_transition_applied and v_next_state = 'succeeded' then
    select greatest(now(), coalesce(ba.vigente_fim, now()))
      into v_start
    from public.billing_assinaturas ba
    where ba.recruta_id = p_recruta_id;
    v_start := coalesce(v_start, now());
    v_end := v_start + interval '365 days';
    v_access_status := 'ativa';
  elsif v_transition_applied and v_next_state in ('refunded','disputed') then
    v_start := null;
    v_end := now();
    v_access_status := 'cancelada';
  elsif v_transition_applied and v_next_state = 'failed' then
    v_access_status := 'pendente';
  else
    v_access_status := null;
  end if;

  if v_access_status is not null then
    insert into public.billing_assinaturas(
      recruta_id,gateway_assinatura_id,plano,status_assinatura,vigente_inicio,vigente_fim,
      auto_renovacao,origem,ultimo_gateway_event_id,metadata
    ) values (
      p_recruta_id,p_gateway_pagamento_id,p_offer_id,v_access_status,v_start,v_end,
      false,'billing',p_gateway_event_id,jsonb_build_object('commerce_model','one_time_365d')
    )
    on conflict (recruta_id) do update set
      gateway_assinatura_id=excluded.gateway_assinatura_id,
      plano=excluded.plano,
      status_assinatura=excluded.status_assinatura,
      vigente_inicio=case when excluded.status_assinatura='ativa' then excluded.vigente_inicio else billing_assinaturas.vigente_inicio end,
      vigente_fim=case when excluded.status_assinatura='ativa' then excluded.vigente_fim else least(coalesce(billing_assinaturas.vigente_fim,now()),now()) end,
      auto_renovacao=false,
      ultimo_gateway_event_id=excluded.ultimo_gateway_event_id,
      metadata=coalesce(billing_assinaturas.metadata,'{}'::jsonb)||excluded.metadata,
      updated_at=now()
    returning id into v_assinatura_id;
  end if;

  insert into public.billing_pagamentos(
    recruta_id,assinatura_id,gateway_nome,gateway_event_id,gateway_pagamento_id,status_pagamento,
    valor_centavos,moeda,plano_referenciado,competencia_inicio,competencia_fim,payload
  ) values (
    p_recruta_id,v_assinatura_id,p_gateway_nome,p_gateway_event_id,p_gateway_pagamento_id,
    case p_event_kind
      when 'payment.pending' then 'pendente'
      when 'payment.failed' then 'falhou'
      when 'payment.succeeded' then 'confirmado'
      when 'payment.refunded' then 'estornado'
      when 'payment.disputed' then 'cancelado'
    end,
    p_valor_centavos,upper(p_moeda),p_offer_id,v_start,v_end,
    jsonb_build_object('event_kind',p_event_kind,'transition_applied',v_transition_applied)
  ) returning id into v_payment_id;

  if v_transition_applied and v_access_status is not null then
    perform public.rpc_billing_reconciliar_pagamentos(p_recruta_id);
  end if;

  insert into public.billing_reconciliacao(
    gateway_nome,gateway_event_id,recruta_id,assinatura_id,pagamento_id,acao,status_execucao,detalhes,observacao
  ) values (
    p_gateway_nome,p_gateway_event_id,p_recruta_id,v_assinatura_id,v_payment_id,
    'processar_evento_pagamento_v2','sucesso',
    jsonb_build_object('event_kind',p_event_kind,'transition_applied',v_transition_applied,
                       'previous_state',v_current_state,'next_state',v_next_state),
    case when v_transition_applied then 'TRANSICAO_APLICADA' else 'TRANSICAO_SUPERADA_IGNORADA' end
  );

  return jsonb_build_object(
    'ok',true,'idempotente',false,'transition_applied',v_transition_applied,
    'pagamento_id',v_payment_id,'assinatura_id',v_assinatura_id,
    'state',case when v_transition_applied then v_next_state else v_current_state end,
    'vigente_fim',v_end
  );
end;
$$;

revoke all on function public.rpc_billing_processar_evento_pagamento_v2(uuid,text,text,text,text,bigint,text,text,timestamptz,jsonb)
  from public, anon, authenticated;
grant execute on function public.rpc_billing_processar_evento_pagamento_v2(uuid,text,text,text,text,bigint,text,text,timestamptz,jsonb)
  to service_role;
