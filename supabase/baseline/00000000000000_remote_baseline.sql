


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "auth";


ALTER SCHEMA "auth" OWNER TO "supabase_admin";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage";


ALTER SCHEMA "storage" OWNER TO "supabase_admin";


CREATE TYPE "auth"."aal_level" AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE "auth"."aal_level" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."code_challenge_method" AS ENUM (
    's256',
    'plain'
);


ALTER TYPE "auth"."code_challenge_method" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_status" AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE "auth"."factor_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_type" AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE "auth"."factor_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_authorization_status" AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE "auth"."oauth_authorization_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_client_type" AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE "auth"."oauth_client_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_registration_type" AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE "auth"."oauth_registration_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_response_type" AS ENUM (
    'code'
);


ALTER TYPE "auth"."oauth_response_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."one_time_token_type" AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE "auth"."one_time_token_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "storage"."buckettype" AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "auth"."email"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION "auth"."email"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."email"() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';



CREATE OR REPLACE FUNCTION "auth"."jwt"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION "auth"."jwt"() OWNER TO "supabase_auth_admin";


CREATE OR REPLACE FUNCTION "auth"."role"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION "auth"."role"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."role"() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';



CREATE OR REPLACE FUNCTION "auth"."uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION "auth"."uid"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."uid"() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';



CREATE OR REPLACE FUNCTION "public"."_auth_enforce_single_session"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
declare
  v_new_jti text;
  v_old record;
begin
  -- Assumimos que auth.sessions.id é UUID e representa bem o "jti" da sessão.
  v_new_jti := new.id::text;

  -- Revoga sessões anteriores (auditoria + evento C5) antes de removê-las
  for v_old in
    select s.id::text as old_jti
    from auth.sessions s
    where s.user_id = new.user_id
      and s.id <> new.id
  loop
    insert into public.auth_session_revocations(auth_id, revoked_jti, revoked_reason, new_jti)
    values (new.user_id, v_old.old_jti, 'security_logout', v_new_jti);

    perform public._c5_emit_auth_logout(new.user_id, v_old.old_jti, 'security_logout');
  end loop;

  -- Persistir a sessão vigente (singleton)
  insert into public.auth_session_singleton(auth_id, current_jti, updated_at)
  values (new.user_id, v_new_jti, now())
  on conflict (auth_id)
  do update set current_jti = excluded.current_jti, updated_at = excluded.updated_at;

  -- Revogar sessões anteriores no backend (hard enforcement)
  delete from auth.sessions
  where user_id = new.user_id
    and id <> new.id;

  return new;
end;
$$;


ALTER FUNCTION "public"."_auth_enforce_single_session"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_auth_enforce_single_session"() IS 'RCC v0.3: Enforce single session per user on auth.sessions INSERT. Revokes prior sessions as security_logout.';



CREATE OR REPLACE FUNCTION "public"."_c5_emit_auth_logout"("p_auth_id" "uuid", "p_session_jti" "text", "p_reason" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_recruta_id uuid;
  v_idempotency_key text;
  v_correlation_id text;
  v_payload jsonb;
begin
  if p_reason not in ('none','user_action','session_expired','security_logout') then
    raise exception 'Invalid reason for auth logout: %', p_reason;
  end if;

  -- recruta dominante
  select r.id into v_recruta_id
  from public.recrutas r
  where r.auth_id = p_auth_id
  limit 1;

  if v_recruta_id is null then
    raise notice 'C5 emit skipped: recruta não encontrado para auth_id=%', p_auth_id;
    return;
  end if;

  -- Idempotência: determinística por auth_id + sessão revogada (jti/id) + reason
  -- (isso garante que "o mesmo logout remoto" não gera múltiplos received equivalentes)
  v_idempotency_key := 'auth_logout:' || p_auth_id::text || ':' || coalesce(p_session_jti,'') || ':' || p_reason;

  -- Correlação: preferir jti, senão usar auth_id
  v_correlation_id := coalesce(nullif(p_session_jti,''), p_auth_id::text);

  -- Payload canônico (inclui metadados operacionais no envelope para o pipeline atual)
  v_payload := jsonb_build_object(
    'titulo', 'Logout',
    'descricao', 'Sessão encerrada por segurança.',
    'prioridade', 5,
    'payload', jsonb_build_object('reason', p_reason)
  );

  -- Emissão canônica (anti-bypass): overload 6 args
  perform public.emitir_evento_c5(
    v_recruta_id,
    'auth',               -- tipo_evento (contrato)
    v_idempotency_key,    -- idempotency_key (contrato de idempotência)
    v_correlation_id,     -- correlation_id (observabilidade)
    'sistema',            -- origem (CHECK exige)
    v_payload             -- payload (contrato)
  );
end;
$$;


ALTER FUNCTION "public"."_c5_emit_auth_logout"("p_auth_id" "uuid", "p_session_jti" "text", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_c5_emit_auth_logout"("p_auth_id" "uuid", "p_session_jti" "text", "p_reason" "text") IS 'RCC v0.3: Emite logout remoto via RPC canônico emitir_evento_c5 com idempotência determinística por idempotency_key. Sem índice global.';



CREATE OR REPLACE FUNCTION "public"."_dash_columns"() RETURNS TABLE("column_name" "text", "data_type" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT c.column_name::text, c.data_type::text
  FROM information_schema.columns c
  WHERE c.table_schema='public'
    AND c.table_name='v_execucao_diaria_dashboard'
  ORDER BY c.ordinal_position;
$$;


ALTER FUNCTION "public"."_dash_columns"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_dash_json"("p_recruta_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_key_col text := public._dash_key_column();
  v_sql text;
  v_j jsonb;

  v_auth_id uuid;
  v_prev_sub text;
  v_prev_role text;
  v_need_inject boolean := (auth.uid() IS NULL);

BEGIN
  -- Se não há coluna chave detectável, não há como filtrar
  IF v_key_col IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  -- Buscar auth_id do recruta (para injetar contexto quando necessário)
  SELECT r.auth_id INTO v_auth_id
  FROM public.recrutas r
  WHERE r.id = p_recruta_id
  LIMIT 1;

  IF v_auth_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  -- Salvar settings atuais
  v_prev_sub  := current_setting('request.jwt.claim.sub', true);
  v_prev_role := current_setting('request.jwt.claim.role', true);

  -- Injetar contexto somente quando auth.uid() é NULL (SQL Editor)
  IF v_need_inject THEN
    PERFORM set_config('request.jwt.claim.sub',  v_auth_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  END IF;

  -- Montar SQL de leitura da view
  v_sql := format(
    'SELECT to_jsonb(d) FROM public.v_execucao_diaria_dashboard d WHERE d.%I = $1 LIMIT 1',
    v_key_col
  );

  -- Se a coluna chave for auth_id, o filtro muda: compara com v_auth_id
  IF v_key_col = 'auth_id' THEN
    EXECUTE v_sql INTO v_j USING v_auth_id;
  ELSE
    EXECUTE v_sql INTO v_j USING p_recruta_id;
  END IF;

  -- Restaurar settings (reverte o contexto)
  IF v_need_inject THEN
    PERFORM set_config('request.jwt.claim.sub',  COALESCE(v_prev_sub,''),  true);
    PERFORM set_config('request.jwt.claim.role', COALESCE(v_prev_role,''), true);
  END IF;

  RETURN COALESCE(v_j, '{}'::jsonb);
END;
$_$;


ALTER FUNCTION "public"."_dash_json"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_dash_json_v2"("p_recruta_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_key text := public._dash_key_column_v2();
  v_sql text;
  v_j jsonb;
BEGIN
  IF v_key IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  v_sql := format(
    'SELECT to_jsonb(d) FROM public.v_execucao_diaria_dashboard d WHERE d.%I = $1 LIMIT 1',
    v_key
  );

  BEGIN
    EXECUTE v_sql INTO v_j USING p_recruta_id;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('erro', SQLERRM, 'sql', v_sql);
  END;

  RETURN COALESCE(v_j, '{}'::jsonb);
END;
$_$;


ALTER FUNCTION "public"."_dash_json_v2"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_dash_key_column"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_key_col text;
BEGIN
  SELECT c.column_name INTO v_key_col
  FROM information_schema.columns c
  WHERE c.table_schema='public'
    AND c.table_name='v_execucao_diaria_dashboard'
    AND c.column_name IN ('recruta_id','user_id','id','recruta','recrutaid','recruta_uuid','auth_id')
  ORDER BY CASE c.column_name
    WHEN 'recruta_id' THEN 1
    WHEN 'user_id'    THEN 2
    WHEN 'id'         THEN 3
    WHEN 'recruta'    THEN 4
    WHEN 'recrutaid'  THEN 5
    WHEN 'recruta_uuid' THEN 6
    WHEN 'auth_id'    THEN 7
    ELSE 99
  END
  LIMIT 1;

  RETURN v_key_col;
END;
$$;


ALTER FUNCTION "public"."_dash_key_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_dash_key_column_v2"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_key text;
BEGIN
  SELECT c.column_name INTO v_key
  FROM information_schema.columns c
  WHERE c.table_schema='public'
    AND c.table_name='v_execucao_diaria_dashboard'
    AND c.column_name IN ('recruta_id','user_id','id','recruta','recrutaid','recruta_uuid','auth_id')
  ORDER BY CASE c.column_name
    WHEN 'recruta_id' THEN 1
    WHEN 'user_id'    THEN 2
    WHEN 'id'         THEN 3
    WHEN 'recruta'    THEN 4
    WHEN 'recrutaid'  THEN 5
    WHEN 'recruta_uuid' THEN 6
    WHEN 'auth_id'    THEN 7
    ELSE 99
  END
  LIMIT 1;

  IF v_key IS NOT NULL THEN
    RETURN v_key;
  END IF;

  SELECT c.column_name INTO v_key
  FROM information_schema.columns c
  WHERE c.table_schema='public'
    AND c.table_name='v_execucao_diaria_dashboard'
    AND (c.udt_name='uuid' OR c.data_type ILIKE '%uuid%')
  ORDER BY c.ordinal_position
  LIMIT 1;

  RETURN v_key;
END;
$$;


ALTER FUNCTION "public"."_dash_key_column_v2"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_dash_num"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric DEFAULT 0) RETURNS numeric
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_txt text;
BEGIN
  v_txt := public._dash_text(p_recruta_id, p_keys);
  IF v_txt IS NULL THEN
    RETURN p_default;
  END IF;

  BEGIN
    RETURN v_txt::numeric;
  EXCEPTION WHEN others THEN
    RETURN p_default;
  END;
END;
$$;


ALTER FUNCTION "public"."_dash_num"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_dash_num_v2"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric DEFAULT 0) RETURNS numeric
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_txt text;
BEGIN
  v_txt := public._dash_text_v2(p_recruta_id, p_keys);
  IF v_txt IS NULL THEN
    RETURN p_default;
  END IF;

  BEGIN
    RETURN v_txt::numeric;
  EXCEPTION WHEN others THEN
    RETURN p_default;
  END;
END;
$$;


ALTER FUNCTION "public"."_dash_num_v2"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_dash_text"("p_recruta_id" "uuid", "p_keys" "text"[]) RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_j jsonb := public._dash_json(p_recruta_id);
  v_key text;
  v_val text;
BEGIN
  FOREACH v_key IN ARRAY p_keys LOOP
    v_val := v_j->>v_key;
    IF v_val IS NOT NULL AND btrim(v_val) <> '' THEN
      RETURN v_val;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."_dash_text"("p_recruta_id" "uuid", "p_keys" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_dash_text_v2"("p_recruta_id" "uuid", "p_keys" "text"[]) RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_j jsonb := public._dash_json_v2(p_recruta_id);
  v_key text;
  v_val text;
BEGIN
  FOREACH v_key IN ARRAY p_keys LOOP
    v_val := v_j->>v_key;
    IF v_val IS NOT NULL AND btrim(v_val) <> '' THEN
      RETURN v_val;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."_dash_text_v2"("p_recruta_id" "uuid", "p_keys" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_emitir_evento_c5_iea_marco"("p_recruta_id" "uuid", "p_ciclo_id" "uuid", "p_snapshot_id" "uuid", "p_marco" integer, "p_iea_score" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_evento_id uuid;
  v_evento_status text;
BEGIN
  IF p_recruta_id IS NULL THEN
    RAISE EXCEPTION 'IEA_C5_RECRUTA_REQUIRED';
  END IF;

  IF p_snapshot_id IS NULL THEN
    RAISE EXCEPTION 'IEA_C5_SNAPSHOT_REQUIRED';
  END IF;

  SELECT e.evento_id, e.status
  INTO v_evento_id, v_evento_status
  FROM public.emitir_evento_c5(
    p_recruta_id,
    'iea_marco_atingido',
    'iea_marco_atingido:' || p_recruta_id::text || ':' || p_snapshot_id::text || ':' || p_marco::text,
    p_snapshot_id::text,
    'sistema',
    jsonb_build_object(
      'ciclo_id', p_ciclo_id,
      'snapshot_id', p_snapshot_id,
      'marco', p_marco,
      'iea_score', p_iea_score,
      'titulo', 'Marco de Excelência Acadêmica',
      'descricao', format('Marco institucional atingido: %s (IEA atual: %s).', p_marco, p_iea_score),
      'origem', '_emitir_evento_c5_iea_marco'
    )
  ) e
  LIMIT 1;
END;
$$;


ALTER FUNCTION "public"."_emitir_evento_c5_iea_marco"("p_recruta_id" "uuid", "p_ciclo_id" "uuid", "p_snapshot_id" "uuid", "p_marco" integer, "p_iea_score" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_is_service_role"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role';
$$;


ALTER FUNCTION "public"."_is_service_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_jwt_jti"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select nullif(current_setting('request.jwt.claim.jti', true), '');
$$;


ALTER FUNCTION "public"."_jwt_jti"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_jwt_jti"() IS 'Retorna JWT claim jti quando disponível (usado para mapear sessão ativa vs revogada).';



CREATE OR REPLACE FUNCTION "public"."_set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."_set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_uuid_from_text"("p_text" "text") RETURNS "uuid"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select (
    substr(md5(p_text), 1, 8) || '-' ||
    substr(md5(p_text), 9, 4) || '-' ||
    substr(md5(p_text), 13, 4) || '-' ||
    substr(md5(p_text), 17, 4) || '-' ||
    substr(md5(p_text), 21, 12)
  )::uuid;
$$;


ALTER FUNCTION "public"."_uuid_from_text"("p_text" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_uuid_from_text"("p_text" "text") IS 'Gera UUID determinístico via md5(text) -> uuid, sem dependência de extensões.';



CREATE OR REPLACE FUNCTION "public"."aplicar_alteracao_medalha"("p_alteracao_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_alteracao record;
    v_snapshot_versao integer;
begin
    select *
      into v_alteracao
      from public.medalhas_alteracoes_pendentes
     where id = p_alteracao_id
     for update;

    if not found then
        raise exception 'Alteração % não encontrada.', p_alteracao_id;
    end if;

    if v_alteracao.status <> 'APROVADA' then
        raise exception 'Alteração precisa estar APROVADA para aplicação. Status atual=%', v_alteracao.status;
    end if;

    -- Snapshot obrigatório antes de publicar
    select public.snapshot_medalha(v_alteracao.medalha_id)
      into v_snapshot_versao;

    -- Atualiza catálogo (mínimo: slug/active; sem inventar colunas)
    update public.medalhas_catalogo mc
       set slug   = coalesce((v_alteracao.proposta_catalogo ->> 'slug')::text, mc.slug),
           active = coalesce((v_alteracao.proposta_catalogo ->> 'active')::boolean, mc.active)
     where mc.id = v_alteracao.medalha_id;

    -- Substituir regras atuais
    delete from public.medalha_regras
     where medalha_id = v_alteracao.medalha_id;

    -- ✅ Inserir regras usando o tipo REAL da tabela (sem assumir colunas)
    -- Importante: precisa estar dentro de SELECT/INSERT.
    -- Se proposta_regras='[]', insere 0 linhas (ok).
    insert into public.medalha_regras
    select *
      from jsonb_populate_recordset(null::public.medalha_regras, v_alteracao.proposta_regras);

    -- Marcar como aplicada
    update public.medalhas_alteracoes_pendentes
       set status  = 'APLICADA',
           aplicado = true
     where id = p_alteracao_id;
end;
$$;


ALTER FUNCTION "public"."aplicar_alteracao_medalha"("p_alteracao_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."aprovar_alteracao_medalha"("p_alteracao_id" "uuid", "p_aprovado_por" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_status text;
begin

    select status into v_status
    from public.medalhas_alteracoes_pendentes
    where id = p_alteracao_id;

    if not found then
        raise exception 'Alteração % não encontrada.', p_alteracao_id;
    end if;

    if v_status <> 'PENDENTE' then
        raise exception 'Alteração não está em status PENDENTE.';
    end if;

    update public.medalhas_alteracoes_pendentes
    set status = 'APROVADA',
        aprovado_por = p_aprovado_por,
        aprovado_em = now()
    where id = p_alteracao_id;

end;
$$;


ALTER FUNCTION "public"."aprovar_alteracao_medalha"("p_alteracao_id" "uuid", "p_aprovado_por" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."atribuir_missao_inicial"("p_recruta_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_missao_id uuid;
begin
  -- Buscar a missão inicial
  select id into v_missao_id
  from missoes
  where codigo = 'MISSAO_INICIAL'
  limit 1;

  -- Se não existir missão, aborta
  if v_missao_id is null then
    return;
  end if;

  -- Inserir progresso se ainda não existir
  insert into progresso_missoes (recruta_id, missao_id)
  values (p_recruta_id, v_missao_id)
  on conflict (recruta_id, missao_id) do nothing;
end;
$$;


ALTER FUNCTION "public"."atribuir_missao_inicial"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."billing_emitir_evento_c5"("p_tipo" "text", "p_payload" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
begin
  if to_regprocedure('public.emitir_evento_c5(text,jsonb)') is not null then
    execute 'select public.emitir_evento_c5($1,$2)'
      using p_tipo, p_payload;
    return true;
  elsif to_regprocedure('public.emitir_evento_c5(jsonb)') is not null then
    execute 'select public.emitir_evento_c5($1)'
      using jsonb_build_object('tipo', p_tipo, 'payload', p_payload);
    return true;
  else
    return false;
  end if;
end;
$_$;


ALTER FUNCTION "public"."billing_emitir_evento_c5"("p_tipo" "text", "p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buscar_revisoes_whatsapp"() RETURNS TABLE("revisao_id" "uuid", "recruta_id" "uuid", "missao_id" "uuid", "forca" "text")
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  select
    r.id as revisao_id,
    r.recruta_id,
    r.missao_id,
    m.forca
  from public.revisoes r
  join public.missoes m on m.id = r.missao_id
  where r.tipo = 'whatsapp'
    and r.status = 'pendente'
  order by r.criada_em
  limit 10;
$$;


ALTER FUNCTION "public"."buscar_revisoes_whatsapp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."c5_auditar_evento_institucional"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_jwt_role text;
  v_jwt_sub uuid;
BEGIN
  BEGIN
    v_jwt_role := current_setting('request.jwt.claim.role', true);
  EXCEPTION WHEN others THEN
    v_jwt_role := NULL;
  END;

  BEGIN
    v_jwt_sub := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  EXCEPTION WHEN others THEN
    v_jwt_sub := NULL;
  END;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.c5_audit_eventos_institucionais(
      evento_id, operacao, jwt_role, jwt_sub, old_row, new_row
    ) VALUES (
      NEW.id, 'INSERT', v_jwt_role, v_jwt_sub, NULL, to_jsonb(NEW)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.c5_audit_eventos_institucionais(
      evento_id, operacao, jwt_role, jwt_sub, old_row, new_row
    ) VALUES (
      NEW.id, 'UPDATE', v_jwt_role, v_jwt_sub, to_jsonb(OLD), to_jsonb(NEW)
    );
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.c5_audit_eventos_institucionais(
      evento_id, operacao, jwt_role, jwt_sub, old_row, new_row
    ) VALUES (
      OLD.id, 'DELETE', v_jwt_role, v_jwt_sub, to_jsonb(OLD), NULL
    );
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."c5_auditar_evento_institucional"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."c5_guard_eventos_institucionais"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_gate text;
BEGIN
  v_gate := current_setting('c5.gateway', true);

  -- Permite apenas se passou pelo gateway
  IF v_gate IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'C5_WRITE_BLOCKED: use public.emitir_evento_c5(...) (anti-bypass ativo)'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."c5_guard_eventos_institucionais"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."c5_normalizar_evento_institucional"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Normalização específica para PATENTE (promoção)
  IF NEW.tipo = 'patente' THEN

    -- Corrige placeholders legados
    IF NEW.titulo = 'x' OR NEW.titulo IS NULL OR length(trim(NEW.titulo)) = 0 THEN
      NEW.titulo := 'Promoção de Patente';
    END IF;

    IF NEW.descricao = 'x' OR NEW.descricao IS NULL OR length(trim(NEW.descricao)) = 0 THEN
      NEW.descricao := 'Promoção registrada conforme regulamento institucional';
    END IF;

    -- Prioridade institucional de patente (padrão oficial do seu emissor)
    -- Se quiser manter liberdade, comente esta linha.
    IF NEW.prioridade IS NULL OR NEW.prioridade <> 1 THEN
      NEW.prioridade := 1;
    END IF;

    -- referencia_id é obrigatória no schema, então não ajustamos aqui.
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."c5_normalizar_evento_institucional"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."c5_recruta_id_for_auth"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select r.id
  from public.recrutas r
  where r.auth_id = auth.uid()
  limit 1
$$;


ALTER FUNCTION "public"."c5_recruta_id_for_auth"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."c5_recruta_id_for_auth"() IS 'Resolve recruta_id do usuário autenticado (auth.uid()) via public.recrutas. SECURITY DEFINER para suportar RLS C5 sem conceder SELECT direto em public.recrutas.';



CREATE OR REPLACE FUNCTION "public"."c6_get_iea_score"("p_recruta_id" "uuid", "p_ciclo_id" "uuid") RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_score numeric := NULL;
BEGIN
  -- Tentativa 1: view/tabela padrão (se existir) -> public.v_iea_recruta_ciclo(recruta_id,ciclo_id,iea_score)
  IF to_regclass('public.v_iea_recruta_ciclo') IS NOT NULL THEN
    EXECUTE
      'SELECT iea_score FROM public.v_iea_recruta_ciclo WHERE recruta_id = $1 AND ciclo_id = $2 LIMIT 1'
    INTO v_score
    USING p_recruta_id, p_ciclo_id;
    RETURN v_score;
  END IF;

  -- Tentativa 2: tabela genérica (se existir) -> public.iea_scores(recruta_id,ciclo_id,score)
  IF to_regclass('public.iea_scores') IS NOT NULL THEN
    EXECUTE
      'SELECT score FROM public.iea_scores WHERE recruta_id = $1 AND ciclo_id = $2 LIMIT 1'
    INTO v_score
    USING p_recruta_id, p_ciclo_id;
    RETURN v_score;
  END IF;

  RETURN NULL;
END;
$_$;


ALTER FUNCTION "public"."c6_get_iea_score"("p_recruta_id" "uuid", "p_ciclo_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."c6_get_simulado_final_score"("p_recruta_id" "uuid", "p_ciclo_id" "uuid") RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_score numeric := NULL;
BEGIN
  -- Tentativa 1: view padrão (se existir) -> public.v_simulado_final_ciclo(recruta_id,ciclo_id,nota)
  IF to_regclass('public.v_simulado_final_ciclo') IS NOT NULL THEN
    EXECUTE
      'SELECT nota FROM public.v_simulado_final_ciclo WHERE recruta_id = $1 AND ciclo_id = $2 LIMIT 1'
    INTO v_score
    USING p_recruta_id, p_ciclo_id;
    RETURN v_score;
  END IF;

  -- Tentativa 2: tabela genérica (se existir) -> public.simulados_resultados(recruta_id,ciclo_id,nota,final boolean)
  IF to_regclass('public.simulados_resultados') IS NOT NULL THEN
    EXECUTE
      'SELECT nota FROM public.simulados_resultados WHERE recruta_id = $1 AND ciclo_id = $2 AND (final IS TRUE) ORDER BY created_at DESC LIMIT 1'
    INTO v_score
    USING p_recruta_id, p_ciclo_id;
    RETURN v_score;
  END IF;

  RETURN NULL;
END;
$_$;


ALTER FUNCTION "public"."c6_get_simulado_final_score"("p_recruta_id" "uuid", "p_ciclo_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."c6_set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."c6_set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."c9_set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."c9_set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calc_nivel_por_xp"("p_xp" integer) RETURNS integer
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
BEGIN
  IF p_xp < 500 THEN
    RETURN 1;
  ELSIF p_xp < 1500 THEN
    RETURN 2;
  ELSIF p_xp < 3000 THEN
    RETURN 3;
  ELSIF p_xp < 5000 THEN
    RETURN 4;
  ELSE
    RETURN 5;
  END IF;
END;
$$;


ALTER FUNCTION "public"."calc_nivel_por_xp"("p_xp" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calcular_regularidade_relativa"("p_recruta_id" "uuid") RETURNS numeric
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public'
    AS $$
declare
  v_semanas_validas numeric;
  v_data_inicio date;
  v_meta constant numeric := 12;
  v_ratio numeric;
begin
  select rcs.semanas_validas::numeric,
         rcs.data_inicio_individual
    into v_semanas_validas,
         v_data_inicio
  from public.recruta_ciclo_status rcs
  where rcs.recruta_id = p_recruta_id
  limit 1;

  -- Se ainda não iniciou (ou registro não existe), retorna 0 (função nunca NULL)
  if v_data_inicio is null or current_date < v_data_inicio then
    return 0;
  end if;

  v_semanas_validas := coalesce(v_semanas_validas, 0);

  if v_meta <= 0 then
    return 0;
  end if;

  v_ratio := v_semanas_validas / v_meta;

  if v_ratio is null or v_ratio < 0 then
    v_ratio := 0;
  end if;

  if v_ratio > 1 then
    v_ratio := 1;
  end if;

  return v_ratio;
end;
$$;


ALTER FUNCTION "public"."calcular_regularidade_relativa"("p_recruta_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."calcular_regularidade_relativa"("p_recruta_id" "uuid") IS 'C6.2: regularidade relativa = public.recruta_ciclo_status.semanas_validas / 12. STABLE. Retorna 0..1, nunca NULL, clamp.';



CREATE OR REPLACE FUNCTION "public"."calcular_semana_relativa"("p_recruta_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public'
    AS $$
declare
  v_data_inicio date;
  v_semana integer;
begin
  select rcs.data_inicio_individual
    into v_data_inicio
  from public.recruta_ciclo_status rcs
  where rcs.recruta_id = p_recruta_id
  limit 1;

  if v_data_inicio is null then
    return 1;
  end if;

  v_semana := floor(((current_date - v_data_inicio)::numeric) / 7)::int + 1;

  if v_semana < 1 then
    return 1;
  end if;

  return v_semana;
end;
$$;


ALTER FUNCTION "public"."calcular_semana_relativa"("p_recruta_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."calcular_semana_relativa"("p_recruta_id" "uuid") IS 'C6.2: semana relativa individual = floor((current_date - data_inicio_individual)/7)+1; NULL->1; mínimo 1. Fonte: public.recruta_ciclo_status.data_inicio_individual. STABLE.';



CREATE OR REPLACE FUNCTION "public"."complete_lesson"("p_recruta_id" "uuid", "p_lesson_id" "uuid", "p_xp" integer DEFAULT 50) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_ja_concluida boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.recruta_progresso
    WHERE recruta_id = p_recruta_id
      AND lesson_id = p_lesson_id
      AND completed_at IS NOT NULL
  ) INTO v_ja_concluida;

  IF v_ja_concluida THEN
    RETURN json_build_object(
      'status', 'ok',
      'xp_granted', false,
      'message', 'Aula já concluída anteriormente'
    );
  END IF;

  INSERT INTO public.recruta_progresso (
    recruta_id,
    lesson_id,
    status,
    completed_at,
    xp_granted,
    source
  )
  VALUES (
    p_recruta_id,
    p_lesson_id,
    'completed',
    now(),
    p_xp,
    'lesson_complete'
  )
  ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

  INSERT INTO public.xp_eventos (
    recruta_id,
    forca,
    quantidade,
    origem,
    referencia_id
  )
  SELECT
    r.id,
    r.forca,
    p_xp,
    'lesson_complete',
    p_lesson_id
  FROM public.recrutas r
  WHERE r.id = p_recruta_id
  ON CONFLICT DO NOTHING;

  RETURN json_build_object(
    'status', 'ok',
    'xp_granted', true,
    'xp_added', p_xp
  );
END;
$$;


ALTER FUNCTION "public"."complete_lesson"("p_recruta_id" "uuid", "p_lesson_id" "uuid", "p_xp" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_lenda_viva"("p_recruta" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE recruta_status
  SET
    nivel = 6,
    patente = 'LENDA_VIVA',
    honra_maxima = true,
    atualizado_em = now()
  WHERE recruta_id = p_recruta;
END;
$$;


ALTER FUNCTION "public"."conceder_lenda_viva"("p_recruta" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.conceder_medalha_v2(
    p_recruta_id,
    p_medalha_slug
  );

  RETURN COALESCE((v_result->>'ok')::boolean, false);
END;
$$;


ALTER FUNCTION "public"."conceder_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_medalha_v2"("p_recruta_id" "uuid", "p_medalha_slug" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_input_slug text;
  v_slug_resolvido text;
  v_medalha_id uuid;
  v_concessao_id uuid;
  v_concedida_agora boolean := false;
  v_evento_id uuid;
  v_evento_status text;
BEGIN
  v_input_slug := nullif(btrim(lower(p_medalha_slug)), '');

  IF v_input_slug IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'motivo', 'slug_invalido',
      'slug_resolvido', p_medalha_slug
    );
  END IF;

  SELECT a.slug_canonico
  INTO v_slug_resolvido
  FROM public.medalhas_slug_aliases a
  WHERE lower(a.slug_alias) = v_input_slug
    AND COALESCE(a.active, true) = true
  LIMIT 1;

  v_slug_resolvido := COALESCE(v_slug_resolvido, v_input_slug);

  SELECT mc.id
  INTO v_medalha_id
  FROM public.medalhas_catalogo mc
  WHERE mc.slug = v_slug_resolvido
    AND mc.active = true
  LIMIT 1;

  IF v_medalha_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'motivo', 'slug_invalido',
      'slug_resolvido', v_slug_resolvido
    );
  END IF;

  INSERT INTO public.medalhas_concedidas (
    recruta_id,
    medalha_id
  )
  VALUES (
    p_recruta_id,
    v_medalha_id
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_concessao_id;

  v_concedida_agora := (v_concessao_id IS NOT NULL);

  IF v_concedida_agora THEN
    SELECT e.evento_id, e.status
    INTO v_evento_id, v_evento_status
    FROM public.emitir_evento_c5(
      p_recruta_id,
      'medalha_concedida',
      'medalha_concedida:' || p_recruta_id::text || ':' || v_medalha_id::text,
      COALESCE(v_concessao_id::text, v_medalha_id::text),
      'sistema',
      jsonb_build_object(
        'medalha_id', v_medalha_id,
        'slug', v_slug_resolvido,
        'titulo', 'Medalha Concedida',
        'descricao', 'Nova medalha concedida ao recruta.',
        'origem', 'conceder_medalha_v2'
      )
    ) e
    LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'medalha_id', v_medalha_id,
    'slug_resolvido', v_slug_resolvido,
    'concedida_agora', v_concedida_agora,
    'evento_id', v_evento_id,
    'evento_status', v_evento_status
  );
END;
$$;


ALTER FUNCTION "public"."conceder_medalha_v2"("p_recruta_id" "uuid", "p_medalha_slug" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."conceder_medalha_v2"("p_recruta_id" "uuid", "p_medalha_slug" "text") IS 'INTERNAL C5 FUNCTION. Direct frontend execution forbidden. Medalhas devem ser concedidas por eventos institucionais via emitir_evento_c5.';



CREATE OR REPLACE FUNCTION "public"."conceder_xp_modulo"("p_user_id" "uuid", "p_modulo_id" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_periodo text;
  v_xp_base integer := 100;
  v_xp_total_hoje integer := 0;
  v_ja_concedido boolean := false;
  v_xp_a_conceder integer := 0;
begin
  v_periodo := to_char(current_date, 'YYYY-MM');

  -- Verificar se módulo já foi concluído
  select exists (
    select 1
    from xp_events
    where user_id = p_user_id
      and tipo = 'modulo_concluido'
      and periodo = v_periodo
      and xp > 0
      and reference = p_modulo_id
  )
  into v_ja_concedido;

  if v_ja_concedido then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'modulo_ja_concluido'
    );
  end if;

  -- XP total ganho hoje
  select coalesce(sum(xp), 0)
  into v_xp_total_hoje
  from xp_events
  where user_id = p_user_id
    and created_at::date = current_date;

  -- Respeitar limite diário geral
  if v_xp_total_hoje + v_xp_base > 200 then
    v_xp_a_conceder := greatest(0, 200 - v_xp_total_hoje);
  else
    v_xp_a_conceder := v_xp_base;
  end if;

  if v_xp_a_conceder = 0 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'limite_diario_geral'
    );
  end if;

  -- Registrar evento
  insert into xp_events (
    user_id,
    tipo,
    xp,
    periodo,
    reference
  )
  values (
    p_user_id,
    'modulo_concluido',
    v_xp_a_conceder,
    v_periodo,
    p_modulo_id
  );

  -- Atualizar XP do usuário
  update user_xp
  set
    xp_total = xp_total + v_xp_a_conceder,
    xp_periodo = xp_periodo + v_xp_a_conceder,
    xp_merito = xp_merito + v_xp_a_conceder,
    last_xp_at = now(),
    updated_at = now()
  where user_id = p_user_id;

  return json_build_object(
    'xp_concedido', v_xp_a_conceder,
    'motivo', 'concedido'
  );
end;
$$;


ALTER FUNCTION "public"."conceder_xp_modulo"("p_user_id" "uuid", "p_modulo_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_xp_revisao_recomendada"("p_user_id" "uuid", "p_revisao_id" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_periodo text;
  v_xp_base integer := 30;
  v_xp_total_hoje integer := 0;
  v_ja_concedido boolean := false;
  v_xp_a_conceder integer := 0;
begin
  v_periodo := to_char(current_date, 'YYYY-MM');

  -- Verificar se a revisão já foi contabilizada
  select exists (
    select 1
    from xp_events
    where user_id = p_user_id
      and tipo = 'revisao_recomendada'
      and reference = p_revisao_id
  )
  into v_ja_concedido;

  if v_ja_concedido then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'revisao_ja_concluida'
    );
  end if;

  -- XP total ganho hoje
  select coalesce(sum(xp), 0)
  into v_xp_total_hoje
  from xp_events
  where user_id = p_user_id
    and created_at::date = current_date;

  -- Respeitar limite diário geral
  if v_xp_total_hoje + v_xp_base > 200 then
    v_xp_a_conceder := greatest(0, 200 - v_xp_total_hoje);
  else
    v_xp_a_conceder := v_xp_base;
  end if;

  if v_xp_a_conceder = 0 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'limite_diario_geral'
    );
  end if;

  -- Registrar evento
  insert into xp_events (
    user_id,
    tipo,
    xp,
    periodo,
    reference
  )
  values (
    p_user_id,
    'revisao_recomendada',
    v_xp_a_conceder,
    v_periodo,
    p_revisao_id
  );

  -- Atualizar XP do usuário
  update user_xp
  set
    xp_total = xp_total + v_xp_a_conceder,
    xp_periodo = xp_periodo + v_xp_a_conceder,
    xp_merito = xp_merito + v_xp_a_conceder,
    last_xp_at = now(),
    updated_at = now()
  where user_id = p_user_id;

  return json_build_object(
    'xp_concedido', v_xp_a_conceder,
    'motivo', 'concedido'
  );
end;
$$;


ALTER FUNCTION "public"."conceder_xp_revisao_recomendada"("p_user_id" "uuid", "p_revisao_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_xp_revisao_voluntaria"("p_user_id" "uuid", "p_revisao_id" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_periodo text;
  v_xp_base integer := 60;
  v_xp_total_hoje integer := 0;
  v_ja_concedido boolean := false;
  v_xp_a_conceder integer := 0;
begin
  v_periodo := to_char(current_date, 'YYYY-MM');

  -- Verificar se a revisão já foi contabilizada
  select exists (
    select 1
    from xp_events
    where user_id = p_user_id
      and tipo = 'revisao_voluntaria'
      and reference = p_revisao_id
  )
  into v_ja_concedido;

  if v_ja_concedido then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'revisao_ja_concluida'
    );
  end if;

  -- XP total ganho hoje
  select coalesce(sum(xp), 0)
  into v_xp_total_hoje
  from xp_events
  where user_id = p_user_id
    and created_at::date = current_date;

  -- Respeitar limite diário geral
  if v_xp_total_hoje + v_xp_base > 200 then
    v_xp_a_conceder := greatest(0, 200 - v_xp_total_hoje);
  else
    v_xp_a_conceder := v_xp_base;
  end if;

  if v_xp_a_conceder = 0 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'limite_diario_geral'
    );
  end if;

  -- Registrar evento
  insert into xp_events (
    user_id,
    tipo,
    xp,
    periodo,
    reference
  )
  values (
    p_user_id,
    'revisao_voluntaria',
    v_xp_a_conceder,
    v_periodo,
    p_revisao_id
  );

  -- Atualizar XP do usuário
  update user_xp
  set
    xp_total = xp_total + v_xp_a_conceder,
    xp_periodo = xp_periodo + v_xp_a_conceder,
    xp_merito = xp_merito + v_xp_a_conceder,
    last_xp_at = now(),
    updated_at = now()
  where user_id = p_user_id;

  return json_build_object(
    'xp_concedido', v_xp_a_conceder,
    'motivo', 'concedido'
  );
end;
$$;


ALTER FUNCTION "public"."conceder_xp_revisao_voluntaria"("p_user_id" "uuid", "p_revisao_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_xp_simulado"("p_user_id" "uuid", "p_simulado_id" "text", "p_percentual_acerto" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_periodo text;
  v_xp_base integer := 40;
  v_xp_bonus integer := 0;
  v_xp_total integer := 0;
  v_xp_total_hoje integer := 0;
  v_ja_concedido boolean := false;
begin
  v_periodo := to_char(current_date, 'YYYY-MM');

  -- Verificar se simulado já foi contabilizado
  select exists (
    select 1
    from xp_events
    where user_id = p_user_id
      and tipo = 'simulado_concluido'
      and reference = p_simulado_id
  )
  into v_ja_concedido;

  if v_ja_concedido then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'simulado_ja_concluido'
    );
  end if;

  -- Definir bônus por desempenho
  if p_percentual_acerto >= 90 then
    v_xp_bonus := 60;
  elsif p_percentual_acerto >= 80 then
    v_xp_bonus := 40;
  elsif p_percentual_acerto >= 70 then
    v_xp_bonus := 20;
  else
    v_xp_bonus := 0;
  end if;

  v_xp_total := v_xp_base + v_xp_bonus;

  -- XP total ganho hoje
  select coalesce(sum(xp), 0)
  into v_xp_total_hoje
  from xp_events
  where user_id = p_user_id
    and created_at::date = current_date;

  -- Respeitar limite diário geral
  if v_xp_total_hoje + v_xp_total > 200 then
    v_xp_total := greatest(0, 200 - v_xp_total_hoje);
  end if;

  if v_xp_total = 0 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'limite_diario_geral'
    );
  end if;

  -- Registrar evento
  insert into xp_events (
    user_id,
    tipo,
    xp,
    periodo,
    reference
  )
  values (
    p_user_id,
    'simulado_concluido',
    v_xp_total,
    v_periodo,
    p_simulado_id
  );

  -- Atualizar XP do usuário
  update user_xp
  set
    xp_total = xp_total + v_xp_total,
    xp_periodo = xp_periodo + v_xp_total,
    xp_merito = xp_merito + v_xp_total,
    last_xp_at = now(),
    updated_at = now()
  where user_id = p_user_id;

  return json_build_object(
    'xp_concedido', v_xp_total,
    'motivo', 'concedido'
  );
end;
$$;


ALTER FUNCTION "public"."conceder_xp_simulado"("p_user_id" "uuid", "p_simulado_id" "text", "p_percentual_acerto" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_xp_streak_5_dias"("p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_periodo text;
  v_xp_base integer := 50;
  v_xp_total_hoje integer := 0;
  v_dias_consecutivos integer := 0;
  v_ja_concedido boolean := false;
begin
  v_periodo := to_char(current_date, 'YYYY-MM');

  -- Já concedeu streak recentemente?
  select exists (
    select 1
    from xp_events
    where user_id = p_user_id
      and tipo = 'streak_5_dias'
      and periodo = v_periodo
  )
  into v_ja_concedido;

  if v_ja_concedido then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'streak_ja_concedido_no_periodo'
    );
  end if;

  -- Contar dias consecutivos com atividade (últimos 5 dias)
  select count(distinct created_at::date)
  into v_dias_consecutivos
  from xp_events
  where user_id = p_user_id
    and created_at::date >= current_date - interval '4 days';

  if v_dias_consecutivos < 5 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'streak_incompleto'
    );
  end if;

  -- XP total ganho hoje
  select coalesce(sum(xp), 0)
  into v_xp_total_hoje
  from xp_events
  where user_id = p_user_id
    and created_at::date = current_date;

  if v_xp_total_hoje + v_xp_base > 200 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'limite_diario_geral'
    );
  end if;

  -- Registrar evento
  insert into xp_events (
    user_id,
    tipo,
    xp,
    periodo
  )
  values (
    p_user_id,
    'streak_5_dias',
    v_xp_base,
    v_periodo
  );

  -- Atualizar XP do usuário
  update user_xp
  set
    xp_total = xp_total + v_xp_base,
    xp_periodo = xp_periodo + v_xp_base,
    xp_constancia = xp_constancia + v_xp_base,
    last_xp_at = now(),
    updated_at = now()
  where user_id = p_user_id;

  return json_build_object(
    'xp_concedido', v_xp_base,
    'motivo', 'concedido'
  );
end;
$$;


ALTER FUNCTION "public"."conceder_xp_streak_5_dias"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_xp_uso_diario"("p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_periodo text;
  v_xp_base integer := 10;
  v_xp_total_hoje integer := 0;
  v_ja_concedido boolean := false;
begin
  v_periodo := to_char(current_date, 'YYYY-MM');

  -- Já concedido hoje?
  select exists (
    select 1
    from xp_events
    where user_id = p_user_id
      and tipo = 'uso_diario'
      and created_at::date = current_date
  )
  into v_ja_concedido;

  if v_ja_concedido then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'uso_diario_ja_concedido'
    );
  end if;

  -- XP total ganho hoje
  select coalesce(sum(xp), 0)
  into v_xp_total_hoje
  from xp_events
  where user_id = p_user_id
    and created_at::date = current_date;

  if v_xp_total_hoje + v_xp_base > 200 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'limite_diario_geral'
    );
  end if;

  -- Registrar evento
  insert into xp_events (
    user_id,
    tipo,
    xp,
    periodo
  )
  values (
    p_user_id,
    'uso_diario',
    v_xp_base,
    v_periodo
  );

  -- Atualizar XP do usuário
  update user_xp
  set
    xp_total = xp_total + v_xp_base,
    xp_periodo = xp_periodo + v_xp_base,
    xp_constancia = xp_constancia + v_xp_base,
    last_xp_at = now(),
    updated_at = now()
  where user_id = p_user_id;

  return json_build_object(
    'xp_concedido', v_xp_base,
    'motivo', 'concedido'
  );
end;
$$;


ALTER FUNCTION "public"."conceder_xp_uso_diario"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conceder_xp_whatsapp"("p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_periodo text;
  v_xp_whatsapp_hoje integer := 0;
  v_xp_total_hoje integer := 0;
  v_xp_base integer := 15;
  v_xp_a_conceder integer := 0;
begin
  -- período atual (YYYY-MM)
  v_periodo := to_char(current_date, 'YYYY-MM');

  -- XP WhatsApp ganho hoje
  select coalesce(sum(xp), 0)
  into v_xp_whatsapp_hoje
  from xp_events
  where user_id = p_user_id
    and tipo = 'whatsapp_consolidacao'
    and created_at::date = current_date;

  -- quanto ainda pode ganhar no WhatsApp hoje
  v_xp_a_conceder := greatest(0, 30 - v_xp_whatsapp_hoje);
  v_xp_a_conceder := least(v_xp_base, v_xp_a_conceder);

  if v_xp_a_conceder = 0 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'limite_whatsapp_diario'
    );
  end if;

  -- XP total ganho hoje (todos os eventos)
  select coalesce(sum(xp), 0)
  into v_xp_total_hoje
  from xp_events
  where user_id = p_user_id
    and created_at::date = current_date;

  -- quanto ainda pode ganhar no dia (geral)
  if v_xp_total_hoje + v_xp_a_conceder > 200 then
    v_xp_a_conceder := greatest(0, 200 - v_xp_total_hoje);
  end if;

  if v_xp_a_conceder = 0 then
    return json_build_object(
      'xp_concedido', 0,
      'motivo', 'limite_diario_geral'
    );
  end if;

  -- registrar evento
  insert into xp_events (
    user_id,
    tipo,
    xp,
    periodo
  )
  values (
    p_user_id,
    'whatsapp_consolidacao',
    v_xp_a_conceder,
    v_periodo
  );

  -- atualizar XP do usuário
  update user_xp
  set
    xp_total = xp_total + v_xp_a_conceder,
    xp_periodo = xp_periodo + v_xp_a_conceder,
    xp_merito = xp_merito + v_xp_a_conceder,
    last_xp_at = now(),
    updated_at = now()
  where user_id = p_user_id;

  return json_build_object(
    'xp_concedido', v_xp_a_conceder,
    'motivo', 'concedido'
  );
end;
$$;


ALTER FUNCTION "public"."conceder_xp_whatsapp"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."concluir_missao"("p_recruta_id" "uuid", "p_missao_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_ordem_atual integer;
  v_forca text;
  v_proxima_missao_id uuid;
begin
  -- 1. Marcar missão atual como concluída
  update progresso_missoes
  set concluida = true,
      concluida_em = now()
  where recruta_id = p_recruta_id
    and missao_id = p_missao_id;

  -- 2. Descobrir ordem e força da missão atual
  select ordem, forca
  into v_ordem_atual, v_forca
  from missoes
  where id = p_missao_id;

  -- 3. Encontrar próxima missão
  select id
  into v_proxima_missao_id
  from missoes
  where forca = v_forca
    and tipo = 'aula'
    and ordem > v_ordem_atual
  order by ordem
  limit 1;

  -- 4. Criar progresso da próxima missão (se existir)
  if v_proxima_missao_id is not null then
    insert into progresso_missoes (recruta_id, missao_id, concluida)
    select p_recruta_id, v_proxima_missao_id, false
    where not exists (
      select 1
      from progresso_missoes
      where recruta_id = p_recruta_id
        and missao_id = v_proxima_missao_id
    );
  end if;
end;
$$;


ALTER FUNCTION "public"."concluir_missao"("p_recruta_id" "uuid", "p_missao_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."concluir_missao_inicial"("p_recruta_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_missao_id uuid;
begin
  -- Buscar missão inicial
  select id into v_missao_id
  from public.missoes
  where codigo = 'MISSAO_INICIAL'
  limit 1;

  if v_missao_id is null then
    return;
  end if;

  -- Marcar missão como concluída
  update public.progresso_missoes
  set concluida = true,
      concluida_em = now()
  where recruta_id = p_recruta_id
    and missao_id = v_missao_id;

  -- Conceder XP e marcar onboarding
  update public.recrutas
  set xp = xp + 50,
      onboarding_concluido = true
  where id = p_recruta_id;
end;
$$;


ALTER FUNCTION "public"."concluir_missao_inicial"("p_recruta_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."concluir_missao_inicial"("p_recruta_id" "uuid") IS 'LEGACY BLOCKED. Bypasses C5 by updating XP/onboarding directly. Do not expose to frontend. Replace with canonical C5/onboarding RPC.';



CREATE OR REPLACE FUNCTION "public"."concluir_revisao"("p_revisao_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  update revisoes
  set status = 'concluida',
      concluida_em = now()
  where id = p_revisao_id;
end;
$$;


ALTER FUNCTION "public"."concluir_revisao"("p_revisao_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."concluir_revisao_com_xp"("p_revisao_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_recruta_id uuid;
  v_forca text;
  v_xp integer;
  v_xp_hoje integer;
begin
  -- Buscar dados da revisão
  select r.recruta_id, m.forca, r.xp_recompensa
  into v_recruta_id, v_forca, v_xp
  from revisoes r
  join missoes m on m.id = r.missao_id
  where r.id = p_revisao_id
    and r.status = 'pendente';

  -- Se não existir ou já concluída, sai
  if v_recruta_id is null then
    return;
  end if;

  -- XP já ganho hoje com revisão
  select coalesce(sum(quantidade), 0)
  into v_xp_hoje
  from xp_eventos
  where recruta_id = v_recruta_id
    and origem = 'revisao'
    and created_at::date = now()::date;

  -- Limite diário: 5 XP
  if v_xp_hoje < 5 then
    insert into xp_eventos (
      recruta_id,
      forca,
      quantidade,
      origem
    )
    values (
      v_recruta_id,
      v_forca,
      least(v_xp, 5 - v_xp_hoje),
      'revisao'
    );
  end if;

  -- Marcar revisão como concluída
  update revisoes
  set status = 'concluida',
      concluida_em = now()
  where id = p_revisao_id;
end;
$$;


ALTER FUNCTION "public"."concluir_revisao_com_xp"("p_revisao_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consumir_evento_c5"("p_evento_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_recruta_id uuid;

  v_evento_recruta_id uuid;
  v_processado boolean;

  v_ja_consumido boolean;
BEGIN
  -- 0) auth obrigatório
  v_auth_id := auth.uid();
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'C5_AUTH_REQUIRED: sessão não autenticada'
      USING ERRCODE = '42501';
  END IF;

  -- 1) resolve recruta_id pelo auth_id
  SELECT r.id
    INTO v_recruta_id
  FROM public.recrutas r
  WHERE r.auth_id = v_auth_id;

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'C5_RECRUTA_NOT_FOUND: auth sem recruta vinculado'
      USING ERRCODE = '42501';
  END IF;

  -- 2) valida evento existe + pertence ao recruta + processado=false
  SELECT e.recruta_id, e.processado
    INTO v_evento_recruta_id, v_processado
  FROM public.eventos_institucionais e
  WHERE e.id = p_evento_id;

  IF v_evento_recruta_id IS NULL THEN
    RAISE EXCEPTION 'C5_EVENT_NOT_FOUND: evento inexistente'
      USING ERRCODE = '22023';
  END IF;

  IF v_evento_recruta_id IS DISTINCT FROM v_recruta_id THEN
    RAISE EXCEPTION 'C5_EVENT_FORBIDDEN: evento não pertence ao recruta'
      USING ERRCODE = '42501';
  END IF;

  IF v_processado IS TRUE THEN
    -- contrato: não consumir evento já processado
    RAISE EXCEPTION 'C5_EVENT_ALREADY_PROCESSED: evento já processado'
      USING ERRCODE = '22023';
  END IF;

  -- 3) já consumido?
  SELECT EXISTS (
    SELECT 1
    FROM public.eventos_consumidos c
    WHERE c.evento_id = p_evento_id
      AND c.recruta_id = v_recruta_id
  )
  INTO v_ja_consumido;

  IF v_ja_consumido THEN
    RETURN false;
  END IF;

  -- 4) insere consumo (idempotente, sem depender de grants do cliente)
  INSERT INTO public.eventos_consumidos (id, evento_id, recruta_id, consumido_em)
  VALUES (gen_random_uuid(), p_evento_id, v_recruta_id, now());

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."consumir_evento_c5"("p_evento_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."debug_concessao_run"("p_run_id" "uuid") RETURNS TABLE("medalha_slug" "text", "elegivel" boolean, "ja_concedida" boolean, "concedida_agora" boolean, "motivo_bloqueio" "text", "faltantes" "text"[], "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    l.medalha_slug,
    l.elegivel,
    l.ja_concedida,
    l.concedida_agora,
    l.motivo_bloqueio,
    l.faltantes,
    l.created_at
  from public.medalhas_concessao_log l
  where l.run_id = p_run_id
  order by l.medalha_slug;
$$;


ALTER FUNCTION "public"."debug_concessao_run"("p_run_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."debug_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") RETURNS TABLE("medalha_slug" "text", "metrica" "text", "valor_atual" numeric, "operador" "text", "valor_esperado" numeric, "passou" boolean, "fonte" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    r.medalha_slug,
    (d->>'metrica')::text as metrica,
    nullif(d->>'valor_atual','')::numeric as valor_atual,
    (d->>'operador')::text as operador,
    nullif(d->>'valor_esperado','')::numeric as valor_esperado,
    case when (d ? 'passou') then (d->>'passou')::boolean else null::boolean end as passou,
    (d->>'fonte')::text as fonte
  from public.verificar_regras_medalha(p_recruta_id, p_medalha_slug) r,
       lateral jsonb_array_elements(r.detalhes) d;
$$;


ALTER FUNCTION "public"."debug_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."debug_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") IS 'C7: debug de avaliação de medalha (expande detalhes). STABLE, sem side effects.';



CREATE OR REPLACE FUNCTION "public"."definir_campeoes_mes"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  f text;
  candidato record;
  mes_ref date := date_trunc('month', now())::date;
begin
  -- Loop por Força
  for f in
    select unnest(array['marinha', 'exercito', 'aeronautica'])
  loop
    -- Buscar primeiro elegível (que nunca foi premiado)
    select
      r.recruta_id,
      r.forca,
      r.xp_mes
    into candidato
    from public.vw_ranking_mensal r
    where r.forca = f
      and not exists (
        select 1
        from public.campeoes_mensais c
        where c.recruta_id = r.recruta_id
          and c.premiado = true
      )
    order by r.posicao
    limit 1;

    -- Se encontrou alguém, registra
    if found then
      insert into public.campeoes_mensais (
        recruta_id,
        forca,
        mes_referencia,
        xp_total,
        premiado
      )
      values (
        candidato.recruta_id,
        candidato.forca,
        mes_ref,
        candidato.xp_mes,
        true
      );
    end if;
  end loop;
end;
$$;


ALTER FUNCTION "public"."definir_campeoes_mes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("evento_id" "uuid", "status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare
  v_referencia_id uuid;
  v_hash text;
begin
  if p_recruta_id is null then
    raise exception 'p_recruta_id é obrigatório';
  end if;

  if p_tipo_evento is null or btrim(p_tipo_evento) = '' then
    raise exception 'p_tipo_evento é obrigatório';
  end if;

  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'p_idempotency_key é obrigatório';
  end if;

  if p_correlation_id is null or btrim(p_correlation_id) = '' then
    raise exception 'p_correlation_id é obrigatório';
  end if;

  if p_origem is null or p_origem not in ('n8n','chat_central','sistema') then
    raise exception 'p_origem inválido (n8n|chat_central|sistema)';
  end if;

  if p_tipo_evento = 'auth' then
    if p_correlation_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_referencia_id := p_correlation_id::uuid;
    else
      v_hash := md5(p_idempotency_key);
      v_referencia_id := (
        substr(v_hash, 1, 8) || '-' ||
        substr(v_hash, 9, 4) || '-' ||
        substr(v_hash, 13, 4) || '-' ||
        substr(v_hash, 17, 4) || '-' ||
        substr(v_hash, 21, 12)
      )::uuid;
    end if;
  else
    v_referencia_id := p_recruta_id;
  end if;

  perform set_config('c5.gateway', '1', true);

  return query
  with upsert as (
    insert into public.eventos_institucionais (
      recruta_id,
      tipo,
      referencia_id,
      titulo,
      descricao,
      tipo_evento,
      idempotency_key,
      correlation_id,
      origem,
      payload,
      status
    )
    values (
      p_recruta_id,
      case
        when p_tipo_evento = 'auth' then 'auth'
        else 'medalha'
      end,
      v_referencia_id,
      p_tipo_evento,
      coalesce(nullif(btrim(coalesce(p_payload->>'descricao', '')), ''), p_tipo_evento),
      p_tipo_evento,
      p_idempotency_key,
      p_correlation_id,
      p_origem,
      coalesce(p_payload, '{}'::jsonb),
      'received'
    )
    on conflict (idempotency_key) where (idempotency_key is not null)
    do update
      set status = 'duplicate'
    returning public.eventos_institucionais.id as id,
              (xmax = 0) as inserted
  )
  select
    upsert.id as evento_id,
    case
      when upsert.inserted then 'inserted'
      else 'duplicate'
    end as status
  from upsert;
end;
$_$;


ALTER FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") IS 'CANONICAL C5 EVENT RPC. SECURITY DEFINER. Frontend may execute only this idempotent institutional event signature.';



CREATE OR REPLACE FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo" "text", "p_referencia_id" "uuid", "p_titulo" "text", "p_descricao" "text", "p_prioridade" integer, "p_cycle_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_evento_id uuid;
begin
  if p_tipo not in ('medalha','patente','auth') then
    raise exception 'C5_CONTRATO_INVALIDO: tipo=% (permitidos: medalha|patente|auth)', p_tipo
      using errcode = '22023';
  end if;

  if p_recruta_id is null or p_referencia_id is null then
    raise exception 'C5_CONTRATO_INVALIDO: recruta_id/referencia_id não podem ser NULL'
      using errcode = '22023';
  end if;

  if p_titulo is null or length(trim(p_titulo)) = 0 then
    raise exception 'C5_CONTRATO_INVALIDO: titulo obrigatório'
      using errcode = '22023';
  end if;

  if p_descricao is null or length(trim(p_descricao)) = 0 then
    raise exception 'C5_CONTRATO_INVALIDO: descricao obrigatória'
      using errcode = '22023';
  end if;

  if p_prioridade is null then
    raise exception 'C5_CONTRATO_INVALIDO: prioridade obrigatória'
      using errcode = '22023';
  end if;

  perform set_config('c5.gateway', '1', true);

  v_evento_id := gen_random_uuid();

  insert into public.eventos_institucionais (
    id,
    recruta_id,
    tipo,
    referencia_id,
    titulo,
    descricao,
    prioridade,
    cycle_id,
    emitido_em,
    processado
  ) values (
    v_evento_id,
    p_recruta_id,
    p_tipo,
    p_referencia_id,
    p_titulo,
    p_descricao,
    p_prioridade,
    p_cycle_id,
    now(),
    false
  );

  return v_evento_id;
end;
$$;


ALTER FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo" "text", "p_referencia_id" "uuid", "p_titulo" "text", "p_descricao" "text", "p_prioridade" integer, "p_cycle_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo" "text", "p_referencia_id" "uuid", "p_titulo" "text", "p_descricao" "text", "p_prioridade" integer, "p_cycle_id" "uuid") IS 'LEGACY C5 OVERLOAD. Frontend execution forbidden. Use modern idempotent signature only.';



CREATE OR REPLACE FUNCTION "public"."emitir_evento_promocao"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_evento_id uuid;
  v_evento_status text;
BEGIN
  SELECT e.evento_id, e.status
  INTO v_evento_id, v_evento_status
  FROM public.emitir_evento_c5(
    NEW.recruta_id,
    'patente_promovida',
    'patente_promovida:' || NEW.recruta_id::text || ':' || NEW.id::text,
    NEW.id::text,
    'sistema',
    jsonb_build_object(
      'patente_evento_id', NEW.id,
      'titulo', 'Promoção de Patente',
      'descricao', COALESCE(NEW.motivo, 'Promoção registrada conforme regulamento institucional'),
      'origem', 'emitir_evento_promocao'
    )
  ) e
  LIMIT 1;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."emitir_evento_promocao"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."executar_auditoria_c7"() RETURNS TABLE("status_geral" "text", "inconsistencias_encontradas" integer, "resumo" "jsonb")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_inconsistencias bigint;
  v_resumo jsonb;
BEGIN
  SELECT COALESCE(sum(ir.quantidade), 0) INTO v_inconsistencias
  FROM public.v_c7_integridade_relacional ir;

  v_resumo := jsonb_build_object(
    'data_quality_resumo',
      (SELECT to_jsonb(dq) FROM public.v_c7_data_quality_resumo dq),
    'integridade_relacional',
      COALESCE(
        (SELECT jsonb_agg(to_jsonb(ir) ORDER BY ir.tipo_inconsistencia) FROM public.v_c7_integridade_relacional ir),
        '[]'::jsonb
      )
  );

  status_geral := CASE WHEN v_inconsistencias = 0 THEN 'SAUDAVEL' ELSE 'ATENCAO' END;
  inconsistencias_encontradas := v_inconsistencias::int;
  resumo := v_resumo;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION "public"."executar_auditoria_c7"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."executar_snapshot_catalogo_completo"() RETURNS TABLE("total_processadas" integer, "total_versionadas" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_medalha record;
    v_processadas integer := 0;
    v_versionadas integer := 0;
begin

    for v_medalha in
        select id
        from public.medalhas_catalogo mc
        where mc.active is true
          and not exists (
                select 1
                from public.medalhas_catalogo_versionamento mv
                where mv.medalha_id = mc.id
          )
    loop
        v_processadas := v_processadas + 1;

        perform public.snapshot_medalha(v_medalha.id);

        v_versionadas := v_versionadas + 1;
    end loop;

    total_processadas := v_processadas;
    total_versionadas := v_versionadas;

    return next;
end;
$$;


ALTER FUNCTION "public"."executar_snapshot_catalogo_completo"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fechar_ranking_mensal"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  periodo record;
  vencedor record;
begin
  -- 1. Buscar período mensal ativo
  select *
  into periodo
  from ranking_periodos
  where status = 'ativo'
    and tipo = 'mensal'
  limit 1;

  if periodo is null then
    raise exception 'Nenhum período mensal ativo encontrado';
  end if;

  -- 2. Gerar snapshot do ranking
  insert into ranking_resultados (
    periodo_id,
    user_id,
    posicao,
    xp_periodo,
    xp_merito
  )
  select
    periodo.id,
    ux.user_id,
    row_number() over (
      order by
        ux.xp_periodo desc,
        ux.xp_merito desc,
        ux.last_xp_at asc
    ) as posicao,
    ux.xp_periodo,
    ux.xp_merito
  from user_xp ux
  where ux.xp_periodo > 0;

  -- 3. Selecionar vencedor elegível (que nunca ganhou prêmio)
  select rr.*
  into vencedor
  from ranking_resultados rr
  where rr.periodo_id = periodo.id
    and not exists (
      select 1
      from premiacoes p
      where p.user_id = rr.user_id
    )
  order by rr.posicao
  limit 1;

  -- 4. Registrar premiação
  if vencedor is not null then
    insert into premiacoes (
      user_id,
      periodo_id,
      tipo,
      descricao
    )
    values (
      vencedor.user_id,
      periodo.id,
      'fisico',
      'Recruta Padrão do Mês'
    );

    update ranking_resultados
    set foi_premiado = true
    where periodo_id = periodo.id
      and user_id = vencedor.user_id;
  end if;

  -- 5. Encerrar período atual
  update ranking_periodos
  set status = 'encerrado'
  where id = periodo.id;

  -- 6. Resetar XP do período
  update user_xp
  set
    xp_periodo = 0,
    xp_merito = 0,
    xp_constancia = 0,
    updated_at = now();

  -- 7. Criar novo período mensal
  insert into ranking_periodos (
    tipo,
    inicio,
    fim,
    status
  )
  values (
    'mensal',
    (date_trunc('month', current_date) + interval '1 month')::date,
    (date_trunc('month', current_date) + interval '2 month - 1 day')::date,
    'ativo'
  );

end;
$$;


ALTER FUNCTION "public"."fechar_ranking_mensal"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fechar_ranking_mensal"() IS 'INTERNAL RCC/C7 RANKING FUNCTION. SECURITY DEFINER with search_path=public. Frontend execution forbidden.';



CREATE OR REPLACE FUNCTION "public"."fn_acquire_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text", "p_ttl_seconds" integer, "p_owner" "text" DEFAULT 'chat_central'::"text") RETURNS TABLE("acquired" boolean, "recruta_id" "uuid", "locked_at" timestamp with time zone, "expires_at" timestamp with time zone, "correlation_id" "text", "owner" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_now timestamptz := now();
  v_row public.conversation_locks%rowtype;
  v_expires timestamptz;
begin
  if p_ttl_seconds is null or p_ttl_seconds <= 0 then
    raise exception 'ttl_seconds inválido (>0)';
  end if;
  if p_owner not in ('n8n','chat_central') then
    raise exception 'owner inválido (n8n|chat_central)';
  end if;

  v_expires := v_now + make_interval(secs => p_ttl_seconds);

  select * into v_row
  from public.conversation_locks
  where conversation_locks.recruta_id = p_recruta_id
  for update;

  if not found then
    insert into public.conversation_locks (recruta_id, locked_at, expires_at, correlation_id, owner)
    values (p_recruta_id, v_now, v_expires, p_correlation_id, p_owner);

    return query select true, p_recruta_id, v_now, v_expires, p_correlation_id, p_owner;
    return;
  end if;

  if v_row.expires_at < v_now then
    update public.conversation_locks
      set locked_at = v_now,
          expires_at = v_expires,
          correlation_id = p_correlation_id,
          owner = p_owner
    where conversation_locks.recruta_id = p_recruta_id;

    return query select true, p_recruta_id, v_now, v_expires, p_correlation_id, p_owner;
    return;
  end if;

  return query
  select false, v_row.recruta_id, v_row.locked_at, v_row.expires_at, v_row.correlation_id, v_row.owner;
end;
$$;


ALTER FUNCTION "public"."fn_acquire_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text", "p_ttl_seconds" integer, "p_owner" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_billing_trial_dias"() RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  select 7
$$;


ALTER FUNCTION "public"."fn_billing_trial_dias"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_calcular_custo_modelo_tokens"("p_modelo" "text", "p_tokens_input" integer, "p_tokens_output" integer, "p_at" timestamp with time zone DEFAULT "now"()) RETURNS TABLE("modelo" "text", "versao" integer, "preco_input_token" numeric, "preco_output_token" numeric, "tokens_input" integer, "tokens_output" integer, "custo_total" numeric)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_preco record;
  v_in int := coalesce(p_tokens_input, 0);
  v_out int := coalesce(p_tokens_output, 0);
begin
  if p_modelo is null or btrim(p_modelo) = '' then
    raise exception 'p_modelo é obrigatório';
  end if;

  if v_in < 0 or v_out < 0 then
    raise exception 'tokens não podem ser negativos';
  end if;

  select mpv.modelo, mpv.versao, mpv.preco_input_token, mpv.preco_output_token
    into v_preco
  from public.modelos_precificacao_versionada mpv
  where mpv.modelo = p_modelo
    and mpv.effective_from <= coalesce(p_at, now())
  order by mpv.effective_from desc, mpv.versao desc
  limit 1;

  if v_preco.modelo is null then
    raise exception 'Preço não cadastrado para modelo=%', p_modelo;
  end if;

  return query
  select
    v_preco.modelo,
    v_preco.versao,
    v_preco.preco_input_token,
    v_preco.preco_output_token,
    v_in,
    v_out,
    (v_in::numeric * v_preco.preco_input_token) + (v_out::numeric * v_preco.preco_output_token) as custo_total;
end;
$$;


ALTER FUNCTION "public"."fn_calcular_custo_modelo_tokens"("p_modelo" "text", "p_tokens_input" integer, "p_tokens_output" integer, "p_at" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fn_calcular_custo_modelo_tokens"("p_modelo" "text", "p_tokens_input" integer, "p_tokens_output" integer, "p_at" timestamp with time zone) IS 'Calcula custo total usando precificação vigente (read-only).';



CREATE OR REPLACE FUNCTION "public"."fn_conceder_xp_aula"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_xp integer;
begin
  -- Busca o XP da aula
  select xp_valor
  into v_xp
  from aulas
  where id = new.aula_id;

  -- Se aula não tiver XP definido, não faz nada
  if v_xp is null or v_xp <= 0 then
    return new;
  end if;

  -- Soma XP ao perfil do recruta
  update profiles
  set xp = xp + v_xp
  where id = new.user_id;

  return new;
end;
$$;


ALTER FUNCTION "public"."fn_conceder_xp_aula"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_os_set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."fn_os_set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_registrar_evento"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("evento_id" "uuid", "status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  return query
  select * from public.emitir_evento_c5(
    p_recruta_id, p_tipo_evento, p_idempotency_key, p_correlation_id, p_origem, p_payload
  );
end;
$$;


ALTER FUNCTION "public"."fn_registrar_evento"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_registrar_preco_modelo"("p_modelo" "text", "p_preco_input_token" numeric, "p_preco_output_token" numeric, "p_criado_por" "text", "p_effective_from" timestamp with time zone DEFAULT "now"()) RETURNS TABLE("modelo" "text", "versao" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_next integer;
begin
  if p_modelo is null or btrim(p_modelo) = '' then
    raise exception 'p_modelo é obrigatório';
  end if;

  if p_criado_por is null or btrim(p_criado_por) = '' then
    raise exception 'p_criado_por é obrigatório';
  end if;

  if p_preco_input_token is null or p_preco_input_token < 0 then
    raise exception 'p_preco_input_token inválido';
  end if;

  if p_preco_output_token is null or p_preco_output_token < 0 then
    raise exception 'p_preco_output_token inválido';
  end if;

  select coalesce(max(mpv.versao), 0) + 1
    into v_next
  from public.modelos_precificacao_versionada mpv
  where mpv.modelo = p_modelo;

  insert into public.modelos_precificacao_versionada (
    modelo, versao, effective_from, preco_input_token, preco_output_token, criado_por
  )
  values (
    p_modelo, v_next, coalesce(p_effective_from, now()), p_preco_input_token, p_preco_output_token, p_criado_por
  );

  return query
  select p_modelo, v_next;
end;
$$;


ALTER FUNCTION "public"."fn_registrar_preco_modelo"("p_modelo" "text", "p_preco_input_token" numeric, "p_preco_output_token" numeric, "p_criado_por" "text", "p_effective_from" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fn_registrar_preco_modelo"("p_modelo" "text", "p_preco_input_token" numeric, "p_preco_output_token" numeric, "p_criado_por" "text", "p_effective_from" timestamp with time zone) IS 'Registra uma nova versão de preço/token para um modelo (auditável).';



CREATE OR REPLACE FUNCTION "public"."fn_release_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text") RETURNS TABLE("released" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_deleted int;
begin
  delete from public.conversation_locks
  where recruta_id = p_recruta_id
    and correlation_id = p_correlation_id;

  get diagnostics v_deleted = row_count;

  return query select (v_deleted > 0);
end;
$$;


ALTER FUNCTION "public"."fn_release_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_semana_base_calendario"("p_ciclo_id" "uuid", "p_data_inicio_individual" "date") RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  /*
    Retorna a semana_num do cronograma onde p_data_inicio_individual cai.
    Se cair antes do início do ciclo, retorna 1.
    Se cair depois e não encontrar faixa, retorna a última semana_num conhecida.
  */
  with ciclo as (
    select cf.data_inicio as ciclo_inicio
    from public.ciclos_formativos cf
    where cf.id = p_ciclo_id
  ),
  hit as (
    select cr.semana_num
    from public.cronograma_semanal cr
    where cr.ciclo_id = p_ciclo_id
      and p_data_inicio_individual between cr.data_inicio and cr.data_fim
    order by cr.semana_num
    limit 1
  ),
  lastw as (
    select cr.semana_num
    from public.cronograma_semanal cr
    where cr.ciclo_id = p_ciclo_id
    order by cr.semana_num desc
    limit 1
  )
  select
    case
      when (select ciclo_inicio from ciclo) is not null
           and p_data_inicio_individual < (select ciclo_inicio from ciclo) then 1
      when (select semana_num from hit) is not null then (select semana_num from hit)
      else coalesce((select semana_num from lastw), 1)
    end::int
$$;


ALTER FUNCTION "public"."fn_semana_base_calendario"("p_ciclo_id" "uuid", "p_data_inicio_individual" "date") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fn_semana_base_calendario"("p_ciclo_id" "uuid", "p_data_inicio_individual" "date") IS 'C6.2: Determina semana_base no cronograma (semana_num) correspondente ao início individual.';



CREATE OR REPLACE FUNCTION "public"."fn_semana_relativa"("p_data_inicio_individual" "date", "p_ref_date" "date" DEFAULT CURRENT_DATE) RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  select greatest(
    1,
    ((p_ref_date - p_data_inicio_individual) / 7) + 1
  )::int
$$;


ALTER FUNCTION "public"."fn_semana_relativa"("p_data_inicio_individual" "date", "p_ref_date" "date") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fn_semana_relativa"("p_data_inicio_individual" "date", "p_ref_date" "date") IS 'C6.2: Semana relativa (1..N) a partir de data_inicio_individual e data de referência.';



CREATE OR REPLACE FUNCTION "public"."fn_touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."fn_touch_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."garantir_recruta_ciclo_status_me"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth uuid;
  v_recruta_id uuid;
  v_forca text;
  v_ciclo_id uuid;

  v_exists boolean;
  v_rcs_id uuid;
BEGIN
  v_auth := auth.uid();
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'C6: auth.uid() obrigatório';
  END IF;

  -- recruta do usuário
  SELECT r.id, r.forca
    INTO v_recruta_id, v_forca
  FROM public.recrutas r
  WHERE r.auth_id = v_auth
  LIMIT 1;

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'C6: recruta não encontrado para auth.uid()';
  END IF;

  -- ciclo vigente da força do recruta (mesma lógica da v_recruta_ciclo_atual)
  SELECT cf.id
    INTO v_ciclo_id
  FROM public.ciclos_formativos cf
  WHERE cf.forca = v_forca
    AND cf.vigente = true
  LIMIT 1;

  IF v_ciclo_id IS NULL THEN
    RAISE EXCEPTION 'C6: ciclo vigente não encontrado para força %', v_forca;
  END IF;

  -- já existe status?
  SELECT TRUE
    INTO v_exists
  FROM public.recruta_ciclo_status s
  WHERE s.recruta_id = v_recruta_id
    AND s.ciclo_id = v_ciclo_id
  LIMIT 1;

  IF COALESCE(v_exists, FALSE) THEN
    -- retorna estado atual (sem escrever)
    SELECT s.id
      INTO v_rcs_id
    FROM public.recruta_ciclo_status s
    WHERE s.recruta_id = v_recruta_id
      AND s.ciclo_id = v_ciclo_id
    LIMIT 1;

    RETURN jsonb_build_object(
      'created', false,
      'recruta_id', v_recruta_id,
      'ciclo_id', v_ciclo_id,
      'recruta_ciclo_status_id', v_rcs_id
    );
  END IF;

  -- cria linha neutra institucional (sem mérito)
  INSERT INTO public.recruta_ciclo_status (
    recruta_id,
    ciclo_id,
    semana_atual,
    semanas_em_atraso_consec,
    regularidade_status,
    comprometeu_em,
    criado_em,
    atualizado_em,
    semanas_perfeitas_consec,
    semanas_validas,
    dias_validos,
    ultima_semana_num
  )
  VALUES (
    v_recruta_id,
    v_ciclo_id,
    1,                  -- inicia na semana 1 institucional
    0,
    'regular',          -- estado inicial neutro (não concede mérito; apenas estado base)
    NULL,
    now(),
    now(),
    0,
    0,
    0,
    0
  )
  RETURNING id INTO v_rcs_id;

  RETURN jsonb_build_object(
    'created', true,
    'recruta_id', v_recruta_id,
    'ciclo_id', v_ciclo_id,
    'recruta_ciclo_status_id', v_rcs_id
  );
END;
$$;


ALTER FUNCTION "public"."garantir_recruta_ciclo_status_me"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gerar_revisao_whatsapp"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  insert into revisoes (
    recruta_id,
    missao_id,
    tipo,
    status,
    origem,
    xp_recompensa
  )
  select
    pm.recruta_id,
    pm.missao_id,
    'whatsapp',
    'pendente',
    'whatsapp',
    1
  from progresso_missoes pm
  where pm.concluida = true
    and not exists (
      select 1
      from revisoes r
      where r.recruta_id = pm.recruta_id
        and r.tipo = 'whatsapp'
        and r.status = 'pendente'
    );
end;
$$;


ALTER FUNCTION "public"."gerar_revisao_whatsapp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gerar_revisoes_espacadas"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  -- Revisão 3 dias
  insert into revisoes (
    recruta_id,
    missao_id,
    tipo,
    status,
    origem,
    xp_recompensa
  )
  select
    pm.recruta_id,
    pm.missao_id,
    'espacada',
    'pendente',
    'app',
    5
  from progresso_missoes pm
  where pm.concluida = true
    and pm.concluida_em <= now() - interval '3 days'
    and not exists (
      select 1
      from revisoes r
      where r.recruta_id = pm.recruta_id
        and r.missao_id = pm.missao_id
        and r.tipo = 'espacada'
        and r.criada_em <= now() - interval '3 days'
    );

  -- Revisão 7 dias
  insert into revisoes (
    recruta_id,
    missao_id,
    tipo,
    status,
    origem,
    xp_recompensa
  )
  select
    pm.recruta_id,
    pm.missao_id,
    'espacada',
    'pendente',
    'app',
    5
  from progresso_missoes pm
  where pm.concluida = true
    and pm.concluida_em <= now() - interval '7 days'
    and not exists (
      select 1
      from revisoes r
      where r.recruta_id = pm.recruta_id
        and r.missao_id = pm.missao_id
        and r.tipo = 'espacada'
        and r.criada_em <= now() - interval '7 days'
    );
end;
$$;


ALTER FUNCTION "public"."gerar_revisoes_espacadas"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."lesson_media" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "url" "text" NOT NULL,
    "available_after_hours" integer,
    "order" integer DEFAULT 1 NOT NULL,
    "force" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "lesson_media_available_after_hours_check" CHECK ((("available_after_hours" IS NULL) OR ("available_after_hours" >= 0))),
    CONSTRAINT "lesson_media_order_check" CHECK (("order" >= 1)),
    CONSTRAINT "lesson_media_type_check" CHECK (("type" = ANY (ARRAY['video'::"text", 'pdf'::"text", 'review_video'::"text", 'review_audio'::"text"])))
);


ALTER TABLE "public"."lesson_media" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lesson_progress" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "completed_at" timestamp with time zone,
    "review_completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."lesson_progress" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_lesson_review_availability" AS
 SELECT "lp"."user_id",
    "lp"."lesson_id",
    "min"("lm"."available_after_hours") AS "available_after_hours",
    "lp"."completed_at",
    (("lp"."completed_at" IS NOT NULL) AND ("now"() >= ("lp"."completed_at" + ('01:00:00'::interval * ("min"("lm"."available_after_hours"))::double precision)))) AS "review_available"
   FROM ("public"."lesson_progress" "lp"
     JOIN "public"."lesson_media" "lm" ON (("lm"."lesson_id" = "lp"."lesson_id")))
  WHERE ("lm"."type" = ANY (ARRAY['review_video'::"text", 'review_audio'::"text"]))
  GROUP BY "lp"."user_id", "lp"."lesson_id", "lp"."completed_at";


ALTER VIEW "public"."v_lesson_review_availability" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_lesson_review_availability"() RETURNS SETOF "public"."v_lesson_review_availability"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  select * from public.v_lesson_review_availability;
$$;


ALTER FUNCTION "public"."get_lesson_review_availability"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.profiles (
    id,
    email,
    tipo_acesso,
    ativo
  )
  values (
    new.id,
    new.email,
    'degustacao',
    true
  );

  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."liberar_modulos_iniciais"("p_recruta_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_forca text;
begin
  -- Descobrir a força do recruta
  select forca
  into v_forca
  from recrutas
  where id = p_recruta_id;

  -- Liberar os 2 primeiros módulos da força do recruta
  insert into recruta_modulos (recruta_id, modulo_id, liberado_em)
  select
    p_recruta_id,
    m.id,
    now()
  from modulos m
  left join recruta_modulos rm
    on rm.recruta_id = p_recruta_id
   and rm.modulo_id = m.id
  where
    m.forca = v_forca
    and m.ordem in (
      select ordem
      from modulos
      where forca = v_forca
      order by ordem
      limit 2
    )
    and rm.id is null;
end;
$$;


ALTER FUNCTION "public"."liberar_modulos_iniciais"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."liberar_todos_modulos_apos_7_dias"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  insert into recruta_modulos (recruta_id, modulo_id, liberado_em)
  select
    r.id as recruta_id,
    m.id as modulo_id,
    now() as liberado_em
  from recrutas r
  cross join modulos m
  left join recruta_modulos rm
    on rm.recruta_id = r.id
   and rm.modulo_id = m.id
  where
    r.created_at <= now() - interval '7 days'
    and rm.id is null;
end;
$$;


ALTER FUNCTION "public"."liberar_todos_modulos_apos_7_dias"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."module_progress"("p_recruta_id" "uuid", "p_modulo_id" "uuid") RETURNS TABLE("completed" integer, "total" integer)
    LANGUAGE "sql" STABLE
    AS $$
  select
    count(*) filter (where rl.completed_at is not null) as completed,
    count(*) as total
  from licoes l
  left join recruta_licoes rl
    on rl.licao_id = l.id
   and rl.recruta_id = p_recruta_id
  where l.modulo_id = p_modulo_id;
$$;


ALTER FUNCTION "public"."module_progress"("p_recruta_id" "uuid", "p_modulo_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."os_tasks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "task_key" "text" NOT NULL,
    "task_type" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "priority" integer DEFAULT 100 NOT NULL,
    "source" "text" DEFAULT 'manual'::"text" NOT NULL,
    "agent_type" "text",
    "goal" "text" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "result" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "error_message" "text",
    "dedupe_key" "text",
    "correlation_id" "uuid" DEFAULT "gen_random_uuid"(),
    "attempts" integer DEFAULT 0 NOT NULL,
    "max_attempts" integer DEFAULT 3 NOT NULL,
    "locked_by" "text",
    "locked_at" timestamp with time zone,
    "retry_after" timestamp with time zone,
    "started_at" timestamp with time zone,
    "finished_at" timestamp with time zone,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "os_tasks_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'running'::"text", 'completed'::"text", 'failed'::"text", 'cancelled'::"text", 'skipped'::"text"])))
);


ALTER TABLE "public"."os_tasks" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."os_fetch_next_task"() RETURNS SETOF "public"."os_tasks"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_task public.os_tasks;
begin
  select *
  into v_task
  from public.os_tasks
  where status = 'pending'
    and (locked_at is null or locked_at < now() - interval '5 minutes')
  order by priority asc, created_at asc
  limit 1
  for update skip locked;

  if not found then
    return;
  end if;

  update public.os_tasks
  set
    status = 'running',
    locked_by = 'worker',
    locked_at = now(),
    started_at = now()
  where id = v_task.id
  returning * into v_task;

  return next v_task;
end;
$$;


ALTER FUNCTION "public"."os_fetch_next_task"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pode_progredir"("p_recruta" "uuid") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  patente_atual text;
BEGIN
  SELECT patente
  INTO patente_atual
  FROM recruta_status
  WHERE recruta_id = p_recruta;

  IF patente_atual = 'LENDA_VIVA' THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."pode_progredir"("p_recruta" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."processar_concessao_medalhas"("p_recruta_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_slug text;
  v_medalha_id uuid;
  v_result record;
  v_ja_concedida boolean;
  v_concedidas integer := 0;
begin
  -- percorre medalhas ativas do catálogo
  for v_slug, v_medalha_id in
    select mc.slug, mc.id
    from public.medalhas_catalogo mc
    where mc.active is true
    order by mc.slug
  loop
    -- avalia via engine (read-only)
    select *
      into v_result
    from public.verificar_regras_medalha(p_recruta_id, v_slug)
    limit 1;

    -- idempotência: já concedida?
    select exists (
      select 1
      from public.medalhas_concedidas mcon
      where mcon.recruta_id = p_recruta_id
        and mcon.medalha_id = v_medalha_id
      limit 1
    )
    into v_ja_concedida;

    -- concede SOMENTE se:
    -- - elegivel = true
    -- - faltantes vazio (bloqueia SEM_DADO e FONTE_NAO_MAPEADA)
    -- - não estiver já concedida
    if coalesce(v_result.elegivel, false) is true
       and coalesce(array_length(v_result.faltantes, 1), 0) = 0
       and v_ja_concedida is false
    then
      insert into public.medalhas_concedidas (
        id,
        recruta_id,
        medalha_id,
        concedida_em
      )
      values (
        gen_random_uuid(),
        p_recruta_id,
        v_medalha_id,
        now()
      );

      v_concedidas := v_concedidas + 1;
    end if;
  end loop;

  return v_concedidas;
end;
$$;


ALTER FUNCTION "public"."processar_concessao_medalhas"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."processar_concessao_medalhas_com_log"("p_recruta_id" "uuid") RETURNS TABLE("run_id" "uuid", "medalhas_avaliadas" integer, "medalhas_concedidas" integer, "bloqueadas" integer, "ja_possuidas" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_run_id uuid := gen_random_uuid();
  v_slug text;
  v_medalha_id uuid;

  v_result record;

  v_ja_concedida boolean;
  v_concedida_agora boolean;
  v_motivo text;

  v_has_fonte_nao_mapeada boolean;
  v_has_sem_dado boolean;

  v_avaliadas int := 0;
  v_concedidas int := 0;
  v_bloqueadas int := 0;
  v_ja int := 0;
begin
  for v_slug, v_medalha_id in
    select mc.slug, mc.id
    from public.medalhas_catalogo mc
    where mc.active is true
    order by mc.slug
  loop
    v_avaliadas := v_avaliadas + 1;

    select *
      into v_result
    from public.verificar_regras_medalha(p_recruta_id, v_slug)
    limit 1;

    select exists (
      select 1
      from public.medalhas_concedidas mcon
      where mcon.recruta_id = p_recruta_id
        and mcon.medalha_id = v_medalha_id
      limit 1
    )
    into v_ja_concedida;

    if v_ja_concedida then
      v_ja := v_ja + 1;
    end if;

    select exists (
      select 1
      from unnest(coalesce(v_result.faltantes, array[]::text[])) f
      where f like 'FONTE_NAO_MAPEADA:%'
    ) into v_has_fonte_nao_mapeada;

    select exists (
      select 1
      from unnest(coalesce(v_result.faltantes, array[]::text[])) f
      where f like 'SEM_DADO:%'
    ) into v_has_sem_dado;

    v_concedida_agora :=
      (coalesce(v_result.elegivel, false) is true)
      and (coalesce(array_length(v_result.faltantes, 1), 0) = 0)
      and (v_ja_concedida is false);

    v_motivo := null;

    if v_ja_concedida is true then
      v_motivo := 'JA_CONCEDIDA';
    elsif v_has_fonte_nao_mapeada is true then
      v_motivo := 'FONTE_NAO_MAPEADA';
    elsif v_has_sem_dado is true then
      v_motivo := 'SEM_DADO';
    elsif coalesce(v_result.elegivel, false) is not true then
      v_motivo := 'NAO_ELEGIVEL';
    end if;

    if v_concedida_agora is true then
      insert into public.medalhas_concedidas (
        id,
        recruta_id,
        medalha_id,
        granted_at
      )
      values (
        gen_random_uuid(),
        p_recruta_id,
        v_medalha_id,
        now()
      );

      v_concedidas := v_concedidas + 1;
    else
      v_bloqueadas := v_bloqueadas + 1;
    end if;

    insert into public.medalhas_concessao_log (
      run_id,
      run_at,
      recruta_id,
      medalha_id,
      medalha_slug,
      elegivel,
      ja_concedida,
      concedida_agora,
      motivo_bloqueio,
      faltantes,
      detalhes,
      created_at
    )
    values (
      v_run_id,
      now(),
      p_recruta_id,
      v_medalha_id,
      v_slug,
      coalesce(v_result.elegivel, false),
      v_ja_concedida,
      v_concedida_agora,
      v_motivo,
      coalesce(v_result.faltantes, array[]::text[]),
      coalesce(v_result.detalhes, '[]'::jsonb),
      now()
    )
    on conflict on constraint medalhas_concessao_log_run_recruta_medalha_uniq
    do nothing;

  end loop;

  run_id := v_run_id;
  medalhas_avaliadas := v_avaliadas;
  medalhas_concedidas := v_concedidas;
  bloqueadas := v_bloqueadas;
  ja_possuidas := v_ja;

  return next;
end;
$$;


ALTER FUNCTION "public"."processar_concessao_medalhas_com_log"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."processar_concessao_medalhas_debug"("p_recruta_id" "uuid") RETURNS TABLE("medalha_slug" "text", "elegivel" boolean, "ja_concedida" boolean, "concedida_agora" boolean, "motivo_bloqueio" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_slug text;
  v_medalha_id uuid;
  v_result record;
  v_ja_concedida boolean;
  v_bloqueio text;
begin
  for v_slug, v_medalha_id in
    select mc.slug, mc.id
    from public.medalhas_catalogo mc
    where mc.active is true
    order by mc.slug
  loop
    select *
      into v_result
    from public.verificar_regras_medalha(p_recruta_id, v_slug)
    limit 1;

    select exists (
      select 1
      from public.medalhas_concedidas mcon
      where mcon.recruta_id = p_recruta_id
        and mcon.medalha_id = v_medalha_id
      limit 1
    )
    into v_ja_concedida;

    v_bloqueio := null;

    if v_ja_concedida is true then
      v_bloqueio := 'JA_CONCEDIDA';
    elsif coalesce(v_result.elegivel, false) is not true then
      v_bloqueio := 'NAO_ELEGIVEL';
    elsif coalesce(array_length(v_result.faltantes, 1), 0) <> 0 then
      -- cobre SEM_DADO:* e FONTE_NAO_MAPEADA:* (e qualquer outra falha)
      v_bloqueio := 'FALTANTES_PRESENTES';
    end if;

    medalha_slug := v_slug;
    elegivel := coalesce(v_result.elegivel, false);
    ja_concedida := v_ja_concedida;
    concedida_agora := false; -- debug não altera dados
    motivo_bloqueio := v_bloqueio;

    return next;
  end loop;

  return;
end;
$$;


ALTER FUNCTION "public"."processar_concessao_medalhas_debug"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."processar_concessao_medalhas_diario"() RETURNS TABLE("execution_started_at" timestamp with time zone, "execution_finished_at" timestamp with time zone, "recrutas_processados" integer, "medalhas_avaliadas" integer, "medalhas_concedidas" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_started_at timestamptz := now();
  v_finished_at timestamptz;
  v_lock_ok boolean;
  v_recruta_id uuid;

  v_recrutas int := 0;
  v_medalhas_av int := 0;
  v_medalhas_conc int := 0;

  v_run record; -- retorno de processar_concessao_medalhas_com_log
  v_has_audit_table boolean;
begin
  -- lock global (anti-concorrência)
  select pg_try_advisory_lock(987654321) into v_lock_ok;
  if v_lock_ok is not true then
    raise notice 'C7.6 já está em execução';
    execution_started_at := v_started_at;
    execution_finished_at := now();
    recrutas_processados := 0;
    medalhas_avaliadas := 0;
    medalhas_concedidas := 0;
    return next;
    return;
  end if;

  begin
    -- detecta se tabela de auditoria global existe (sem depender de inventar nada)
    select exists (
      select 1
      from information_schema.tables
      where table_schema='public' and table_name='c7_execucao_diaria_log'
    ) into v_has_audit_table;

    -- ⚠️ critério de “ativos” NÃO aplicado aqui porque não temos schema confirmado de recrutas.
    -- banco-first seguro: processa todos os recrutas.
    for v_recruta_id in
      select r.id
      from public.recrutas r
      order by r.id
    loop
      v_recrutas := v_recrutas + 1;

      -- chamada canônica: concede + gera logs por run (C7.5)
      select
        t.run_id,
        t.medalhas_avaliadas,
        t.medalhas_concedidas,
        t.bloqueadas,
        t.ja_possuidas
      into v_run
      from public.processar_concessao_medalhas_com_log(v_recruta_id) t;

      v_medalhas_av := v_medalhas_av + coalesce(v_run.medalhas_avaliadas, 0);
      v_medalhas_conc := v_medalhas_conc + coalesce(v_run.medalhas_concedidas, 0);
    end loop;

    v_finished_at := now();

    -- auditoria global (1 linha por execução) — somente se a tabela existir
    if v_has_audit_table is true then
      insert into public.c7_execucao_diaria_log (
        started_at,
        finished_at,
        recrutas_processados,
        medalhas_avaliadas,
        medalhas_concedidas
      ) values (
        v_started_at,
        v_finished_at,
        v_recrutas,
        v_medalhas_av,
        v_medalhas_conc
      );
    end if;

    execution_started_at := v_started_at;
    execution_finished_at := v_finished_at;
    recrutas_processados := v_recrutas;
    medalhas_avaliadas := v_medalhas_av;
    medalhas_concedidas := v_medalhas_conc;
    return next;

  exception
    when others then
      -- garante unlock mesmo em erro
      perform pg_advisory_unlock(987654321);
      raise;
  end;

  -- unlock no final
  perform pg_advisory_unlock(987654321);
end;
$$;


ALTER FUNCTION "public"."processar_concessao_medalhas_diario"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."promover_recruta"("p_recruta_id" "uuid", "p_patente_codigo" "text", "p_motivo" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_auth_id uuid;
    v_nova_patente_id uuid;
    v_novo_nivel integer;
    v_nivel_atual integer;
    v_xp_total integer := 0;
    r_regra RECORD;
BEGIN

    -- 🔐 Validação robusta de identidade (anti-NULL escape)
    SELECT auth_id
    INTO v_auth_id
    FROM public.recrutas
    WHERE id = p_recruta_id;

    IF v_auth_id IS NULL
       OR auth.uid() IS NULL
       OR v_auth_id IS DISTINCT FROM auth.uid()
    THEN
        RETURN false;
    END IF;

    -- 1️⃣ Patente alvo válida?
    SELECT id, nivel
    INTO v_nova_patente_id, v_novo_nivel
    FROM public.patentes_catalogo
    WHERE codigo = p_patente_codigo
      AND ativo = true;

    IF v_nova_patente_id IS NULL THEN
        RETURN false;
    END IF;

    -- 2️⃣ Nível atual
    SELECT COALESCE(MAX(p.nivel), 0)
    INTO v_nivel_atual
    FROM public.recruta_patentes rp
    JOIN public.patentes_catalogo p
      ON p.id = rp.patente_id
    WHERE rp.recruta_id = p_recruta_id;

    -- 3️⃣ Só permite subir 1 nível por vez
    IF v_novo_nivel <> v_nivel_atual + 1 THEN
        RETURN false;
    END IF;

    -- 4️⃣ XP TOTAL
    SELECT COALESCE(SUM(quantidade), 0)
    INTO v_xp_total
    FROM public.xp_eventos
    WHERE recruta_id = p_recruta_id;

    -- 5️⃣ Avalia regras
    FOR r_regra IN
        SELECT *
        FROM public.patente_regras
        WHERE patente_id = v_nova_patente_id
          AND active = true
    LOOP
        IF r_regra.metrica = 'xp_total' THEN
            IF v_xp_total < r_regra.valor THEN
                RETURN false;
            END IF;
        END IF;
    END LOOP;

    -- 6️⃣ Registra promoção
    INSERT INTO public.recruta_patentes (
        recruta_id,
        patente_id,
        motivo
    )
    VALUES (
        p_recruta_id,
        v_nova_patente_id,
        p_motivo
    );

    RETURN true;
END;
$$;


ALTER FUNCTION "public"."promover_recruta"("p_recruta_id" "uuid", "p_patente_codigo" "text", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."propor_alteracao_medalha"("p_medalha_id" "uuid", "p_proposta_catalogo" "jsonb", "p_proposta_regras" "jsonb", "p_criado_por" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_exists boolean;
    v_id uuid;
begin

    select exists(
        select 1 from public.medalhas_catalogo where id = p_medalha_id
    ) into v_exists;

    if not v_exists then
        raise exception 'Medalha % não encontrada.', p_medalha_id;
    end if;

    insert into public.medalhas_alteracoes_pendentes (
        medalha_id,
        proposta_catalogo,
        proposta_regras,
        criado_por
    )
    values (
        p_medalha_id,
        p_proposta_catalogo,
        p_proposta_regras,
        p_criado_por
    )
    returning id into v_id;

    return v_id;
end;
$$;


ALTER FUNCTION "public"."propor_alteracao_medalha"("p_medalha_id" "uuid", "p_proposta_catalogo" "jsonb", "p_proposta_regras" "jsonb", "p_criado_por" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalcular_iea"("p_recruta_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth uuid := auth.uid();
  v_is_service boolean := public._is_service_role();
  v_is_sql_admin boolean := (current_user IN ('postgres', 'supabase_admin'));

  v_ciclo_id uuid;         -- pode ser NULL fora de ciclo (FK permite)
  v_ciclo_chave uuid;      -- NUNCA NULL (sem FK)
  v_reg_status text;

  v_score_regularidade int;
  v_score_desempenho int;

  v_iea int;
  v_conceito text;
  v_componentes jsonb;

  v_prev_iea int;
  v_snapshot_id uuid;

  v_marcos int[] := ARRAY[70,80,90,95];
  v_m int;

  v_ciclo_fora uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid;
BEGIN
  -- Acesso: service_role OU SQL admin OU (auth.uid + ownership)
  IF NOT v_is_service AND NOT v_is_sql_admin THEN
    IF v_auth IS NULL THEN
      RAISE EXCEPTION 'C7: auth.uid() obrigatório.';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.recrutas r
      WHERE r.id = p_recruta_id
        AND r.auth_id = v_auth
    ) THEN
      RAISE EXCEPTION 'C7: recruta_id não pertence ao usuário autenticado.';
    END IF;
  END IF;

  -- ciclo vigente (NULL antes de 02/03/2026)
  SELECT vrca.ciclo_id
    INTO v_ciclo_id
  FROM public.v_recruta_ciclo_atual vrca
  WHERE vrca.recruta_id = p_recruta_id
  LIMIT 1;

  -- ciclo_chave determinístico (sem FK)
  v_ciclo_chave := COALESCE(v_ciclo_id, v_ciclo_fora);

  -- regularidade
  SELECT vrsr.regularidade_status
    INTO v_reg_status
  FROM public.v_regularidade_status_recruta vrsr
  WHERE vrsr.recruta_id = p_recruta_id
  LIMIT 1;

  IF v_reg_status IS NULL THEN
    v_reg_status := 'nao_disponivel';
  END IF;

  v_score_regularidade :=
    CASE v_reg_status
      WHEN 'regular'       THEN 60
      WHEN 'recuperacao'   THEN 55
      WHEN 'atencao'       THEN 45
      WHEN 'comprometida'  THEN 25
      ELSE 50
    END;

  v_score_desempenho := 40;

  v_iea := LEAST(100, GREATEST(0, v_score_regularidade + v_score_desempenho));

  v_conceito :=
    CASE
      WHEN v_iea >= 95 THEN 'Excelência Máxima'
      WHEN v_iea >= 90 THEN 'Excelência'
      WHEN v_iea >= 80 THEN 'Alta Performance'
      WHEN v_iea >= 70 THEN 'Bom'
      ELSE 'Regular'
    END;

  v_componentes := jsonb_build_object(
    'ciclo_id', v_ciclo_id,
    'ciclo_chave', v_ciclo_chave,
    'regularidade', jsonb_build_object(
      'status', v_reg_status,
      'score', v_score_regularidade,
      'fonte', 'v_regularidade_status_recruta'
    ),
    'desempenho', jsonb_build_object(
      'score', v_score_desempenho,
      'fonte', 'placeholder_neutro',
      'observacao', 'avaliacoes/quiz/simulado ainda nao disponiveis ou nao integrados ao C7'
    ),
    'modelo', jsonb_build_object(
      'versao', 'C7_v1_2',
      'nota', 'Formula completa nao exposta no app; audit via v_iea_audit'
    )
  );

  -- snapshot anterior no mesmo "contexto": ciclo real quando existe, senão NULL (fora de ciclo)
  SELECT s.iea_score
    INTO v_prev_iea
  FROM public.iea_snapshots s
  WHERE s.recruta_id = p_recruta_id
    AND (s.ciclo_id IS NOT DISTINCT FROM v_ciclo_id)
  ORDER BY s.calculado_em DESC
  LIMIT 1;

  -- inserir snapshot (ciclo_id pode ser NULL; FK ok)
  INSERT INTO public.iea_snapshots (recruta_id, ciclo_id, iea_score, conceito, componentes)
  VALUES (p_recruta_id, v_ciclo_id, v_iea, v_conceito, v_componentes)
  RETURNING id INTO v_snapshot_id;

  -- marcos 1x por ciclo_chave
  FOREACH v_m IN ARRAY v_marcos LOOP
    IF (v_iea >= v_m) AND (COALESCE(v_prev_iea, 0) < v_m) THEN
      BEGIN
        INSERT INTO public.iea_marcos_emitidos (recruta_id, ciclo_id, ciclo_chave, marco, snapshot_id)
        VALUES (p_recruta_id, v_ciclo_id, v_ciclo_chave, v_m, v_snapshot_id);

        PERFORM public._emitir_evento_c5_iea_marco(p_recruta_id, v_ciclo_id, v_snapshot_id, v_m, v_iea);

      EXCEPTION WHEN unique_violation THEN
        NULL;
      END;
    END IF;
  END LOOP;

END;
$$;


ALTER FUNCTION "public"."recalcular_iea"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalcular_regularidade"("p_recruta_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_forca text;
  v_ciclo_id uuid;
BEGIN
  -- recruta existe?
  SELECT r.forca INTO v_forca
  FROM public.recrutas r
  WHERE r.id = p_recruta_id;

  IF v_forca IS NULL THEN
    RAISE EXCEPTION 'C6_RECRUTA_NOT_FOUND';
  END IF;

  -- ciclo vigente (se não existir, sai sem erro)
  SELECT c.id INTO v_ciclo_id
  FROM public.ciclos_formativos c
  WHERE c.forca = v_forca
    AND current_date BETWEEN c.data_inicio AND c.data_fim
  ORDER BY c.data_inicio DESC
  LIMIT 1;

  IF v_ciclo_id IS NULL THEN
    RETURN;
  END IF;

  -- Aqui fica sua lógica de regularidade (semanas_em_atraso_consec etc.)
  -- Se você já tem a lógica implementada em outra versão, cole o miolo aqui
  -- mantendo a assinatura acima.
  RETURN;
END;
$$;


ALTER FUNCTION "public"."recalcular_regularidade"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recruta_progresso_geral"("p_recruta_id" "uuid") RETURNS TABLE("completed" bigint, "total" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_completed bigint;
  v_total bigint;
begin
  -- Total de aulas ativas no sistema
  select count(*) into v_total
  from aulas
  where ativa = true;

  -- Total de aulas concluídas pelo recruta
  select count(*) into v_completed
  from progresso_aulas
  where user_id = p_recruta_id
  and concluida = true;

  -- Retorno dos dados
  return query
  select 
    coalesce(v_completed, 0),
    case when coalesce(v_total, 0) = 0 then 1 else v_total end; -- Evita divisão por zero no front
end;
$$;


ALTER FUNCTION "public"."recruta_progresso_geral"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_c7_materialized_views"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin

  -- Ordem estratégica
  refresh materialized view concurrently public.mv_c7_metricas_problema_resumo;

  refresh materialized view concurrently public.mv_c7_bloqueio_por_medalha;

  refresh materialized view concurrently public.mv_c7_status_recruta_atual;

end;
$$;


ALTER FUNCTION "public"."refresh_c7_materialized_views"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registrar_atividade_academica"("p_recruta_id" "uuid", "p_tipo" "text", "p_ref_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_forca text;
  v_ciclo_id uuid;
BEGIN
  -- Hardening mínimo: tipo obrigatório
  IF p_tipo IS NULL OR length(trim(p_tipo)) = 0 THEN
    RAISE EXCEPTION 'C6_INVALID_TIPO';
  END IF;

  -- Resolve força do recruta
  SELECT r.forca
    INTO v_forca
  FROM public.recrutas r
  WHERE r.id = p_recruta_id;

  IF v_forca IS NULL THEN
    RAISE EXCEPTION 'C6_RECRUTA_NOT_FOUND';
  END IF;

  -- Ciclo vigente (se não existir, deixa NULL e registra mesmo: modo independente não quebra)
  SELECT c.id
    INTO v_ciclo_id
  FROM public.ciclos_formativos c
  WHERE c.forca = v_forca
    AND current_date BETWEEN c.data_inicio AND c.data_fim
  ORDER BY c.data_inicio DESC
  LIMIT 1;

  -- Log append-only (coluna correta: registrado_em)
  INSERT INTO public.atividade_academica_log (
    recruta_id,
    ciclo_id,
    tipo,
    ref_id,
    registrado_em
  )
  VALUES (
    p_recruta_id,
    v_ciclo_id,
    p_tipo,
    p_ref_id,
    now()
  );

  RETURN;
END;
$$;


ALTER FUNCTION "public"."registrar_atividade_academica"("p_recruta_id" "uuid", "p_tipo" "text", "p_ref_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolver_slug_medalha"("p_slug" "text") RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select coalesce(a.slug_canonico, p_slug)
  from public.medalhas_slug_aliases a
  where a.slug_alias = p_slug
  limit 1
$$;


ALTER FUNCTION "public"."resolver_slug_medalha"("p_slug" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_auth_claim_active_client_session"("p_client_instance_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_auth_id uuid;
  v_prev_client_instance_id text;
  v_changed boolean;
begin
  v_auth_id := auth.uid();

  if v_auth_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_client_instance_id is null or btrim(p_client_instance_id) = '' then
    raise exception 'INVALID_CLIENT_INSTANCE_ID';
  end if;

  select s.current_client_instance_id
    into v_prev_client_instance_id
  from public.auth_client_singleton as s
  where s.auth_id = v_auth_id;

  if v_prev_client_instance_id is not null
     and v_prev_client_instance_id <> p_client_instance_id then

    insert into public.auth_client_revocations (
      auth_id,
      revoked_client_instance_id,
      revoked_reason,
      new_client_instance_id
    )
    values (
      v_auth_id,
      v_prev_client_instance_id,
      'security_logout',
      p_client_instance_id
    );

    perform public._c5_emit_auth_logout(
      v_auth_id,
      v_prev_client_instance_id,
      'security_logout'
    );
  end if;

  insert into public.auth_client_singleton (
    auth_id,
    current_client_instance_id,
    updated_at
  )
  values (
    v_auth_id,
    p_client_instance_id,
    now()
  )
  on conflict (auth_id)
  do update
     set current_client_instance_id = excluded.current_client_instance_id,
         updated_at = excluded.updated_at;

  v_changed := coalesce(v_prev_client_instance_id is distinct from p_client_instance_id, true);

  return jsonb_build_object(
    'auth_id', v_auth_id,
    'current_client_instance_id', p_client_instance_id,
    'previous_client_instance_id', v_prev_client_instance_id,
    'changed', v_changed
  );
end;
$$;


ALTER FUNCTION "public"."rpc_auth_claim_active_client_session"("p_client_instance_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_auth_claim_active_client_session"("p_client_instance_id" "text") IS 'RCC-0.3: registra client_instance_id ativo da conta, revoga o anterior e retorna payload jsonb sem ambiguidade de nomes.';



CREATE OR REPLACE FUNCTION "public"."rpc_auth_resolve_session_state"("p_client_instance_id" "text") RETURNS TABLE("auth_id" "uuid", "recruta_id" "uuid", "email" "text", "status_conta" "text", "requires_mfa" boolean, "account_locked" boolean, "password_expired" boolean, "inactive_user" boolean, "ultima_atividade" timestamp with time zone, "session_checked_at" timestamp with time zone, "session_revoked_reason" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_auth_id uuid;
  v_current_client_instance_id text;
begin
  v_auth_id := auth.uid();

  if v_auth_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_client_instance_id is null or btrim(p_client_instance_id) = '' then
    raise exception 'INVALID_CLIENT_INSTANCE_ID';
  end if;

  select s.current_client_instance_id
    into v_current_client_instance_id
  from public.auth_client_singleton s
  where s.auth_id = v_auth_id;

  return query
  select
    v_auth_id::uuid as auth_id,
    r.id::uuid as recruta_id,
    r.email::text as email,
    (
      case
        when r.status = 'ativo' then 'active'
        when r.status = 'bloqueado' then 'locked'
        when r.status = 'inativo' then 'inactive'
        else 'active'
      end
    )::text as status_conta,
    false::boolean as requires_mfa,
    false::boolean as account_locked,
    false::boolean as password_expired,
    (
      case
        when r.status = 'inativo' then true
        else false
      end
    )::boolean as inactive_user,
    r.updated_at::timestamptz as ultima_atividade,
    now()::timestamptz as session_checked_at,
    (
      case
        when v_current_client_instance_id is null then 'none'
        when v_current_client_instance_id = p_client_instance_id then 'none'
        else 'security_logout'
      end
    )::text as session_revoked_reason
  from public.recrutas r
  where r.auth_id = v_auth_id;
end;
$$;


ALTER FUNCTION "public"."rpc_auth_resolve_session_state"("p_client_instance_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_auth_resolve_session_state"("p_client_instance_id" "text") IS 'Resolve o estado institucional da sessão por client_instance_id. Corrigido para alinhar exatamente o RETURN QUERY à assinatura.';



CREATE OR REPLACE FUNCTION "public"."rpc_auth_revoke_client_session"("p_client_instance_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_auth_id uuid;
  v_current_client_instance_id text;
  v_tombstone_client_instance_id text;
begin
  v_auth_id := auth.uid();

  if v_auth_id is null then
    raise exception using
      errcode = '28000',
      message = 'AUTH_REQUIRED',
      detail = 'rpc_auth_revoke_client_session exige auth.uid() válido.';
  end if;

  if p_client_instance_id is null or btrim(p_client_instance_id) = '' then
    raise exception using
      errcode = '22023',
      message = 'INVALID_CLIENT_INSTANCE_ID',
      detail = 'p_client_instance_id é obrigatório.';
  end if;

  select s.current_client_instance_id
    into v_current_client_instance_id
  from public.auth_client_singleton s
  where s.auth_id = v_auth_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'ACTIVE_CLIENT_NOT_FOUND',
      detail = 'Nenhum cliente vigente encontrado para o auth.uid() atual.';
  end if;

  if v_current_client_instance_id <> p_client_instance_id then
    raise exception using
      errcode = 'P0002',
      message = 'TARGET_CLIENT_NOT_ACTIVE',
      detail = 'No modelo singleton atual, apenas o cliente vigente do usuário pode ser revogado por esta RPC.';
  end if;

  v_tombstone_client_instance_id :=
    '__revoked__:' || gen_random_uuid()::text;

  insert into public.auth_client_revocations (
    auth_id,
    revoked_client_instance_id,
    revoked_reason,
    new_client_instance_id
  )
  values (
    v_auth_id,
    v_current_client_instance_id,
    'security_logout',
    v_tombstone_client_instance_id
  );

  update public.auth_client_singleton
     set current_client_instance_id = v_tombstone_client_instance_id,
         updated_at = now()
   where auth_id = v_auth_id;

  perform public._c5_emit_auth_logout(
    v_auth_id,
    v_current_client_instance_id,
    'security_logout'
  );

  return jsonb_build_object(
    'ok', true,
    'auth_id', v_auth_id,
    'revoked_client_instance_id', v_current_client_instance_id,
    'replacement_client_instance_id', v_tombstone_client_instance_id,
    'reason', 'security_logout',
    'mode', 'singleton_compatible'
  );
end;
$$;


ALTER FUNCTION "public"."rpc_auth_revoke_client_session"("p_client_instance_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_auth_revoke_client_session"("p_client_instance_id" "text") IS 'RPC sensível do AUTH DOMAIN. Compatível com o modelo singleton do RCC v0.3. Revoga o cliente vigente do auth.uid(), registra revogação append-only e emite auditoria AUTH -> C5. Não representa revogação multi-device plena.';



CREATE OR REPLACE FUNCTION "public"."rpc_billing_corrigir_divergencias"("p_recruta_id" "uuid" DEFAULT NULL::"uuid", "p_gateway_event_id" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_afetadas integer := 0;
  v_reconciliadas integer := 0;
begin
  insert into public.billing_reconciliation_issues (
    executado_em,
    gateway_event_id,
    recruta_id,
    assinatura_id,
    pagamento_id,
    tipo_divergencia,
    detalhes,
    status_execucao
  )
  select
    now(),
    bp.gateway_event_id,
    bp.recruta_id,
    bp.assinatura_id,
    bp.id,
    'PAGAMENTO_SEM_ASSINATURA_VALIDADA',
    jsonb_build_object(
      'gateway_nome', bp.gateway_nome,
      'status_pagamento', bp.status_pagamento
    ),
    'pendente'
  from public.billing_pagamentos bp
  left join public.billing_assinaturas ba
    on ba.id = bp.assinatura_id
  where ba.id is null
    and (p_recruta_id is null or bp.recruta_id = p_recruta_id)
    and (p_gateway_event_id is null or bp.gateway_event_id = p_gateway_event_id);

  get diagnostics v_afetadas = row_count;

  perform public.rpc_billing_reconciliar_pagamentos(p_recruta_id);

  update public.billing_reconciliation_issues bri
     set status_execucao = 'sucesso',
         detalhes = coalesce(bri.detalhes, '{}'::jsonb) || jsonb_build_object('corrigido_em', now())
   where bri.status_execucao = 'pendente'
     and (p_recruta_id is null or bri.recruta_id = p_recruta_id)
     and (p_gateway_event_id is null or bri.gateway_event_id = p_gateway_event_id);

  get diagnostics v_reconciliadas = row_count;

  return jsonb_build_object(
    'ok', true,
    'issues_registradas', v_afetadas,
    'issues_reconciliadas', v_reconciliadas
  );
end;
$$;


ALTER FUNCTION "public"."rpc_billing_corrigir_divergencias"("p_recruta_id" "uuid", "p_gateway_event_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_billing_processar_evento_pagamento"("p_recruta_id" "uuid", "p_gateway_event_id" "text", "p_gateway_nome" "text" DEFAULT 'n8n'::"text", "p_gateway_pagamento_id" "text" DEFAULT NULL::"text", "p_valor_centavos" bigint DEFAULT 0, "p_moeda" "text" DEFAULT 'BRL'::"text", "p_status_pagamento" "text" DEFAULT 'confirmado'::"text", "p_plano" "text" DEFAULT 'basico'::"text", "p_periodo_inicio" timestamp with time zone DEFAULT "now"(), "p_periodo_fim" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_payload" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_pagamento_id uuid;
  v_assinatura_id uuid;
  v_assinatura_id_fk uuid;
  v_status_assinatura text;
  v_c5_emitido boolean := false;
begin
  if p_recruta_id is null then
    return jsonb_build_object('ok', false, 'erro', 'RECRUTA_ID_OBRIGATORIO');
  end if;

  if coalesce(btrim(p_gateway_event_id), '') = '' then
    return jsonb_build_object('ok', false, 'erro', 'GATEWAY_EVENT_ID_OBRIGATORIO');
  end if;

  if not exists (
    select 1
    from public.recrutas r
    where r.id = p_recruta_id
  ) then
    return jsonb_build_object('ok', false, 'erro', 'RECRUTA_NAO_ENCONTRADO');
  end if;

  select bp.id, bp.assinatura_id
    into v_pagamento_id, v_assinatura_id
  from public.billing_pagamentos bp
  where bp.gateway_nome = p_gateway_nome
    and bp.gateway_event_id = p_gateway_event_id
  limit 1;

  if v_pagamento_id is not null then
    insert into public.billing_reconciliacao (
      gateway_nome,
      gateway_event_id,
      recruta_id,
      assinatura_id,
      pagamento_id,
      acao,
      status_execucao,
      detalhes,
      observacao
    )
    values (
      p_gateway_nome,
      p_gateway_event_id,
      p_recruta_id,
      v_assinatura_id,
      v_pagamento_id,
      'processar_evento_pagamento',
      'ignorado',
      jsonb_build_object('motivo', 'EVENTO_DUPLICADO'),
      'IDEMPOTENCIA_APLICADA'
    );

    return jsonb_build_object(
      'ok', true,
      'idempotente', true,
      'pagamento_id', v_pagamento_id,
      'assinatura_id', v_assinatura_id
    );
  end if;

  v_status_assinatura :=
    case
      when p_status_pagamento in ('confirmado', 'recebido') then 'ativa'
      when p_status_pagamento = 'pendente' then 'pendente'
      when p_status_pagamento = 'falhou' then 'inadimplente'
      when p_status_pagamento in ('cancelado', 'estornado') then 'cancelada'
      else 'pendente'
    end;

  insert into public.billing_assinaturas (
    recruta_id,
    gateway_assinatura_id,
    plano,
    status_assinatura,
    vigente_inicio,
    vigente_fim,
    ultimo_gateway_event_id,
    metadata
  )
  values (
    p_recruta_id,
    p_gateway_pagamento_id,
    p_plano,
    v_status_assinatura,
    case when v_status_assinatura = 'ativa' then coalesce(p_periodo_inicio, now()) else null end,
    case when v_status_assinatura = 'ativa' then p_periodo_fim else null end,
    p_gateway_event_id,
    coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (recruta_id) do update
     set gateway_assinatura_id = excluded.gateway_assinatura_id,
         plano = excluded.plano,
         status_assinatura = excluded.status_assinatura,
         vigente_inicio = excluded.vigente_inicio,
         vigente_fim = excluded.vigente_fim,
         ultimo_gateway_event_id = excluded.ultimo_gateway_event_id,
         metadata = excluded.metadata
  returning id into v_assinatura_id;

  insert into public.billing_pagamentos (
    recruta_id,
    assinatura_id,
    gateway_nome,
    gateway_event_id,
    gateway_pagamento_id,
    status_pagamento,
    valor_centavos,
    moeda,
    plano_referenciado,
    competencia_inicio,
    competencia_fim,
    payload
  )
  values (
    p_recruta_id,
    v_assinatura_id,
    p_gateway_nome,
    p_gateway_event_id,
    p_gateway_pagamento_id,
    p_status_pagamento,
    p_valor_centavos,
    p_moeda,
    p_plano,
    p_periodo_inicio,
    p_periodo_fim,
    coalesce(p_payload, '{}'::jsonb)
  )
  returning id into v_pagamento_id;

  perform public.rpc_billing_reconciliar_pagamentos(p_recruta_id);

  update public.recrutas
     set data_pagamento = case
                            when p_status_pagamento in ('confirmado', 'recebido') then now()
                            else data_pagamento
                          end
   where id = p_recruta_id;

  v_c5_emitido := public.billing_emitir_evento_c5(
    'billing.pagamento_processado',
    jsonb_build_object(
      'recruta_id', p_recruta_id,
      'gateway_nome', p_gateway_nome,
      'gateway_event_id', p_gateway_event_id,
      'pagamento_id', v_pagamento_id,
      'assinatura_id', v_assinatura_id,
      'status_pagamento', p_status_pagamento,
      'plano', p_plano,
      'valor_centavos', p_valor_centavos,
      'moeda', p_moeda
    )
  );

  insert into public.billing_reconciliacao (
    gateway_nome,
    gateway_event_id,
    recruta_id,
    assinatura_id,
    pagamento_id,
    acao,
    status_execucao,
    detalhes,
    observacao
  )
  values (
    p_gateway_nome,
    p_gateway_event_id,
    p_recruta_id,
    v_assinatura_id,
    v_pagamento_id,
    'processar_evento_pagamento',
    'sucesso',
    jsonb_build_object(
      'status_assinatura', v_status_assinatura,
      'evento_c5_emitido', v_c5_emitido
    ),
    'EVENTO_PROCESSADO'
  );

  return jsonb_build_object(
    'ok', true,
    'idempotente', false,
    'pagamento_id', v_pagamento_id,
    'assinatura_id', v_assinatura_id,
    'evento_c5_emitido', v_c5_emitido
  );
exception
  when others then
    if v_assinatura_id is not null
       and exists (
         select 1
         from public.billing_assinaturas ba
         where ba.id = v_assinatura_id
       )
    then
      v_assinatura_id_fk := v_assinatura_id;
    else
      v_assinatura_id_fk := null;
    end if;

    insert into public.billing_reconciliacao (
      gateway_nome,
      gateway_event_id,
      recruta_id,
      assinatura_id,
      pagamento_id,
      acao,
      status_execucao,
      detalhes,
      observacao
    )
    values (
      coalesce(p_gateway_nome, 'n8n'),
      p_gateway_event_id,
      p_recruta_id,
      v_assinatura_id_fk,
      v_pagamento_id,
      'processar_evento_pagamento',
      'erro',
      jsonb_build_object(
        'sqlstate', sqlstate,
        'sqlerrm', sqlerrm,
        'assinatura_id_original', v_assinatura_id
      ),
      'ERRO_PROCESSAMENTO_EVENTO'
    );

    return jsonb_build_object(
      'ok', false,
      'erro', sqlerrm,
      'sqlstate', sqlstate
    );
end;
$$;


ALTER FUNCTION "public"."rpc_billing_processar_evento_pagamento"("p_recruta_id" "uuid", "p_gateway_event_id" "text", "p_gateway_nome" "text", "p_gateway_pagamento_id" "text", "p_valor_centavos" bigint, "p_moeda" "text", "p_status_pagamento" "text", "p_plano" "text", "p_periodo_inicio" timestamp with time zone, "p_periodo_fim" timestamp with time zone, "p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_billing_reconciliar_pagamentos"("p_recruta_id" "uuid" DEFAULT NULL::"uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_count integer := 0;
begin
  update public.recrutas r
     set plano = src.plano_atual,
         validade = src.validade,
         status = case
                    when src.acesso_liberado then 'ativo'
                    else r.status
                  end,
         updated_at = now()
    from (
      select
        r2.id as recruta_id,
        coalesce(ba.plano, r2.plano, 'basico') as plano_atual,
        case
          when ba.status_assinatura = 'trial' then
            coalesce(ba.trial_fim, r2.created_at + make_interval(days => public.fn_billing_trial_dias()))
          when ba.status_assinatura = 'ativa' then
            coalesce(ba.vigente_fim, r2.validade)
          when ba.status_assinatura is null
               and r2.created_at + make_interval(days => public.fn_billing_trial_dias()) >= now() then
            r2.created_at + make_interval(days => public.fn_billing_trial_dias())
          else
            coalesce(ba.vigente_fim, r2.validade)
        end as validade,
        case
          when ba.status_assinatura = 'ativa'
               and coalesce(ba.vigente_fim, r2.validade, now()) >= now() then true
          when ba.status_assinatura = 'trial'
               and coalesce(ba.trial_fim, r2.created_at + make_interval(days => public.fn_billing_trial_dias())) >= now() then true
          when ba.status_assinatura is null
               and r2.created_at + make_interval(days => public.fn_billing_trial_dias()) >= now() then true
          when r2.validade is not null and r2.validade >= now() then true
          else false
        end as acesso_liberado
      from public.recrutas r2
      left join public.billing_assinaturas ba
        on ba.recruta_id = r2.id
      where p_recruta_id is null or r2.id = p_recruta_id
    ) src
   where r.id = src.recruta_id;

  get diagnostics v_count = row_count;

  insert into public.billing_reconciliacao (
    gateway_nome,
    gateway_event_id,
    recruta_id,
    acao,
    status_execucao,
    detalhes,
    observacao
  )
  values (
    'interno',
    null,
    p_recruta_id,
    'reconciliar_pagamentos',
    'sucesso',
    jsonb_build_object(
      'recruta_id', p_recruta_id,
      'linhas_atualizadas', v_count
    ),
    'RECONCILIACAO_APLICADA'
  );

  return v_count;
end;
$$;


ALTER FUNCTION "public"."rpc_billing_reconciliar_pagamentos"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_billing_status_recruta"("p_recruta_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("recruta_id" "uuid", "auth_id" "uuid", "plano_atual" "text", "status_assinatura" "text", "validade" timestamp with time zone, "trial_restante" integer, "acesso_liberado" boolean, "origem_status" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    v.recruta_id,
    v.auth_id,
    v.plano_atual,
    v.status_assinatura,
    v.validade,
    v.trial_restante,
    v.acesso_liberado,
    v.origem_status
  from public.v_billing_status_recruta v
  where p_recruta_id is null
     or v.recruta_id = p_recruta_id
$$;


ALTER FUNCTION "public"."rpc_billing_status_recruta"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_billing_verificar_idempotencia"("p_gateway_nome" "text", "p_gateway_event_id" "text") RETURNS TABLE("existe" boolean, "pagamento_id" "uuid", "recruta_id" "uuid", "assinatura_id" "uuid", "status_pagamento" "text", "processado_em" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with alvo as (
    select
      bp.id as pagamento_id,
      bp.recruta_id,
      bp.assinatura_id,
      bp.status_pagamento,
      bp.processado_em
    from public.billing_pagamentos bp
    where bp.gateway_nome = p_gateway_nome
      and bp.gateway_event_id = p_gateway_event_id
    limit 1
  )
  select
    exists(select 1 from alvo) as existe,
    a.pagamento_id,
    a.recruta_id,
    a.assinatura_id,
    a.status_pagamento,
    a.processado_em
  from alvo a
  union all
  select
    false as existe,
    null::uuid,
    null::uuid,
    null::uuid,
    null::text,
    null::timestamptz
  where not exists (select 1 from alvo);
$$;


ALTER FUNCTION "public"."rpc_billing_verificar_idempotencia"("p_gateway_nome" "text", "p_gateway_event_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_billing_verificar_trial_expirando"("p_dias" integer DEFAULT 3) RETURNS TABLE("recruta_id" "uuid", "plano_atual" "text", "validade" timestamp with time zone, "trial_restante" integer, "acesso_liberado" boolean, "origem_status" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    r.id as recruta_id,
    coalesce(ba.plano, r.plano, 'basico') as plano_atual,
    coalesce(
      ba.trial_fim,
      r.created_at + make_interval(days => public.fn_billing_trial_dias())
    ) as validade,
    greatest(
      0,
      ceil(extract(epoch from (
        coalesce(ba.trial_fim, r.created_at + make_interval(days => public.fn_billing_trial_dias())) - now()
      )) / 86400.0)
    )::integer as trial_restante,
    true as acesso_liberado,
    case
      when ba.status_assinatura = 'trial' then 'trial_assinatura'
      else 'trial_implicito'
    end as origem_status
  from public.recrutas r
  left join public.billing_assinaturas ba
    on ba.recruta_id = r.id
  where (
      (ba.status_assinatura = 'trial'
        and coalesce(ba.trial_fim, r.created_at + make_interval(days => public.fn_billing_trial_dias())) >= now())
      or
      (ba.id is null
        and r.created_at + make_interval(days => public.fn_billing_trial_dias()) >= now())
    )
    and greatest(
      0,
      ceil(extract(epoch from (
        coalesce(ba.trial_fim, r.created_at + make_interval(days => public.fn_billing_trial_dias())) - now()
      )) / 86400.0)
    )::integer <= p_dias;
$$;


ALTER FUNCTION "public"."rpc_billing_verificar_trial_expirando"("p_dias" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_c5_atualizar_fatos_analytics"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_executado_em timestamptz := now();
  v_linhas_processadas bigint := 0;
begin
  with base as (
    select
      v.id_evento,
      v.id_recruta,
      v.timestamp_evento,
      v.timestamp_evento::date as dia,
      v.dominio_analitico,
      v.evento_analitico,
      v.origem,
      md5(v.id_recruta::text || '|' || v.timestamp_evento::date::text)::uuid as sessao_logica,
      row_number() over (
        partition by v.id_recruta, v.timestamp_evento::date
        order by v.timestamp_evento, v.id_evento
      )::integer as sequencia_ordem
    from public.v_c5_eventos_dominios_v3 v
  ),
  inserted as (
    insert into public.c5_fatos_analytics (
      id_evento,
      id_recruta,
      timestamp_evento,
      dia,
      dominio_analitico,
      evento_analitico,
      origem,
      sessao_logica,
      sequencia_ordem
    )
    select
      b.id_evento,
      b.id_recruta,
      b.timestamp_evento,
      b.dia,
      b.dominio_analitico,
      b.evento_analitico,
      b.origem,
      b.sessao_logica,
      b.sequencia_ordem
    from base b
    on conflict (id_evento) do update
      set
        id_recruta = excluded.id_recruta,
        timestamp_evento = excluded.timestamp_evento,
        dia = excluded.dia,
        dominio_analitico = excluded.dominio_analitico,
        evento_analitico = excluded.evento_analitico,
        origem = excluded.origem,
        sessao_logica = excluded.sessao_logica,
        sequencia_ordem = excluded.sequencia_ordem
    returning 1
  )
  select count(*)::bigint
    into v_linhas_processadas
  from inserted;

  return jsonb_build_object(
    'job', 'c5_fatos_analytics',
    'executado_em', v_executado_em,
    'linhas_processadas', v_linhas_processadas
  );
end;
$$;


ALTER FUNCTION "public"."rpc_c5_atualizar_fatos_analytics"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_c5_atualizar_fatos_analytics"() IS 'Job operacional do C5 Analytics: materializa e atualiza a tabela fato public.c5_fatos_analytics a partir da public.v_c5_eventos_dominios_v3.';



CREATE OR REPLACE FUNCTION "public"."rpc_c5_detectar_alertas_operacionais"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_executado_em timestamptz := now();
  v_linhas_processadas bigint := 0;
begin
  with
  regras as (
    select *
    from public.c5_regras_alerta
    where ativo = true
  ),

  -- pico_auth -> métricas globais do dia atual
  base_pico_auth as (
    select
      r.tipo_alerta,
      r.dominio_analitico,
      'sistema'::text as entidade,
      coalesce(sum(m.total_eventos), 0)::bigint as valor_detectado,
      r.limite as limite_configurado,
      r.tipo_alerta as regra_origem,
      jsonb_build_object(
        'janela', r.janela_tempo,
        'fonte', 'public.c5_metricas_diarias',
        'evento_analitico', r.evento_analitico,
        'dia', current_date
      ) as detalhe
    from regras r
    left join public.c5_metricas_diarias m
      on m.dia = current_date
     and m.dominio_analitico = r.dominio_analitico
     and (
       r.evento_analitico is null
       or m.evento_analitico = r.evento_analitico
     )
    where r.tipo_alerta = 'pico_auth'
    group by
      r.tipo_alerta, r.dominio_analitico, r.limite, r.janela_tempo, r.evento_analitico
  ),

  -- loop_workflow -> métricas globais do dia atual
  base_loop_workflow as (
    select
      r.tipo_alerta,
      r.dominio_analitico,
      'sistema'::text as entidade,
      coalesce(sum(m.total_eventos), 0)::bigint as valor_detectado,
      r.limite as limite_configurado,
      r.tipo_alerta as regra_origem,
      jsonb_build_object(
        'janela', r.janela_tempo,
        'fonte', 'public.c5_metricas_diarias',
        'evento_analitico', r.evento_analitico,
        'dia', current_date
      ) as detalhe
    from regras r
    left join public.c5_metricas_diarias m
      on m.dia = current_date
     and m.dominio_analitico = r.dominio_analitico
     and (
       r.evento_analitico is null
       or m.evento_analitico = r.evento_analitico
     )
    where r.tipo_alerta = 'loop_workflow'
    group by
      r.tipo_alerta, r.dominio_analitico, r.limite, r.janela_tempo, r.evento_analitico
  ),

  -- spam_chat -> métricas por recruta do dia atual
  base_spam_chat as (
    select
      r.tipo_alerta,
      r.dominio_analitico,
      ('recruta:' || m.id_recruta::text)::text as entidade,
      m.total_eventos::bigint as valor_detectado,
      r.limite as limite_configurado,
      r.tipo_alerta as regra_origem,
      jsonb_build_object(
        'janela', r.janela_tempo,
        'fonte', 'public.c5_metricas_recruta',
        'evento_analitico', r.evento_analitico,
        'dia', m.dia,
        'id_recruta', m.id_recruta
      ) as detalhe
    from regras r
    join public.c5_metricas_recruta m
      on m.dia = current_date
     and m.dominio_analitico = r.dominio_analitico
     and m.evento_analitico = r.evento_analitico
    where r.tipo_alerta = 'spam_chat'
  ),

  -- atividade_automatizada -> todos os eventos por recruta do dia atual
  base_atividade_auto as (
    select
      r.tipo_alerta,
      'outros'::text as dominio_analitico,
      ('recruta:' || m.id_recruta::text)::text as entidade,
      sum(m.total_eventos)::bigint as valor_detectado,
      r.limite as limite_configurado,
      r.tipo_alerta as regra_origem,
      jsonb_build_object(
        'janela', r.janela_tempo,
        'fonte', 'public.c5_metricas_recruta',
        'dia', current_date,
        'id_recruta', m.id_recruta
      ) as detalhe
    from regras r
    join public.c5_metricas_recruta m
      on m.dia = current_date
    where r.tipo_alerta = 'atividade_automatizada'
    group by
      r.tipo_alerta, r.limite, r.janela_tempo, m.id_recruta
  ),

  candidatos as (
    select * from base_pico_auth
    union all
    select * from base_loop_workflow
    union all
    select * from base_spam_chat
    union all
    select * from base_atividade_auto
  ),

  excedidos as (
    select *
    from candidatos
    where valor_detectado > limite_configurado
  ),

  inserted as (
    insert into public.c5_alertas_operacionais (
      tipo_alerta,
      dominio_analitico,
      entidade,
      valor_detectado,
      limite_configurado,
      detectado_em,
      regra_origem,
      detalhe
    )
    select
      tipo_alerta,
      dominio_analitico,
      entidade,
      valor_detectado,
      limite_configurado,
      v_executado_em,
      regra_origem,
      detalhe
    from excedidos
    returning 1
  )
  select count(*)::bigint
    into v_linhas_processadas
  from inserted;

  return jsonb_build_object(
    'job', 'c5_alertas_operacionais',
    'executado_em', v_executado_em,
    'linhas_processadas', v_linhas_processadas
  );
end;
$$;


ALTER FUNCTION "public"."rpc_c5_detectar_alertas_operacionais"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_c5_detectar_alertas_operacionais"() IS 'Job operacional do C5: lê métricas materializadas, compara com regras ativas e registra alertas operacionais. Não executa ações automáticas.';



CREATE OR REPLACE FUNCTION "public"."rpc_c5_refresh_metricas_diarias"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_executado_em timestamptz := now();
  v_linhas_processadas bigint := 0;
  v_resultado jsonb;
begin
  with src as (
    select
      date_trunc('day', timestamp_evento)::date as dia,
      dominio_analitico,
      evento_analitico,
      count(*)::bigint as total_eventos
    from public.v_c5_eventos_dominios_v3
    group by
      date_trunc('day', timestamp_evento)::date,
      dominio_analitico,
      evento_analitico
  ),
  upserted as (
    insert into public.c5_metricas_diarias (
      dia,
      dominio_analitico,
      evento_analitico,
      total_eventos
    )
    select
      dia,
      dominio_analitico,
      evento_analitico,
      total_eventos
    from src
    on conflict (dia, dominio_analitico, evento_analitico)
    do update
      set total_eventos = excluded.total_eventos
    returning 1
  )
  select count(*)::bigint
    into v_linhas_processadas
  from upserted;

  v_resultado := jsonb_build_object(
    'job', 'c5_metricas_diarias',
    'executado_em', v_executado_em,
    'linhas_processadas', v_linhas_processadas
  );

  insert into public.c5_jobs_execucao_log (
    job,
    executado_em,
    linhas_processadas,
    status,
    detalhe
  ) values (
    'c5_metricas_diarias',
    v_executado_em,
    v_linhas_processadas,
    'success',
    jsonb_build_object(
      'tabela_destino', 'public.c5_metricas_diarias',
      'fonte', 'public.v_c5_eventos_dominios_v3'
    )
  );

  return v_resultado;

exception
  when others then
    insert into public.c5_jobs_execucao_log (
      job,
      executado_em,
      linhas_processadas,
      status,
      detalhe
    ) values (
      'c5_metricas_diarias',
      v_executado_em,
      0,
      'failed',
      jsonb_build_object(
        'erro_sqlstate', sqlstate,
        'erro_mensagem', sqlerrm,
        'tabela_destino', 'public.c5_metricas_diarias',
        'fonte', 'public.v_c5_eventos_dominios_v3'
      )
    );

    raise;
end;
$$;


ALTER FUNCTION "public"."rpc_c5_refresh_metricas_diarias"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_c5_refresh_metricas_diarias"() IS 'Job operacional do C5: atualiza public.c5_metricas_diarias, retorna confirmação resumida e grava log append-only.';



CREATE OR REPLACE FUNCTION "public"."rpc_c5_refresh_metricas_recruta"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_executado_em timestamptz := now();
  v_linhas_processadas bigint := 0;
  v_resultado jsonb;
begin
  with src as (
    select
      id_recruta,
      date_trunc('day', timestamp_evento)::date as dia,
      dominio_analitico,
      evento_analitico,
      count(*)::bigint as total_eventos
    from public.v_c5_eventos_dominios_v3
    group by
      id_recruta,
      date_trunc('day', timestamp_evento)::date,
      dominio_analitico,
      evento_analitico
  ),
  upserted as (
    insert into public.c5_metricas_recruta (
      id_recruta,
      dia,
      dominio_analitico,
      evento_analitico,
      total_eventos
    )
    select
      id_recruta,
      dia,
      dominio_analitico,
      evento_analitico,
      total_eventos
    from src
    on conflict (id_recruta, dia, dominio_analitico, evento_analitico)
    do update
      set total_eventos = excluded.total_eventos
    returning 1
  )
  select count(*)::bigint
    into v_linhas_processadas
  from upserted;

  v_resultado := jsonb_build_object(
    'job', 'c5_metricas_recruta',
    'executado_em', v_executado_em,
    'linhas_processadas', v_linhas_processadas
  );

  insert into public.c5_jobs_execucao_log (
    job,
    executado_em,
    linhas_processadas,
    status,
    detalhe
  ) values (
    'c5_metricas_recruta',
    v_executado_em,
    v_linhas_processadas,
    'success',
    jsonb_build_object(
      'tabela_destino', 'public.c5_metricas_recruta',
      'fonte', 'public.v_c5_eventos_dominios_v3'
    )
  );

  return v_resultado;

exception
  when others then
    insert into public.c5_jobs_execucao_log (
      job,
      executado_em,
      linhas_processadas,
      status,
      detalhe
    ) values (
      'c5_metricas_recruta',
      v_executado_em,
      0,
      'failed',
      jsonb_build_object(
        'erro_sqlstate', sqlstate,
        'erro_mensagem', sqlerrm,
        'tabela_destino', 'public.c5_metricas_recruta',
        'fonte', 'public.v_c5_eventos_dominios_v3'
      )
    );

    raise;
end;
$$;


ALTER FUNCTION "public"."rpc_c5_refresh_metricas_recruta"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_c5_refresh_metricas_recruta"() IS 'Job operacional do C5: atualiza public.c5_metricas_recruta, retorna confirmação resumida e grava log append-only.';



CREATE OR REPLACE FUNCTION "public"."rpc_chat_mark_read"("p_conversa_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_recruta_id uuid;
  v_corr text;
  v_evento_id uuid;
  v_evento_status text;
  v_c5_errors jsonb := '[]'::jsonb;
BEGIN
  v_auth_id := auth.uid();

  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT c.recruta_id
  INTO v_recruta_id
  FROM public.chat_conversas c
  JOIN public.recrutas r
    ON r.id = c.recruta_id
  WHERE c.id = p_conversa_id
    AND r.auth_id = v_auth_id
  LIMIT 1;

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'CONVERSA_NOT_FOUND';
  END IF;

  v_corr := 'chat_read:' || p_conversa_id::text || ':' || v_recruta_id::text;

  INSERT INTO public.chat_reads (
    conversa_id,
    recruta_id,
    last_read_at,
    updated_at
  )
  VALUES (
    p_conversa_id,
    v_recruta_id,
    now(),
    now()
  )
  ON CONFLICT (conversa_id, recruta_id)
  DO UPDATE SET
    last_read_at = excluded.last_read_at,
    updated_at = now();

  UPDATE public.chat_conversas
  SET
    unread_count = 0,
    updated_at = now()
  WHERE id = p_conversa_id;

  UPDATE public.chat_mensagens
  SET status = 'read'
  WHERE conversa_id = p_conversa_id
    AND recruta_id = v_recruta_id
    AND role = 'assistant'
    AND status = 'sent';

  BEGIN
    SELECT e.evento_id, e.status
    INTO v_evento_id, v_evento_status
    FROM public.emitir_evento_c5(
      v_recruta_id,
      'chat_mensagem_lida',
      'chat_mensagem_lida:' || p_conversa_id::text || ':' || v_recruta_id::text,
      v_corr,
      'rpc_chat_mark_read',
      jsonb_build_object(
        'conversa_id', p_conversa_id,
        'recruta_id', v_recruta_id
      )
    ) e
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_c5_errors := v_c5_errors || jsonb_build_object(
      'evento', 'chat_mensagem_lida',
      'sqlstate', SQLSTATE,
      'message', SQLERRM
    );
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'conversa_id', p_conversa_id,
    'unread_count', 0,
    'c5_errors', v_c5_errors
  );
END;
$$;


ALTER FUNCTION "public"."rpc_chat_mark_read"("p_conversa_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_chat_mark_read"("p_conversa_id" "uuid") IS 'RCC-0.5 Wave 1: marca conversa como lida, zera unread e emite C5.';



CREATE OR REPLACE FUNCTION "public"."rpc_chat_open_conversation"("p_instrutor_slug" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_recruta_id uuid;
  v_conversa_id uuid;
BEGIN
  v_auth_id := auth.uid();

  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF p_instrutor_slug NOT IN ('objetivo', 'estrategico', 'didatico') THEN
    RAISE EXCEPTION 'INSTRUTOR_INVALIDO';
  END IF;

  SELECT r.id
  INTO v_recruta_id
  FROM public.recrutas r
  WHERE r.auth_id = v_auth_id
  LIMIT 1;

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'RECRUTA_NOT_FOUND';
  END IF;

  SELECT c.id
  INTO v_conversa_id
  FROM public.chat_conversas c
  WHERE c.recruta_id = v_recruta_id
    AND c.instrutor_slug = p_instrutor_slug
  LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'exists', v_conversa_id IS NOT NULL,
    'conversa_id', v_conversa_id,
    'recruta_id', v_recruta_id,
    'instrutor_slug', p_instrutor_slug
  );
END;
$$;


ALTER FUNCTION "public"."rpc_chat_open_conversation"("p_instrutor_slug" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_chat_open_conversation"("p_instrutor_slug" "text") IS 'RCC-0.5 Wave 1: resolve conversa existente. Não cria conversa vazia.';



CREATE OR REPLACE FUNCTION "public"."rpc_chat_send_message"("p_instrutor_slug" "text", "p_client_message_id" "text", "p_user_text" "text", "p_assistant_text" "text", "p_correlation_id" "text" DEFAULT NULL::"text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_recruta_id uuid;
  v_conversa_id uuid;
  v_created_conversa boolean := false;
  v_user_message_id uuid;
  v_assistant_message_id uuid;
  v_base_idem text;
  v_corr text;
  v_evento_id uuid;
  v_evento_status text;
  v_c5_errors jsonb := '[]'::jsonb;
BEGIN
  v_auth_id := auth.uid();

  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF p_instrutor_slug NOT IN ('objetivo', 'estrategico', 'didatico') THEN
    RAISE EXCEPTION 'INSTRUTOR_INVALIDO';
  END IF;

  IF NULLIF(BTRIM(p_client_message_id), '') IS NULL THEN
    RAISE EXCEPTION 'CLIENT_MESSAGE_ID_REQUIRED';
  END IF;

  IF NULLIF(BTRIM(p_user_text), '') IS NULL THEN
    RAISE EXCEPTION 'USER_TEXT_REQUIRED';
  END IF;

  IF NULLIF(BTRIM(p_assistant_text), '') IS NULL THEN
    RAISE EXCEPTION 'ASSISTANT_TEXT_REQUIRED';
  END IF;

  SELECT r.id
  INTO v_recruta_id
  FROM public.recrutas r
  WHERE r.auth_id = v_auth_id
  LIMIT 1;

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'RECRUTA_NOT_FOUND';
  END IF;

  v_base_idem := 'chat:' || v_recruta_id::text || ':' || BTRIM(p_client_message_id);
  v_corr := COALESCE(NULLIF(BTRIM(p_correlation_id), ''), v_base_idem);

  -- Cria conversa somente na primeira mensagem.
  INSERT INTO public.chat_conversas (
    recruta_id,
    instrutor_slug,
    status,
    opened_at,
    last_message_at,
    unread_count
  )
  VALUES (
    v_recruta_id,
    p_instrutor_slug,
    'active',
    now(),
    now(),
    0
  )
  ON CONFLICT (recruta_id, instrutor_slug)
  DO UPDATE SET
    updated_at = now()
  RETURNING id, (xmax = 0) INTO v_conversa_id, v_created_conversa;

  -- Mensagem do usuário.
  INSERT INTO public.chat_mensagens (
    conversa_id,
    recruta_id,
    instrutor_slug,
    role,
    conteudo,
    status,
    client_message_id,
    idempotency_key,
    correlation_id,
    origem,
    metadata
  )
  VALUES (
    v_conversa_id,
    v_recruta_id,
    p_instrutor_slug,
    'user',
    BTRIM(p_user_text),
    'sent',
    BTRIM(p_client_message_id),
    v_base_idem || ':user',
    v_corr,
    'app',
    COALESCE(p_metadata, '{}'::jsonb)
  )
  ON CONFLICT (idempotency_key)
  DO UPDATE SET
    metadata = public.chat_mensagens.metadata
  RETURNING id INTO v_user_message_id;

  -- Resposta do assistente.
  INSERT INTO public.chat_mensagens (
    conversa_id,
    recruta_id,
    instrutor_slug,
    role,
    conteudo,
    status,
    client_message_id,
    idempotency_key,
    correlation_id,
    origem,
    metadata
  )
  VALUES (
    v_conversa_id,
    v_recruta_id,
    p_instrutor_slug,
    'assistant',
    BTRIM(p_assistant_text),
    'sent',
    BTRIM(p_client_message_id),
    v_base_idem || ':assistant',
    v_corr,
    'chat_central',
    COALESCE(p_metadata, '{}'::jsonb)
  )
  ON CONFLICT (idempotency_key)
  DO UPDATE SET
    metadata = public.chat_mensagens.metadata
  RETURNING id INTO v_assistant_message_id;

  -- Unread é materializado: resposta do assistente gera unread para o recruta.
  -- Se foi replay idempotente e a mensagem já existia, ainda mantemos comportamento seguro:
  -- incremento apenas se essa tentativa criou/retornou mensagem e conversa existe.
  UPDATE public.chat_conversas
  SET
    unread_count = GREATEST(unread_count, 0) + 1,
    last_message_at = now(),
    updated_at = now()
  WHERE id = v_conversa_id
    AND v_assistant_message_id IS NOT NULL;

  -- Evento C5: conversa aberta, somente quando a conversa nasceu agora.
  IF v_created_conversa THEN
    BEGIN
      SELECT e.evento_id, e.status
      INTO v_evento_id, v_evento_status
      FROM public.emitir_evento_c5(
        v_recruta_id,
        'chat_conversa_aberta',
        'chat_conversa_aberta:' || v_conversa_id::text,
        v_corr,
        'rpc_chat_send_message',
        jsonb_build_object(
          'conversa_id', v_conversa_id,
          'instrutor_slug', p_instrutor_slug,
          'client_message_id', p_client_message_id
        )
      ) e
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_c5_errors := v_c5_errors || jsonb_build_object(
        'evento', 'chat_conversa_aberta',
        'sqlstate', SQLSTATE,
        'message', SQLERRM
      );
    END;
  END IF;

  -- Evento C5: mensagem enviada.
  BEGIN
    SELECT e.evento_id, e.status
    INTO v_evento_id, v_evento_status
    FROM public.emitir_evento_c5(
      v_recruta_id,
      'chat_mensagem_enviada',
      'chat_mensagem_enviada:' || v_base_idem,
      v_corr,
      'rpc_chat_send_message',
      jsonb_build_object(
        'conversa_id', v_conversa_id,
        'user_message_id', v_user_message_id,
        'assistant_message_id', v_assistant_message_id,
        'instrutor_slug', p_instrutor_slug,
        'client_message_id', p_client_message_id
      )
    ) e
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_c5_errors := v_c5_errors || jsonb_build_object(
      'evento', 'chat_mensagem_enviada',
      'sqlstate', SQLSTATE,
      'message', SQLERRM
    );
  END;

  -- Evento C5: unread incrementado.
  BEGIN
    SELECT e.evento_id, e.status
    INTO v_evento_id, v_evento_status
    FROM public.emitir_evento_c5(
      v_recruta_id,
      'chat_unread_incrementado',
      'chat_unread_incrementado:' || v_conversa_id::text || ':' || v_base_idem,
      v_corr,
      'rpc_chat_send_message',
      jsonb_build_object(
        'conversa_id', v_conversa_id,
        'instrutor_slug', p_instrutor_slug,
        'client_message_id', p_client_message_id
      )
    ) e
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_c5_errors := v_c5_errors || jsonb_build_object(
      'evento', 'chat_unread_incrementado',
      'sqlstate', SQLSTATE,
      'message', SQLERRM
    );
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'conversa_id', v_conversa_id,
    'created_conversa', v_created_conversa,
    'user_message_id', v_user_message_id,
    'assistant_message_id', v_assistant_message_id,
    'client_message_id', p_client_message_id,
    'correlation_id', v_corr,
    'c5_errors', v_c5_errors
  );
END;
$$;


ALTER FUNCTION "public"."rpc_chat_send_message"("p_instrutor_slug" "text", "p_client_message_id" "text", "p_user_text" "text", "p_assistant_text" "text", "p_correlation_id" "text", "p_metadata" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."rpc_chat_send_message"("p_instrutor_slug" "text", "p_client_message_id" "text", "p_user_text" "text", "p_assistant_text" "text", "p_correlation_id" "text", "p_metadata" "jsonb") IS 'RCC-0.5 Wave 1: persiste par mensagem usuário/resposta Chat Central, governa unread e emite C5. Não processa IA.';



CREATE OR REPLACE FUNCTION "public"."rpc_chat_summary_upsert"("p_recruta_id" "uuid", "p_thread_id" "text", "p_summary" "text") RETURNS TABLE("recruta_id" "uuid", "thread_id" "text", "version" integer, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_autorizado boolean := false;
  v_result public.chat_summaries%rowtype;
begin
  v_autorizado :=
    current_user = 'postgres'
    or auth.role() = 'service_role'
    or exists (
      select 1
      from public.recrutas r
      where r.id = p_recruta_id
        and r.auth_id = auth.uid()
    );

  if not v_autorizado then
    raise exception 'ACESSO_NEGADO_CHAT_SUMMARY';
  end if;

  insert into public.chat_summaries as cs (
    recruta_id,
    thread_id,
    summary,
    version
  )
  values (
    p_recruta_id,
    p_thread_id,
    coalesce(p_summary, ''),
    1
  )
  on conflict on constraint chat_summaries_pkey
  do update
     set thread_id = excluded.thread_id,
         summary = excluded.summary,
         version = cs.version + 1,
         updated_at = now()
  returning cs.*
  into v_result;

  return query
  select
    v_result.recruta_id,
    v_result.thread_id,
    v_result.version,
    v_result.updated_at;
end;
$$;


ALTER FUNCTION "public"."rpc_chat_summary_upsert"("p_recruta_id" "uuid", "p_thread_id" "text", "p_summary" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_complete_onboarding"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_recruta_id uuid;
  v_onboarding_concluido boolean;
  v_evento_id uuid;
  v_evento_status text;
BEGIN
  v_auth_id := auth.uid();

  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT id, COALESCE(onboarding_concluido, false)
  INTO v_recruta_id, v_onboarding_concluido
  FROM public.recrutas
  WHERE auth_id = v_auth_id
  LIMIT 1;

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'RECRUTA_NOT_FOUND';
  END IF;

  IF v_onboarding_concluido = true THEN
    RETURN jsonb_build_object(
      'ok', true,
      'changed', false,
      'recruta_id', v_recruta_id,
      'onboarding_concluido', true
    );
  END IF;

  UPDATE public.recrutas
  SET onboarding_concluido = true,
      updated_at = now()
  WHERE id = v_recruta_id;

  SELECT e.evento_id, e.status
  INTO v_evento_id, v_evento_status
  FROM public.emitir_evento_c5(
    v_recruta_id,
    'onboarding_concluido',
    'onboarding_concluido:' || v_recruta_id::text,
    gen_random_uuid()::text,
    'sistema',
    jsonb_build_object(
      'origem', 'rpc_complete_onboarding'
    )
  ) e
  LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'changed', true,
    'recruta_id', v_recruta_id,
    'onboarding_concluido', true,
    'evento_id', v_evento_id,
    'evento_status', v_evento_status
  );
END;
$$;


ALTER FUNCTION "public"."rpc_complete_onboarding"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_complete_onboarding"("p_forca" "text", "p_nome_guerra" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_user_id         UUID := auth.uid();
    v_forca_norm      TEXT;
    v_nome            TEXT;
    v_email           TEXT;
BEGIN
    -- Sessão obrigatória
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    -- Normaliza forca: aceita inglês (legado) e português (canônico)
    v_forca_norm := CASE p_forca
        WHEN 'navy'     THEN 'marinha'
        WHEN 'army'     THEN 'exercito'
        WHEN 'airforce' THEN 'aeronautica'
        ELSE p_forca
    END;

    IF v_forca_norm NOT IN ('marinha', 'exercito', 'aeronautica') THEN
        RAISE EXCEPTION 'INVALID_FORCA: %', p_forca;
    END IF;

    IF p_nome_guerra IS NULL OR trim(p_nome_guerra) = '' THEN
        RAISE EXCEPTION 'NOME_GUERRA_OBRIGATORIO';
    END IF;

    -- Obtém nome e email do usuário a partir dos metadados do Supabase Auth.
    -- Google OAuth preenche raw_user_meta_data com 'full_name' ou 'name'.
    SELECT
        COALESCE(
            NULLIF(trim(u.raw_user_meta_data->>'full_name'), ''),
            NULLIF(trim(u.raw_user_meta_data->>'name'), ''),
            NULLIF(trim(u.email), ''),
            'Recruta'
        ),
        COALESCE(NULLIF(trim(u.email), ''), 'sem-email@quarteldigital.local')
    INTO v_nome, v_email
    FROM auth.users u
    WHERE u.id = v_user_id;

    -- UPSERT: cria recruta se não existir, atualiza se já existir.
    -- Columns not listed here use their table defaults (xp=0, xp_total=0, etc.)
    INSERT INTO public.recrutas (
        id,
        auth_id,
        email,
        nome,
        forca,
        nome_guerra,
        onboarding_concluido
    )
    VALUES (
        v_user_id,
        v_user_id,
        v_email,
        v_nome,
        v_forca_norm,
        trim(p_nome_guerra),
        true
    )
    ON CONFLICT (id) DO UPDATE SET
        forca                = EXCLUDED.forca,
        nome_guerra          = EXCLUDED.nome_guerra,
        onboarding_concluido = true;
    -- nome, auth_id e email NÃO são sobrescritos no UPDATE para preservar dados existentes
END;
$$;


ALTER FUNCTION "public"."rpc_complete_onboarding"("p_forca" "text", "p_nome_guerra" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_mark_notice_read"("p_notice_id" "uuid", "p_recruta_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.institutional_notice_reads (notice_id, recruta_id)
  VALUES (p_notice_id, p_recruta_id)
  ON CONFLICT (notice_id, recruta_id) DO NOTHING;

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."rpc_mark_notice_read"("p_notice_id" "uuid", "p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_mark_onboarding_complete"("p_recruta_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_forca text;
  v_onboarding boolean;
  v_nome_guerra text;
BEGIN
  SELECT forca, onboarding_concluido, nome_guerra
  INTO v_current_forca, v_onboarding, v_nome_guerra
  FROM public.recrutas
  WHERE id = p_recruta_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'recruta_nao_encontrado';
  END IF;

  IF COALESCE(v_onboarding, false) = true THEN
    RETURN true;
  END IF;

  IF v_current_forca IS NULL THEN
    RAISE EXCEPTION 'forca_nao_definida';
  END IF;

  IF NULLIF(TRIM(v_nome_guerra), '') IS NULL THEN
    RAISE EXCEPTION 'nome_guerra_obrigatorio';
  END IF;

  UPDATE public.recrutas
  SET onboarding_concluido = true
  WHERE id = p_recruta_id
    AND forca IS NOT NULL
    AND NULLIF(TRIM(nome_guerra), '') IS NOT NULL
    AND COALESCE(onboarding_concluido, false) = false;

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."rpc_mark_onboarding_complete"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_select_force"("p_recruta_id" "uuid", "p_forca" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_forca text;
  v_onboarding boolean;
BEGIN
  IF p_forca NOT IN ('marinha', 'exercito', 'aeronautica') THEN
    RAISE EXCEPTION 'forca_invalida';
  END IF;

  SELECT forca, onboarding_concluido
  INTO v_current_forca, v_onboarding
  FROM public.recrutas
  WHERE id = p_recruta_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'recruta_nao_encontrado';
  END IF;

  IF v_current_forca IS NOT NULL THEN
    RETURN true;
  END IF;

  IF COALESCE(v_onboarding, false) = true THEN
    RAISE EXCEPTION 'onboarding_ja_concluido';
  END IF;

  UPDATE public.recrutas
  SET forca = p_forca
  WHERE id = p_recruta_id
    AND forca IS NULL
    AND COALESCE(onboarding_concluido, false) = false;

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."rpc_select_force"("p_recruta_id" "uuid", "p_forca" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_set_instructor_profile"("p_instructor_profile_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_allowed text[] := ARRAY['objetivo','estrategico','didatico'];
BEGIN
  v_auth_id := auth.uid();

  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF p_instructor_profile_id IS NULL
     OR NOT (p_instructor_profile_id = ANY(v_allowed)) THEN
    RAISE EXCEPTION 'INSTRUCTOR_PROFILE_INVALIDO';
  END IF;

  UPDATE public.profiles
  SET instructor_profile_id = p_instructor_profile_id
  WHERE id = v_auth_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'auth_id', v_auth_id,
    'instructor_profile_id', p_instructor_profile_id
  );
END;
$$;


ALTER FUNCTION "public"."rpc_set_instructor_profile"("p_instructor_profile_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_set_nome_guerra"("p_recruta_id" "uuid", "p_nome_guerra" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_onboarding boolean;
BEGIN
  IF NULLIF(TRIM(p_nome_guerra), '') IS NULL THEN
    RAISE EXCEPTION 'nome_guerra_obrigatorio';
  END IF;

  SELECT onboarding_concluido
  INTO v_onboarding
  FROM public.recrutas
  WHERE id = p_recruta_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'recruta_nao_encontrado';
  END IF;

  IF COALESCE(v_onboarding, false) = true THEN
    RAISE EXCEPTION 'onboarding_ja_concluido';
  END IF;

  UPDATE public.recrutas
  SET nome_guerra = TRIM(p_nome_guerra)
  WHERE id = p_recruta_id
    AND COALESCE(onboarding_concluido, false) = false;

  RETURN true;
END;
$$;


ALTER FUNCTION "public"."rpc_set_nome_guerra"("p_recruta_id" "uuid", "p_nome_guerra" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_set_recruta_forca"("p_forca" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_recruta_id uuid;
  v_forca_atual text;
  v_evento_id uuid;
  v_evento_status text;
BEGIN
  v_auth_id := auth.uid();

  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF p_forca NOT IN ('marinha','exercito','aeronautica') THEN
    RAISE EXCEPTION 'FORCA_INVALIDA';
  END IF;

  SELECT id, forca
  INTO v_recruta_id, v_forca_atual
  FROM public.recrutas
  WHERE auth_id = v_auth_id
  LIMIT 1;

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'RECRUTA_NOT_FOUND';
  END IF;

  IF v_forca_atual = p_forca THEN
    RETURN jsonb_build_object(
      'ok', true,
      'changed', false,
      'recruta_id', v_recruta_id,
      'forca', p_forca
    );
  END IF;

  UPDATE public.recrutas
  SET forca = p_forca,
      updated_at = now()
  WHERE id = v_recruta_id;

  SELECT e.evento_id, e.status
  INTO v_evento_id, v_evento_status
  FROM public.emitir_evento_c5(
    v_recruta_id,
    'forca_selecionada',
    'forca_selecionada:' || v_recruta_id::text || ':' || p_forca,
    gen_random_uuid()::text,
    'sistema',
    jsonb_build_object(
      'forca_anterior', v_forca_atual,
      'forca_nova', p_forca,
      'origem', 'rpc_set_recruta_forca'
    )
  ) e
  LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'changed', true,
    'recruta_id', v_recruta_id,
    'forca', p_forca,
    'evento_id', v_evento_id,
    'evento_status', v_evento_status
  );
END;
$$;


ALTER FUNCTION "public"."rpc_set_recruta_forca"("p_forca" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_update_instructor_profile"("p_instructor_profile_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_recruta_id uuid;
  v_old_codigo text;
  v_input text;
  v_new_codigo text;
  v_evento_id uuid;
  v_evento_status text;
  v_c5_errors jsonb := '[]'::jsonb;
BEGIN
  v_auth_id := auth.uid();

  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  v_input := lower(btrim(p_instructor_profile_id));

  v_new_codigo := CASE v_input
    WHEN 'ramos' THEN 'objetivo'
    WHEN 'rocha' THEN 'estrategico'
    WHEN 'sara' THEN 'didatico'
    WHEN 'objetivo' THEN 'objetivo'
    WHEN 'estrategico' THEN 'estrategico'
    WHEN 'didatico' THEN 'didatico'
    ELSE NULL
  END;

  IF v_new_codigo IS NULL THEN
    RAISE EXCEPTION 'INSTRUCTOR_PROFILE_INVALID';
  END IF;

  SELECT
    r.id,
    r.instructor_profile_id
  INTO
    v_recruta_id,
    v_old_codigo
  FROM public.recrutas r
  WHERE r.auth_id = v_auth_id
  LIMIT 1;

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'RECRUTA_NOT_FOUND';
  END IF;

  IF COALESCE(v_old_codigo, '') <> v_new_codigo THEN
    UPDATE public.recrutas
    SET
      instructor_profile_id = v_new_codigo,
      updated_at = now()
    WHERE id = v_recruta_id
      AND auth_id = v_auth_id;

    BEGIN
      SELECT e.evento_id, e.status
      INTO v_evento_id, v_evento_status
      FROM public.emitir_evento_c5(
        v_recruta_id,
        'instrutor_profile_updated',
        'instrutor_profile_updated:' || v_recruta_id::text || ':' || v_new_codigo,
        'instrutor_profile_updated:' || v_recruta_id::text,
        'rpc_update_instructor_profile',
        jsonb_build_object(
          'old_instructor_profile_id', v_old_codigo,
          'new_instructor_profile_id', v_new_codigo,
          'input', v_input,
          'persisted_in', 'recrutas.instructor_profile_id'
        )
      ) e
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_c5_errors := v_c5_errors || jsonb_build_object(
        'evento', 'instrutor_profile_updated',
        'sqlstate', SQLSTATE,
        'message', SQLERRM
      );
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'recruta_id', v_recruta_id,
    'input', v_input,
    'instructor_profile_id', v_new_codigo,
    'changed', COALESCE(v_old_codigo, '') <> v_new_codigo,
    'evento_id', v_evento_id,
    'evento_status', v_evento_status,
    'c5_errors', v_c5_errors
  );
END;
$$;


ALTER FUNCTION "public"."rpc_update_instructor_profile"("p_instructor_profile_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_nome_default"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if new.nome is null or new.nome = '' then
    new.nome := 'Recruta ' || left(new.id::text, 4);
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."set_nome_default"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."set_nome_default"() IS 'Institutional trigger helper. SECURITY INVOKER. search_path fixed to public.';



CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."set_updated_at"() IS 'Institutional trigger helper. SECURITY INVOKER. search_path fixed to public.';



CREATE OR REPLACE FUNCTION "public"."snapshot_medalha"("p_medalha_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_medalha record;
    v_regras jsonb;
    v_proxima_versao integer;
begin

    -- buscar medalha
    select *
    into v_medalha
    from public.medalhas_catalogo
    where id = p_medalha_id;

    if not found then
        raise exception 'Medalha % não encontrada no catálogo.', p_medalha_id;
    end if;

    -- buscar regras associadas
    select coalesce(
        jsonb_agg(to_jsonb(r) order by r.id),
        '[]'::jsonb
    )
    into v_regras
    from public.medalha_regras r
    where r.medalha_id = p_medalha_id;

    -- calcular próxima versão
    select coalesce(max(versao), 0) + 1
    into v_proxima_versao
    from public.medalhas_catalogo_versionamento
    where medalha_id = p_medalha_id;

    -- inserir snapshot
    insert into public.medalhas_catalogo_versionamento (
        medalha_id,
        versao,
        snapshot_catalogo,
        snapshot_regras
    )
    values (
        p_medalha_id,
        v_proxima_versao,
        to_jsonb(v_medalha),
        v_regras
    );

    return v_proxima_versao;
end;
$$;


ALTER FUNCTION "public"."snapshot_medalha"("p_medalha_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_recrutas_normalizar_nome_guerra"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.nome_guerra is not null then
    new.nome_guerra := regexp_replace(btrim(new.nome_guerra), '\s+', ' ', 'g');
    if new.nome_guerra = '' then
      new.nome_guerra := null;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."trg_recrutas_normalizar_nome_guerra"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_set_data_inicio_individual"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.data_inicio_individual is null then
    -- Prioridade 1: semana atual no cronograma
    select cr.data_inicio
      into new.data_inicio_individual
    from public.cronograma_semanal cr
    where cr.ciclo_id = new.ciclo_id
      and cr.semana_num = new.semana_atual
    limit 1;

    -- Fallback: data_inicio do ciclo
    if new.data_inicio_individual is null then
      select cf.data_inicio
        into new.data_inicio_individual
      from public.ciclos_formativos cf
      where cf.id = new.ciclo_id
      limit 1;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."trg_set_data_inicio_individual"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."trg_set_data_inicio_individual"() IS 'C6.2: Garante data_inicio_individual preenchido em recruta_ciclo_status quando ausente.';



CREATE OR REPLACE FUNCTION "public"."trg_verificar_honra_maxima"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  PERFORM verificar_honra_maxima(NEW.recruta_id);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_verificar_honra_maxima"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_verificar_medalhas_conclusao"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Instrução completa
  PERFORM verificar_medalha_instrucao_completa(
    NEW.recruta_id,
    NEW.modulo_id
  );

  -- Revisão cumprida
  PERFORM verificar_medalha_revisao_cumprida(
    NEW.recruta_id,
    NEW.modulo_id
  );

  -- Missão cumprida
  PERFORM verificar_medalha_missao_cumprida(
    NEW.recruta_id,
    NEW.modulo_id
  );

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_verificar_medalhas_conclusao"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_verificar_medalhas_desempenho"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Precisão (por revisão)
  PERFORM verificar_medalha_precisao(
    NEW.recruta_id,
    NEW.revisao_id
  );

  -- Domínio (global)
  PERFORM verificar_medalha_dominio(
    NEW.recruta_id
  );

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_verificar_medalhas_desempenho"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_metrics_daily_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."update_metrics_daily_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_elegibilidade_grau6"("p_recruta_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_auth_id uuid;
  v_forca text;
  v_ciclo_id uuid;

  v_iea numeric;
  v_simulado numeric;

  v_status text;
  v_semanas_validas integer;

  v_ok boolean := true;
  v_motivo text := NULL;
BEGIN
  -- anti-bypass: só o próprio recruta
  SELECT auth_id, forca INTO v_auth_id, v_forca
  FROM public.recrutas
  WHERE id = p_recruta_id;

  IF auth.uid() IS NULL OR v_auth_id IS NULL OR v_auth_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('ok', false, 'motivo_negacao', 'C6_FORBIDDEN');
  END IF;

  -- ciclo vigente
  SELECT c.id INTO v_ciclo_id
  FROM public.ciclos_formativos c
  WHERE c.forca = v_forca
    AND CURRENT_DATE BETWEEN c.data_inicio AND c.data_fim
  ORDER BY c.data_inicio DESC
  LIMIT 1;

  IF v_ciclo_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo_negacao', 'SEM_CICLO_VIGENTE');
  END IF;

  -- status do ciclo do recruta
  SELECT regularidade_status, semanas_validas
    INTO v_status, v_semanas_validas
  FROM public.recruta_ciclo_status
  WHERE recruta_id = p_recruta_id
    AND ciclo_id = v_ciclo_id
  LIMIT 1;

  IF v_status IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo_negacao', 'STATUS_CICLO_INEXISTENTE');
  END IF;

  -- IEA e simulado final (fallback NULL => reprova com motivo claro)
  v_iea := public.c6_get_iea_score(p_recruta_id, v_ciclo_id);
  v_simulado := public.c6_get_simulado_final_score(p_recruta_id, v_ciclo_id);

  IF v_status = 'comprometida' THEN
    v_ok := false; v_motivo := 'REGULARIDADE_COMPROMETIDA';
  ELSIF v_semanas_validas < 12 THEN
    v_ok := false; v_motivo := 'SEMANAS_VALIDAS_INSUFICIENTES';
  ELSIF v_iea IS NULL OR v_iea < 80 THEN
    v_ok := false; v_motivo := 'IEA_INSUFICIENTE';
  ELSIF v_simulado IS NULL OR v_simulado < 75 THEN
    v_ok := false; v_motivo := 'SIMULADO_FINAL_INSUFICIENTE';
  END IF;

  RETURN jsonb_build_object(
    'ok', v_ok,
    'motivo_negacao', v_motivo,
    'ciclo_id', v_ciclo_id,
    'iea', v_iea,
    'simulado_final', v_simulado,
    'regularidade_status', v_status,
    'semanas_validas', v_semanas_validas
  );
END;
$$;


ALTER FUNCTION "public"."verificar_elegibilidade_grau6"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_honra_maxima"("p_recruta" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  total_obrigatorias int;
  total_conquistadas int;
BEGIN
  -- total de medalhas obrigatórias ativas
  SELECT COUNT(*) INTO total_obrigatorias
  FROM medalhas
  WHERE obrigatoria = true
    AND ativa = true;

  -- total de medalhas obrigatórias conquistadas pelo recruta
  SELECT COUNT(DISTINCT rm.medalha_id) INTO total_conquistadas
  FROM recruta_medalhas rm
  JOIN medalhas m ON m.id = rm.medalha_id
  WHERE rm.recruta_id = p_recruta
    AND m.obrigatoria = true
    AND m.ativa = true;

  -- se completou todas, concede LENDA VIVA
  IF total_obrigatorias > 0
     AND total_conquistadas = total_obrigatorias THEN

    UPDATE recruta_status
    SET
      honra_maxima = true,
      nivel = 6,
      patente = 'LENDA_VIVA',
      atualizado_em = now()
    WHERE recruta_id = p_recruta;

  END IF;
END;
$$;


ALTER FUNCTION "public"."verificar_honra_maxima"("p_recruta" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_medalha_dominio"("p_recruta" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  media_acerto numeric;
  total_revisoes int;
BEGIN
  SELECT
    AVG(percentual_acerto),
    COUNT(*)
  INTO
    media_acerto,
    total_revisoes
  FROM recruta_desempenho_revisoes
  WHERE recruta_id = p_recruta;

  IF total_revisoes >= 3 AND media_acerto >= 90 THEN
    INSERT INTO recruta_medalhas (recruta_id, medalha_id)
    SELECT p_recruta, id
    FROM medalhas
    WHERE codigo = 'DOMINIO'
      AND ativa = true
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;


ALTER FUNCTION "public"."verificar_medalha_dominio"("p_recruta" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_medalha_instrucao_completa"("p_recruta" "uuid", "p_modulo" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM recruta_progressos_modulos
    WHERE recruta_id = p_recruta
      AND modulo_id = p_modulo
      AND aulas_concluidas = total_aulas
  ) THEN
    INSERT INTO recruta_medalhas (recruta_id, medalha_id)
    SELECT p_recruta, id
    FROM medalhas
    WHERE codigo = 'INSTRUCAO_COMPLETA'
      AND ativa = true
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;


ALTER FUNCTION "public"."verificar_medalha_instrucao_completa"("p_recruta" "uuid", "p_modulo" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_medalha_missao_cumprida"("p_recruta" "uuid", "p_modulo" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM recruta_progressos_modulos
    WHERE recruta_id = p_recruta
      AND modulo_id = p_modulo
      AND aulas_concluidas = total_aulas
      AND revisoes_concluidas = total_revisoes
  ) THEN
    INSERT INTO recruta_medalhas (recruta_id, medalha_id)
    SELECT p_recruta, id
    FROM medalhas
    WHERE codigo = 'MISSAO_CUMPRIDA'
      AND ativa = true
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;


ALTER FUNCTION "public"."verificar_medalha_missao_cumprida"("p_recruta" "uuid", "p_modulo" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_medalha_precisao"("p_recruta" "uuid", "p_revisao" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM recruta_desempenho_revisoes
    WHERE recruta_id = p_recruta
      AND revisao_id = p_revisao
      AND percentual_acerto = 100
  ) THEN
    INSERT INTO recruta_medalhas (recruta_id, medalha_id)
    SELECT p_recruta, id
    FROM medalhas
    WHERE codigo = 'PRECISAO'
      AND ativa = true
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;


ALTER FUNCTION "public"."verificar_medalha_precisao"("p_recruta" "uuid", "p_revisao" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_medalha_revisao_cumprida"("p_recruta" "uuid", "p_modulo" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM recruta_progressos_modulos
    WHERE recruta_id = p_recruta
      AND modulo_id = p_modulo
      AND revisoes_concluidas = total_revisoes
  ) THEN
    INSERT INTO recruta_medalhas (recruta_id, medalha_id)
    SELECT p_recruta, id
    FROM medalhas
    WHERE codigo = 'REVISAO_CUMPRIDA'
      AND ativa = true
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;


ALTER FUNCTION "public"."verificar_medalha_revisao_cumprida"("p_recruta" "uuid", "p_modulo" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_medalha_sentinela"("p_recruta" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF (
    SELECT dias_consecutivos
    FROM recruta_status
    WHERE recruta_id = p_recruta
  ) >= 15 THEN
    INSERT INTO recruta_medalhas (recruta_id, medalha_id)
    SELECT p_recruta, id
    FROM medalhas
    WHERE codigo = 'SENTINELA'
      AND ativa = true
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;


ALTER FUNCTION "public"."verificar_medalha_sentinela"("p_recruta" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_medalhas_obrigatorias"("p_recruta_id" "uuid") RETURNS TABLE("elegivel" boolean, "faltantes" "text"[])
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_forca text;
begin
  select r.forca::text into v_forca
  from public.recrutas r
  where r.id = p_recruta_id;

  if v_forca is null or v_forca not in ('marinha','exercito','aeronautica') then
    return query
    select false,
           coalesce(array_agg(distinct m.medalha_slug order by m.medalha_slug), '{}'::text[])
    from public.medalhas_obrigatorias_map m;
    return;
  end if;

  return query
  with obrig as (
    select medalha_slug
    from public.medalhas_obrigatorias_map
    where forca = v_forca
  ),
  concedidas as (
    select distinct c.slug as medalha_slug
    from public.medalhas_concedidas mc
    join public.medalhas_catalogo c on c.id = mc.medalha_id
    where mc.recruta_id = p_recruta_id
  )
  select
    (count(*) filter (where o.medalha_slug is not null and d.medalha_slug is null) = 0) as elegivel,
    coalesce(array_agg(o.medalha_slug order by o.medalha_slug) filter (where d.medalha_slug is null), '{}'::text[]) as faltantes
  from obrig o
  left join concedidas d on d.medalha_slug = o.medalha_slug;
end;
$$;


ALTER FUNCTION "public"."verificar_medalhas_obrigatorias"("p_recruta_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_regras_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") RETURNS TABLE("medalha_slug" "text", "elegivel" boolean, "regras_total" integer, "regras_atendidas" integer, "faltantes" "text"[], "detalhes" "jsonb")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_medalha_id uuid;
begin
  select mc.id
    into v_medalha_id
  from public.medalhas_catalogo mc
  where mc.slug = p_medalha_slug
  limit 1;

  if v_medalha_id is null then
    return query
    select
      p_medalha_slug,
      false,
      0,
      0,
      array['MEDALHA_NAO_ENCONTRADA']::text[],
      jsonb_build_array(
        jsonb_build_object(
          'erro', 'MEDALHA_NAO_ENCONTRADA',
          'medalha_slug', p_medalha_slug
        )
      );
    return;
  end if;

  return query
  with regras_raw as (
    select
      mr.id as regra_id,
      mr.tipo_regra,
      mr.parametro,
      mr.comparador,
      mr.ativa,
      mr.metrica,
      mr.valor,
      mr.operador,
      mr.active
    from public.medalha_regras mr
    where mr.medalha_id = v_medalha_id
      and (
        (mr.ativa is true)
        or (mr.ativa is null and mr.active is true)
      )
  ),
  regras_norm as (
    select
      regra_id,
      coalesce(nullif(tipo_regra, ''), nullif(metrica, ''))::text as metrica_norm,
      coalesce(nullif(comparador, ''), nullif(operador, ''))::text as operador_norm,
      case
        when parametro is not null then parametro::numeric
        when valor is not null then valor::numeric
        else null::numeric
      end as valor_esperado
    from regras_raw
  ),

  -- auth_id do recruta (join canônico para ranking_resultados)
  r_auth as (
    select r.auth_id
    from public.recrutas r
    where r.id = p_recruta_id
    limit 1
  ),

  -- ciclo atual (para CICLO_COMPLETO e CICLO_MEDIA_MIN)
  ciclo_atual as (
    select v.ciclo_id
    from public.v_recruta_ciclo_atual v
    where v.recruta_id = p_recruta_id
    limit 1
  ),

  -- CICLO_COMPLETO canônico: existe linha na classificação final para (recruta_id, ciclo_id atual)
  m_ciclo_completo as (
    select
      case
        when exists (
          select 1
          from public.v_classificacao_final_ciclo cfc
          where cfc.recruta_id = p_recruta_id
            and cfc.ciclo_id = (select ciclo_id from ciclo_atual)
        ) then 1::numeric
        else 0::numeric
      end as ciclo_completo_0_1
  ),

  -- CICLO_MEDIA_MIN canônico: score_final da classificação final do ciclo atual
  m_ciclo_media as (
    select
      cfc.score_final::numeric as score_final
    from public.v_classificacao_final_ciclo cfc
    where cfc.recruta_id = p_recruta_id
      and cfc.ciclo_id = (select ciclo_id from ciclo_atual)
    limit 1
  ),

  -- progresso agregado por módulo (por recruta)
  m_progresso as (
    select
      rpm.recruta_id,
      coalesce(sum(rpm.aulas_concluidas), 0)::numeric as aulas_concluidas,
      coalesce(sum(rpm.total_aulas), 0)::numeric as total_aulas,
      coalesce(sum(rpm.revisoes_concluidas), 0)::numeric as revisoes_concluidas,
      coalesce(sum(rpm.total_revisoes), 0)::numeric as total_revisoes,
      count(*) filter (where rpm.concluido is true)::numeric as modulos_concluidos
    from public.recruta_progressos_modulos rpm
    where rpm.recruta_id = p_recruta_id
    group by rpm.recruta_id
  ),

  -- regularidade (0..1) -> engine usa 0..100 conforme decisão
  m_regularidade as (
    select (public.calcular_regularidade_relativa(p_recruta_id) * 100)::numeric as regularidade_0_100
  ),

  -- streak semanal canônica
  m_streak as (
    select coalesce(rcs.semanas_perfeitas_consec, 0)::numeric as semanas_consec
    from public.recruta_ciclo_status rcs
    where rcs.recruta_id = p_recruta_id
    order by rcs.atualizado_em desc nulls last
    limit 1
  ),

  -- IEA canônico: v_iea_atual.iea_score (se NULL -> SEM_DADO)
  m_iea as (
    select v.iea_score::numeric as iea_score
    from public.v_iea_atual v
    where v.recruta_id = p_recruta_id
    order by v.calculado_em desc nulls last
    limit 1
  ),

  -- ranking_resultados (simulado/tag) pelo auth_id; registro mais recente
  m_ranking as (
    select
      rr.media_simulados::numeric as media_simulados,
      case when rr.foi_premiado is true then 1::numeric else 0::numeric end as foi_premiado_0_1
    from public.ranking_resultados rr
    where rr.user_id = (select auth_id from r_auth)
    order by rr.created_at desc nulls last
    limit 1
  ),

  -- FREQUENCIA_DIAS canônico: recruta_status.dias_consecutivos
  m_frequencia as (
    select rs.dias_consecutivos::numeric as dias_consecutivos
    from public.recruta_status rs
    where rs.recruta_id = p_recruta_id
    limit 1
  ),

  -- evidência de ausência de quiz (determinística)
  quiz_stats as (
    select count(*)::int as total_quiz
    from public.v_audit_xp
    where quiz_id is not null
  ),

  avaliacoes as (
    select
      r.regra_id,
      r.metrica_norm as metrica,
      r.operador_norm as operador,
      r.valor_esperado,

      case
        when r.metrica_norm = 'AULAS_CONCLUIDAS_MIN'
          then coalesce((select p.aulas_concluidas from m_progresso p), 0::numeric)

        when r.metrica_norm = 'MODULOS_CONCLUIDOS_MIN'
          then coalesce((select p.modulos_concluidos from m_progresso p), 0::numeric)

        when r.metrica_norm = 'AULAS_CONCLUIDAS_PERCENT'
          then case
            when coalesce((select p.total_aulas from m_progresso p), 0::numeric) = 0 then 0::numeric
            else (select p.aulas_concluidas from m_progresso p) / nullif((select p.total_aulas from m_progresso p), 0::numeric) * 100
          end

        when r.metrica_norm = 'REVISOES_COMPLETAS_PERCENT'
          then case
            when coalesce((select p.total_revisoes from m_progresso p), 0::numeric) = 0 then 0::numeric
            else (select p.revisoes_concluidas from m_progresso p) / nullif((select p.total_revisoes from m_progresso p), 0::numeric) * 100
          end

        when r.metrica_norm = 'REGULARIDADE_MIN'
          then (select regularidade_0_100 from m_regularidade)

        when r.metrica_norm = 'SEMANAS_CONSECUTIVAS'
          then (select semanas_consec from m_streak)

        when r.metrica_norm = 'IEA_MIN'
          then (select iea_score from m_iea)

        when r.metrica_norm = 'SIMULADO_MIN'
          then (select media_simulados from m_ranking)

        when r.metrica_norm = 'TAG_CLASSIFICACAO_PRESENTE'
          then (select foi_premiado_0_1 from m_ranking)

        when r.metrica_norm = 'CICLO_COMPLETO'
          then (select ciclo_completo_0_1 from m_ciclo_completo)

        when r.metrica_norm = 'CICLO_MEDIA_MIN'
          then (select score_final from m_ciclo_media)

        when r.metrica_norm = 'FREQUENCIA_DIAS'
          then (select dias_consecutivos from m_frequencia)

        -- QUIZ: sem fonte hoje
        when r.metrica_norm in ('QUIZ_SCORE_MIN','QUIZ_TENTATIVAS_MAX')
          then null::numeric

        -- ATIVIDADES_NO_PRAZO_PERCENT: sem fonte canônica (sem coluna de prazo/deadline no schema auditado)
        when r.metrica_norm = 'ATIVIDADES_NO_PRAZO_PERCENT'
          then null::numeric

        -- MODULO_MEDIA_MIN: sem fonte canônica de média por módulo no schema auditado
        when r.metrica_norm = 'MODULO_MEDIA_MIN'
          then null::numeric

        else null::numeric
      end as valor_atual,

      case
        when r.metrica_norm = 'AULAS_CONCLUIDAS_MIN' then
          'public.recruta_progressos_modulos.sum(aulas_concluidas)'
        when r.metrica_norm = 'MODULOS_CONCLUIDOS_MIN' then
          'public.recruta_progressos_modulos.count(concluido=true)'
        when r.metrica_norm = 'AULAS_CONCLUIDAS_PERCENT' then
          'public.recruta_progressos_modulos.sum(aulas_concluidas)/sum(total_aulas)*100'
        when r.metrica_norm = 'REVISOES_COMPLETAS_PERCENT' then
          'public.recruta_progressos_modulos.sum(revisoes_concluidas)/sum(total_revisoes)*100'
        when r.metrica_norm = 'REGULARIDADE_MIN' then
          'public.calcular_regularidade_relativa(recruta_id)*100'
        when r.metrica_norm = 'SEMANAS_CONSECUTIVAS' then
          'public.recruta_ciclo_status.semanas_perfeitas_consec'
        when r.metrica_norm = 'IEA_MIN' then
          'public.v_iea_atual.iea_score'
        when r.metrica_norm = 'SIMULADO_MIN' then
          'public.ranking_resultados.media_simulados (último por recrutas.auth_id=user_id)'
        when r.metrica_norm = 'TAG_CLASSIFICACAO_PRESENTE' then
          'public.ranking_resultados.foi_premiado (último por recrutas.auth_id=user_id)'
        when r.metrica_norm = 'CICLO_COMPLETO' then
          'exists public.v_classificacao_final_ciclo(recruta_id,ciclo_id) com ciclo_id de public.v_recruta_ciclo_atual'
        when r.metrica_norm = 'CICLO_MEDIA_MIN' then
          'public.v_classificacao_final_ciclo.score_final (para ciclo_id de public.v_recruta_ciclo_atual)'
        when r.metrica_norm = 'FREQUENCIA_DIAS' then
          'public.recruta_status.dias_consecutivos'
        when r.metrica_norm in ('QUIZ_SCORE_MIN','QUIZ_TENTATIVAS_MAX') then
          'public.v_audit_xp (quiz_id is null em 100% dos casos)'
        when r.metrica_norm = 'ATIVIDADES_NO_PRAZO_PERCENT' then
          'SEM_FONTE: sem coluna de prazo/deadline no schema auditado (%prazo% retornou 0 linhas)'
        when r.metrica_norm = 'MODULO_MEDIA_MIN' then
          'SEM_FONTE: schema auditado só indica media_simulados e views de mídia (media_url/media_type)'
        else null::text
      end as fonte,

      case
        when r.metrica_norm is null or r.metrica_norm = '' then 'REGRA_SEM_METRICA'
        when r.valor_esperado is null then 'REGRA_SEM_PARAMETRO'
        when r.operador_norm not in ('>=','<=','=') then 'OPERADOR_NAO_SUPORTADO'

        when r.metrica_norm in ('QUIZ_SCORE_MIN','QUIZ_TENTATIVAS_MAX') then
          'FONTE_NAO_MAPEADA'

        when r.metrica_norm in ('ATIVIDADES_NO_PRAZO_PERCENT','MODULO_MEDIA_MIN') then
          'FONTE_NAO_MAPEADA'

        when (
          r.metrica_norm not in (
            'AULAS_CONCLUIDAS_MIN',
            'MODULOS_CONCLUIDOS_MIN',
            'AULAS_CONCLUIDAS_PERCENT',
            'REVISOES_COMPLETAS_PERCENT',
            'REGULARIDADE_MIN',
            'SEMANAS_CONSECUTIVAS',
            'IEA_MIN',
            'SIMULADO_MIN',
            'TAG_CLASSIFICACAO_PRESENTE',
            'CICLO_COMPLETO',
            'CICLO_MEDIA_MIN',
            'FREQUENCIA_DIAS',
            'QUIZ_SCORE_MIN',
            'QUIZ_TENTATIVAS_MAX',
            'ATIVIDADES_NO_PRAZO_PERCENT',
            'MODULO_MEDIA_MIN'
          )
        ) then
          'FONTE_NAO_MAPEADA'

        -- SEM_DADO específicos
        when r.metrica_norm = 'IEA_MIN' and (select iea_score from m_iea) is null then
          'SEM_DADO'

        when r.metrica_norm in ('SIMULADO_MIN','TAG_CLASSIFICACAO_PRESENTE') and not exists (select 1 from m_ranking) then
          'SEM_DADO'

        when r.metrica_norm = 'CICLO_COMPLETO' and (select ciclo_id from ciclo_atual) is null then
          'SEM_DADO'

        when r.metrica_norm = 'CICLO_MEDIA_MIN' and (
          (select ciclo_id from ciclo_atual) is null
          or (select score_final from m_ciclo_media) is null
        ) then
          'SEM_DADO'

        when r.metrica_norm = 'FREQUENCIA_DIAS' and (select dias_consecutivos from m_frequencia) is null then
          'SEM_DADO'

        else null::text
      end as motivo
    from regras_norm r
  ),

  resultados as (
    select
      a.*,
      case
        when a.motivo = 'FONTE_NAO_MAPEADA' then false
        when a.motivo is not null then null::boolean
        when a.valor_atual is null then null::boolean
        when a.valor_esperado is null then null::boolean
        when a.operador = '>=' then (a.valor_atual >= a.valor_esperado)
        when a.operador = '<=' then (a.valor_atual <= a.valor_esperado)
        when a.operador = '='  then (a.valor_atual =  a.valor_esperado)
        else null::boolean
      end as passou
    from avaliacoes a
  ),

  agregados as (
    select
      count(*)::int as regras_total,
      count(*) filter (where passou is true)::int as regras_atendidas,
      array_agg(
        case
          when motivo = 'FONTE_NAO_MAPEADA' then ('FONTE_NAO_MAPEADA:' || metrica)
          when motivo = 'SEM_DADO' then ('SEM_DADO:' || metrica)
          else metrica
        end
        order by metrica
      ) filter (where passou is not true) as faltantes,
      jsonb_agg(
        jsonb_build_object(
          'metrica', metrica,
          'valor_atual', valor_atual,
          'operador', operador,
          'valor_esperado', valor_esperado,
          'passou', passou,
          'fonte', fonte,
          'motivo', motivo,
          'quiz_total', (select total_quiz from quiz_stats)
        )
        order by metrica
      ) as detalhes
    from resultados
  )

  select
    p_medalha_slug as medalha_slug,
    (
      (select a.regras_total from agregados a) = (select a.regras_atendidas from agregados a)
      and coalesce(array_length((select a.faltantes from agregados a), 1), 0) = 0
    ) as elegivel,
    (select a.regras_total from agregados a) as regras_total,
    (select a.regras_atendidas from agregados a) as regras_atendidas,
    coalesce((select a.faltantes from agregados a), array[]::text[]) as faltantes,
    coalesce((select a.detalhes from agregados a), '[]'::jsonb) as detalhes;

end;
$$;


ALTER FUNCTION "public"."verificar_regras_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."verificar_regras_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") IS 'C7.1 Engine read-only determinística. Fontes fechadas: recruta_progressos_modulos (aulas/módulos/revisões), calcular_regularidade_relativa()*100 (regularidade), recruta_ciclo_status.semanas_perfeitas_consec (streak), v_iea_atual.iea_score (IEA). Métricas sem fonte retornam FONTE_NAO_MAPEADA:<METRICA>.';



CREATE OR REPLACE FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


ALTER FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."allow_only_operation"("expected_operation" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


ALTER FUNCTION "storage"."allow_only_operation"("expected_operation" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_name_length"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION "storage"."enforce_bucket_name_length"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."extension"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Get the last path segment (the actual filename)
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    -- Extract extension: reverse, split on '.', then reverse again
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION "storage"."extension"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."filename"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION "storage"."filename"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."foldername"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION "storage"."foldername"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


ALTER FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_size_by_bucket"() RETURNS TABLE("size" bigint, "bucket_id" "text")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint)::bigint as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION "storage"."get_size_by_bucket"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "next_key_token" "text" DEFAULT ''::"text", "next_upload_token" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "id" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "next_key_token" "text", "next_upload_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "start_after" "text" DEFAULT ''::"text", "next_token" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "metadata" "jsonb", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "start_after" "text", "next_token" "text", "sort_order" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."operation"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION "storage"."operation"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."protect_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."protect_delete"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach (unchanged)
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT path_tokens[$1] AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $2 || '%%'
                  AND bucket_id = $3
                  AND array_length(objects.path_tokens, 1) <> $1
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT path_tokens[$1] AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $2 || '%%'
               AND bucket_id = $3
               AND array_length(objects.path_tokens, 1) = $1
             ORDER BY %I %s)
            LIMIT $4 OFFSET $5
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := split_part(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter), v_delimiter, levels);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := split_part(v_current.name, v_delimiter, levels);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    IF p_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        p_sort_column,
        v_cursor_op,
        p_sort_column,
        p_sort_order,
        p_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


ALTER FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "start_after" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text", "sort_column" "text" DEFAULT 'name'::"text", "sort_column_after" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


ALTER FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer, "levels" integer, "start_after" "text", "sort_order" "text", "sort_column" "text", "sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION "storage"."update_updated_at_column"() OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "public"."ciclos_formativos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "forca" "text" NOT NULL,
    "codigo" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "data_inicio" "date" NOT NULL,
    "data_fim" "date" NOT NULL,
    "semanas_total" integer NOT NULL,
    "vigente" boolean DEFAULT false NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ciclos_formativos_semanas_total_check" CHECK (("semanas_total" > 0))
);


ALTER TABLE "public"."ciclos_formativos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."iea_snapshots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "ciclo_id" "uuid",
    "iea_score" integer NOT NULL,
    "conceito" "text" NOT NULL,
    "componentes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "calculado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "iea_snapshots_iea_score_check" CHECK ((("iea_score" >= 0) AND ("iea_score" <= 100)))
);


ALTER TABLE "public"."iea_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_status" (
    "recruta_id" "uuid" NOT NULL,
    "nivel" integer DEFAULT 1 NOT NULL,
    "xp" integer DEFAULT 0 NOT NULL,
    "ultima_atividade" "date",
    "dias_consecutivos" integer DEFAULT 0,
    "honra_maxima" boolean DEFAULT false,
    "atualizado_em" timestamp with time zone DEFAULT "now"(),
    "patente" "text" DEFAULT 'ASPIRANTE'::"text" NOT NULL
);


ALTER TABLE "public"."recruta_status" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recrutas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "auth_id" "uuid" NOT NULL,
    "nome" "text",
    "email" "text" NOT NULL,
    "forca" "text" NOT NULL,
    "patente" "text" DEFAULT 'Recruta'::"text",
    "plano" "text",
    "status" "text" DEFAULT 'ativo'::"text",
    "data_pagamento" timestamp without time zone,
    "validade" timestamp without time zone,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "onboarding_concluido" boolean DEFAULT false,
    "patente_virtual" "text" DEFAULT 'Recruta'::"text",
    "thread_id" "text",
    "nome_guerra" "text",
    "instructor_profile_id" "text",
    CONSTRAINT "chk_forca_valida" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "recrutas_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"])))
);

ALTER TABLE ONLY "public"."recrutas" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."recrutas" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_recruta_ciclo_atual" AS
 SELECT "r"."id" AS "recruta_id",
    "cf"."id" AS "ciclo_id",
    "cf"."forca",
    "cf"."codigo",
    "cf"."titulo",
    "cf"."data_inicio",
    "cf"."data_fim",
    "cf"."semanas_total",
    "cf"."vigente"
   FROM ("public"."recrutas" "r"
     JOIN "public"."ciclos_formativos" "cf" ON ((("cf"."forca" = "r"."forca") AND ("cf"."vigente" = true))))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_recruta_ciclo_atual" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_recruta_ciclo_atual" IS 'Ciclo vigente do recruta autenticado (contrato preservado).';



CREATE OR REPLACE VIEW "public"."v_iea_atual" AS
 WITH "me" AS (
         SELECT "r"."id" AS "recruta_id"
           FROM "public"."recrutas" "r"
          WHERE ("r"."auth_id" = "auth"."uid"())
         LIMIT 1
        ), "ciclo" AS (
         SELECT "vrca"."recruta_id",
            "vrca"."ciclo_id"
           FROM ("public"."v_recruta_ciclo_atual" "vrca"
             JOIN "me" ON (("me"."recruta_id" = "vrca"."recruta_id")))
         LIMIT 1
        ), "prefer" AS (
         SELECT "s"."id",
            "s"."recruta_id",
            "s"."ciclo_id",
            "s"."iea_score",
            "s"."conceito",
            "s"."componentes",
            "s"."calculado_em"
           FROM (("public"."iea_snapshots" "s"
             JOIN "me" ON (("me"."recruta_id" = "s"."recruta_id")))
             LEFT JOIN "ciclo" "c" ON (("c"."recruta_id" = "s"."recruta_id")))
          WHERE (("c"."ciclo_id" IS NOT NULL) AND (NOT ("s"."ciclo_id" IS DISTINCT FROM "c"."ciclo_id")))
          ORDER BY "s"."calculado_em" DESC
         LIMIT 1
        ), "fallback" AS (
         SELECT "s"."id",
            "s"."recruta_id",
            "s"."ciclo_id",
            "s"."iea_score",
            "s"."conceito",
            "s"."componentes",
            "s"."calculado_em"
           FROM ("public"."iea_snapshots" "s"
             JOIN "me" ON (("me"."recruta_id" = "s"."recruta_id")))
          ORDER BY "s"."calculado_em" DESC
         LIMIT 1
        )
 SELECT COALESCE("p"."recruta_id", "f"."recruta_id") AS "recruta_id",
    COALESCE("p"."ciclo_id", "f"."ciclo_id") AS "ciclo_id",
    COALESCE("p"."iea_score", "f"."iea_score") AS "iea_score",
    COALESCE("p"."conceito", "f"."conceito") AS "conceito",
    COALESCE("p"."calculado_em", "f"."calculado_em") AS "calculado_em",
    (COALESCE("p"."calculado_em", "f"."calculado_em") AT TIME ZONE 'America/Sao_Paulo'::"text") AS "calculado_em_br"
   FROM ("prefer" "p"
     FULL JOIN "fallback" "f" ON (true))
  WHERE (("p"."id" IS NOT NULL) OR ("f"."id" IS NOT NULL));


ALTER VIEW "public"."v_iea_atual" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "auth"."audit_log_entries" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "payload" json,
    "created_at" timestamp with time zone,
    "ip_address" character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE "auth"."audit_log_entries" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."audit_log_entries" IS 'Auth: Audit trail for user actions.';



CREATE TABLE IF NOT EXISTS "auth"."custom_oauth_providers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "provider_type" "text" NOT NULL,
    "identifier" "text" NOT NULL,
    "name" "text" NOT NULL,
    "client_id" "text" NOT NULL,
    "client_secret" "text" NOT NULL,
    "acceptable_client_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "scopes" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "pkce_enabled" boolean DEFAULT true NOT NULL,
    "attribute_mapping" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "authorization_params" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "email_optional" boolean DEFAULT false NOT NULL,
    "issuer" "text",
    "discovery_url" "text",
    "skip_nonce_check" boolean DEFAULT false NOT NULL,
    "cached_discovery" "jsonb",
    "discovery_cached_at" timestamp with time zone,
    "authorization_url" "text",
    "token_url" "text",
    "userinfo_url" "text",
    "jwks_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "custom_oauth_providers_authorization_url_https" CHECK ((("authorization_url" IS NULL) OR ("authorization_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_authorization_url_length" CHECK ((("authorization_url" IS NULL) OR ("char_length"("authorization_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_client_id_length" CHECK ((("char_length"("client_id") >= 1) AND ("char_length"("client_id") <= 512))),
    CONSTRAINT "custom_oauth_providers_discovery_url_length" CHECK ((("discovery_url" IS NULL) OR ("char_length"("discovery_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_identifier_format" CHECK (("identifier" ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::"text")),
    CONSTRAINT "custom_oauth_providers_issuer_length" CHECK ((("issuer" IS NULL) OR (("char_length"("issuer") >= 1) AND ("char_length"("issuer") <= 2048)))),
    CONSTRAINT "custom_oauth_providers_jwks_uri_https" CHECK ((("jwks_uri" IS NULL) OR ("jwks_uri" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_jwks_uri_length" CHECK ((("jwks_uri" IS NULL) OR ("char_length"("jwks_uri") <= 2048))),
    CONSTRAINT "custom_oauth_providers_name_length" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 100))),
    CONSTRAINT "custom_oauth_providers_oauth2_requires_endpoints" CHECK ((("provider_type" <> 'oauth2'::"text") OR (("authorization_url" IS NOT NULL) AND ("token_url" IS NOT NULL) AND ("userinfo_url" IS NOT NULL)))),
    CONSTRAINT "custom_oauth_providers_oidc_discovery_url_https" CHECK ((("provider_type" <> 'oidc'::"text") OR ("discovery_url" IS NULL) OR ("discovery_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_oidc_issuer_https" CHECK ((("provider_type" <> 'oidc'::"text") OR ("issuer" IS NULL) OR ("issuer" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_oidc_requires_issuer" CHECK ((("provider_type" <> 'oidc'::"text") OR ("issuer" IS NOT NULL))),
    CONSTRAINT "custom_oauth_providers_provider_type_check" CHECK (("provider_type" = ANY (ARRAY['oauth2'::"text", 'oidc'::"text"]))),
    CONSTRAINT "custom_oauth_providers_token_url_https" CHECK ((("token_url" IS NULL) OR ("token_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_token_url_length" CHECK ((("token_url" IS NULL) OR ("char_length"("token_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_userinfo_url_https" CHECK ((("userinfo_url" IS NULL) OR ("userinfo_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_userinfo_url_length" CHECK ((("userinfo_url" IS NULL) OR ("char_length"("userinfo_url") <= 2048)))
);


ALTER TABLE "auth"."custom_oauth_providers" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."flow_state" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid",
    "auth_code" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "code_challenge" "text",
    "provider_type" "text" NOT NULL,
    "provider_access_token" "text",
    "provider_refresh_token" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "authentication_method" "text" NOT NULL,
    "auth_code_issued_at" timestamp with time zone,
    "invite_token" "text",
    "referrer" "text",
    "oauth_client_state_id" "uuid",
    "linking_target_id" "uuid",
    "email_optional" boolean DEFAULT false NOT NULL
);


ALTER TABLE "auth"."flow_state" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."flow_state" IS 'Stores metadata for all OAuth/SSO login flows';



CREATE TABLE IF NOT EXISTS "auth"."identities" (
    "provider_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "identity_data" "jsonb" NOT NULL,
    "provider" "text" NOT NULL,
    "last_sign_in_at" timestamp with time zone,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "email" "text" GENERATED ALWAYS AS ("lower"(("identity_data" ->> 'email'::"text"))) STORED,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "auth"."identities" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."identities" IS 'Auth: Stores identities associated to a user.';



COMMENT ON COLUMN "auth"."identities"."email" IS 'Auth: Email is a generated column that references the optional email property in the identity_data';



CREATE TABLE IF NOT EXISTS "auth"."instances" (
    "id" "uuid" NOT NULL,
    "uuid" "uuid",
    "raw_base_config" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "auth"."instances" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."instances" IS 'Auth: Manages users across multiple sites.';



CREATE TABLE IF NOT EXISTS "auth"."mfa_amr_claims" (
    "session_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "authentication_method" "text" NOT NULL,
    "id" "uuid" NOT NULL
);


ALTER TABLE "auth"."mfa_amr_claims" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_amr_claims" IS 'auth: stores authenticator method reference claims for multi factor authentication';



CREATE TABLE IF NOT EXISTS "auth"."mfa_challenges" (
    "id" "uuid" NOT NULL,
    "factor_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "verified_at" timestamp with time zone,
    "ip_address" "inet" NOT NULL,
    "otp_code" "text",
    "web_authn_session_data" "jsonb"
);


ALTER TABLE "auth"."mfa_challenges" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_challenges" IS 'auth: stores metadata about challenge requests made';



CREATE TABLE IF NOT EXISTS "auth"."mfa_factors" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "friendly_name" "text",
    "factor_type" "auth"."factor_type" NOT NULL,
    "status" "auth"."factor_status" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "secret" "text",
    "phone" "text",
    "last_challenged_at" timestamp with time zone,
    "web_authn_credential" "jsonb",
    "web_authn_aaguid" "uuid",
    "last_webauthn_challenge_data" "jsonb"
);


ALTER TABLE "auth"."mfa_factors" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_factors" IS 'auth: stores metadata about factors';



COMMENT ON COLUMN "auth"."mfa_factors"."last_webauthn_challenge_data" IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';



CREATE TABLE IF NOT EXISTS "auth"."oauth_authorizations" (
    "id" "uuid" NOT NULL,
    "authorization_id" "text" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "redirect_uri" "text" NOT NULL,
    "scope" "text" NOT NULL,
    "state" "text",
    "resource" "text",
    "code_challenge" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "response_type" "auth"."oauth_response_type" DEFAULT 'code'::"auth"."oauth_response_type" NOT NULL,
    "status" "auth"."oauth_authorization_status" DEFAULT 'pending'::"auth"."oauth_authorization_status" NOT NULL,
    "authorization_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '00:03:00'::interval) NOT NULL,
    "approved_at" timestamp with time zone,
    "nonce" "text",
    CONSTRAINT "oauth_authorizations_authorization_code_length" CHECK (("char_length"("authorization_code") <= 255)),
    CONSTRAINT "oauth_authorizations_code_challenge_length" CHECK (("char_length"("code_challenge") <= 128)),
    CONSTRAINT "oauth_authorizations_expires_at_future" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "oauth_authorizations_nonce_length" CHECK (("char_length"("nonce") <= 255)),
    CONSTRAINT "oauth_authorizations_redirect_uri_length" CHECK (("char_length"("redirect_uri") <= 2048)),
    CONSTRAINT "oauth_authorizations_resource_length" CHECK (("char_length"("resource") <= 2048)),
    CONSTRAINT "oauth_authorizations_scope_length" CHECK (("char_length"("scope") <= 4096)),
    CONSTRAINT "oauth_authorizations_state_length" CHECK (("char_length"("state") <= 4096))
);


ALTER TABLE "auth"."oauth_authorizations" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_client_states" (
    "id" "uuid" NOT NULL,
    "provider_type" "text" NOT NULL,
    "code_verifier" "text",
    "created_at" timestamp with time zone NOT NULL
);


ALTER TABLE "auth"."oauth_client_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."oauth_client_states" IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';



CREATE TABLE IF NOT EXISTS "auth"."oauth_clients" (
    "id" "uuid" NOT NULL,
    "client_secret_hash" "text",
    "registration_type" "auth"."oauth_registration_type" NOT NULL,
    "redirect_uris" "text" NOT NULL,
    "grant_types" "text" NOT NULL,
    "client_name" "text",
    "client_uri" "text",
    "logo_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "client_type" "auth"."oauth_client_type" DEFAULT 'confidential'::"auth"."oauth_client_type" NOT NULL,
    "token_endpoint_auth_method" "text" NOT NULL,
    CONSTRAINT "oauth_clients_client_name_length" CHECK (("char_length"("client_name") <= 1024)),
    CONSTRAINT "oauth_clients_client_uri_length" CHECK (("char_length"("client_uri") <= 2048)),
    CONSTRAINT "oauth_clients_logo_uri_length" CHECK (("char_length"("logo_uri") <= 2048)),
    CONSTRAINT "oauth_clients_token_endpoint_auth_method_check" CHECK (("token_endpoint_auth_method" = ANY (ARRAY['client_secret_basic'::"text", 'client_secret_post'::"text", 'none'::"text"])))
);


ALTER TABLE "auth"."oauth_clients" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_consents" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "scopes" "text" NOT NULL,
    "granted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    CONSTRAINT "oauth_consents_revoked_after_granted" CHECK ((("revoked_at" IS NULL) OR ("revoked_at" >= "granted_at"))),
    CONSTRAINT "oauth_consents_scopes_length" CHECK (("char_length"("scopes") <= 2048)),
    CONSTRAINT "oauth_consents_scopes_not_empty" CHECK (("char_length"(TRIM(BOTH FROM "scopes")) > 0))
);


ALTER TABLE "auth"."oauth_consents" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."one_time_tokens" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token_type" "auth"."one_time_token_type" NOT NULL,
    "token_hash" "text" NOT NULL,
    "relates_to" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "one_time_tokens_token_hash_check" CHECK (("char_length"("token_hash") > 0))
);


ALTER TABLE "auth"."one_time_tokens" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."refresh_tokens" (
    "instance_id" "uuid",
    "id" bigint NOT NULL,
    "token" character varying(255),
    "user_id" character varying(255),
    "revoked" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "parent" character varying(255),
    "session_id" "uuid"
);


ALTER TABLE "auth"."refresh_tokens" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."refresh_tokens" IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';



CREATE SEQUENCE IF NOT EXISTS "auth"."refresh_tokens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNER TO "supabase_auth_admin";


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNED BY "auth"."refresh_tokens"."id";



CREATE TABLE IF NOT EXISTS "auth"."saml_providers" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "entity_id" "text" NOT NULL,
    "metadata_xml" "text" NOT NULL,
    "metadata_url" "text",
    "attribute_mapping" "jsonb",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "name_id_format" "text",
    CONSTRAINT "entity_id not empty" CHECK (("char_length"("entity_id") > 0)),
    CONSTRAINT "metadata_url not empty" CHECK ((("metadata_url" = NULL::"text") OR ("char_length"("metadata_url") > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK (("char_length"("metadata_xml") > 0))
);


ALTER TABLE "auth"."saml_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_providers" IS 'Auth: Manages SAML Identity Provider connections.';



CREATE TABLE IF NOT EXISTS "auth"."saml_relay_states" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "request_id" "text" NOT NULL,
    "for_email" "text",
    "redirect_to" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "flow_state_id" "uuid",
    CONSTRAINT "request_id not empty" CHECK (("char_length"("request_id") > 0))
);


ALTER TABLE "auth"."saml_relay_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_relay_states" IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';



CREATE TABLE IF NOT EXISTS "auth"."schema_migrations" (
    "version" character varying(255) NOT NULL
);


ALTER TABLE "auth"."schema_migrations" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."schema_migrations" IS 'Auth: Manages updates to the auth system.';



CREATE TABLE IF NOT EXISTS "auth"."sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "factor_id" "uuid",
    "aal" "auth"."aal_level",
    "not_after" timestamp with time zone,
    "refreshed_at" timestamp without time zone,
    "user_agent" "text",
    "ip" "inet",
    "tag" "text",
    "oauth_client_id" "uuid",
    "refresh_token_hmac_key" "text",
    "refresh_token_counter" bigint,
    "scopes" "text",
    CONSTRAINT "sessions_scopes_length" CHECK (("char_length"("scopes") <= 4096))
);


ALTER TABLE "auth"."sessions" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sessions" IS 'Auth: Stores session data associated to a user.';



COMMENT ON COLUMN "auth"."sessions"."not_after" IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_hmac_key" IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_counter" IS 'Holds the ID (counter) of the last issued refresh token.';



CREATE TABLE IF NOT EXISTS "auth"."sso_domains" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "domain" "text" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK (("char_length"("domain") > 0))
);


ALTER TABLE "auth"."sso_domains" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_domains" IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';



CREATE TABLE IF NOT EXISTS "auth"."sso_providers" (
    "id" "uuid" NOT NULL,
    "resource_id" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "disabled" boolean,
    CONSTRAINT "resource_id not empty" CHECK ((("resource_id" = NULL::"text") OR ("char_length"("resource_id") > 0)))
);


ALTER TABLE "auth"."sso_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_providers" IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';



COMMENT ON COLUMN "auth"."sso_providers"."resource_id" IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';



CREATE TABLE IF NOT EXISTS "auth"."users" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "aud" character varying(255),
    "role" character varying(255),
    "email" character varying(255),
    "encrypted_password" character varying(255),
    "email_confirmed_at" timestamp with time zone,
    "invited_at" timestamp with time zone,
    "confirmation_token" character varying(255),
    "confirmation_sent_at" timestamp with time zone,
    "recovery_token" character varying(255),
    "recovery_sent_at" timestamp with time zone,
    "email_change_token_new" character varying(255),
    "email_change" character varying(255),
    "email_change_sent_at" timestamp with time zone,
    "last_sign_in_at" timestamp with time zone,
    "raw_app_meta_data" "jsonb",
    "raw_user_meta_data" "jsonb",
    "is_super_admin" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "phone" "text" DEFAULT NULL::character varying,
    "phone_confirmed_at" timestamp with time zone,
    "phone_change" "text" DEFAULT ''::character varying,
    "phone_change_token" character varying(255) DEFAULT ''::character varying,
    "phone_change_sent_at" timestamp with time zone,
    "confirmed_at" timestamp with time zone GENERATED ALWAYS AS (LEAST("email_confirmed_at", "phone_confirmed_at")) STORED,
    "email_change_token_current" character varying(255) DEFAULT ''::character varying,
    "email_change_confirm_status" smallint DEFAULT 0,
    "banned_until" timestamp with time zone,
    "reauthentication_token" character varying(255) DEFAULT ''::character varying,
    "reauthentication_sent_at" timestamp with time zone,
    "is_sso_user" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "is_anonymous" boolean DEFAULT false NOT NULL,
    CONSTRAINT "users_email_change_confirm_status_check" CHECK ((("email_change_confirm_status" >= 0) AND ("email_change_confirm_status" <= 2)))
);


ALTER TABLE "auth"."users" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."users" IS 'Auth: Stores user login data within a secure schema.';



COMMENT ON COLUMN "auth"."users"."is_sso_user" IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';



CREATE TABLE IF NOT EXISTS "auth"."webauthn_challenges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "challenge_type" "text" NOT NULL,
    "session_data" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    CONSTRAINT "webauthn_challenges_challenge_type_check" CHECK (("challenge_type" = ANY (ARRAY['signup'::"text", 'registration'::"text", 'authentication'::"text"])))
);


ALTER TABLE "auth"."webauthn_challenges" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."webauthn_credentials" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "credential_id" "bytea" NOT NULL,
    "public_key" "bytea" NOT NULL,
    "attestation_type" "text" DEFAULT ''::"text" NOT NULL,
    "aaguid" "uuid",
    "sign_count" bigint DEFAULT 0 NOT NULL,
    "transports" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "backup_eligible" boolean DEFAULT false NOT NULL,
    "backed_up" boolean DEFAULT false NOT NULL,
    "friendly_name" "text" DEFAULT ''::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_used_at" timestamp with time zone
);


ALTER TABLE "auth"."webauthn_credentials" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "public"."_qd_migration_snapshots" (
    "migration_id" "text" NOT NULL,
    "applied_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "snapshot" "jsonb" NOT NULL
);


ALTER TABLE "public"."_qd_migration_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."atividade_academica_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "ciclo_id" "uuid",
    "tipo" "text" NOT NULL,
    "ref_id" "uuid",
    "registrado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."atividade_academica_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."aula_pipeline_execucoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "aula_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'running'::"text" NOT NULL,
    "etapa_atual" "text" DEFAULT 'AuditorConteudo'::"text" NOT NULL,
    "pipeline_versao" "text" DEFAULT 'v1'::"text" NOT NULL,
    "last_error" "text",
    "last_error_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "aula_pipeline_execucoes_etapa_atual_check" CHECK (("etapa_atual" = ANY (ARRAY['AuditorConteudo'::"text", 'ComplementadorTecnico'::"text", 'Roteirista'::"text", 'EditorTextoComplementar'::"text", 'DesignerQuiz'::"text", 'RevisorInstitucional'::"text"]))),
    CONSTRAINT "aula_pipeline_execucoes_status_check" CHECK (("status" = ANY (ARRAY['running'::"text", 'completed'::"text", 'error'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."aula_pipeline_execucoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."aula_pipeline_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "execucao_id" "uuid" NOT NULL,
    "agente" "text" NOT NULL,
    "etapa_ordem" integer NOT NULL,
    "payload_json" "jsonb" NOT NULL,
    "payload_hash" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "aula_pipeline_logs_agente_check" CHECK (("agente" = ANY (ARRAY['AuditorConteudo'::"text", 'ComplementadorTecnico'::"text", 'Roteirista'::"text", 'EditorTextoComplementar'::"text", 'DesignerQuiz'::"text", 'RevisorInstitucional'::"text"]))),
    CONSTRAINT "aula_pipeline_logs_etapa_ordem_check" CHECK ((("etapa_ordem" >= 1) AND ("etapa_ordem" <= 6)))
);


ALTER TABLE "public"."aula_pipeline_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."aulas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "modulo_id" "uuid" NOT NULL,
    "titulo" "text" NOT NULL,
    "ordem" integer NOT NULL,
    "xp_valor" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "video_url" "text",
    "pdf_url" "text"
);


ALTER TABLE "public"."aulas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."aulas_concluidas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "aula_id" "uuid" NOT NULL,
    "data_conclusao" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."aulas_concluidas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."auth_client_revocations" (
    "id" bigint NOT NULL,
    "auth_id" "uuid" NOT NULL,
    "revoked_client_instance_id" "text" NOT NULL,
    "revoked_reason" "text" NOT NULL,
    "new_client_instance_id" "text" NOT NULL,
    "revoked_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "auth_client_revocations_reason_chk" CHECK (("revoked_reason" = ANY (ARRAY['none'::"text", 'user_action'::"text", 'session_expired'::"text", 'security_logout'::"text"])))
);


ALTER TABLE "public"."auth_client_revocations" OWNER TO "postgres";


COMMENT ON TABLE "public"."auth_client_revocations" IS 'Histórico append-only de revogações institucionais por client_instance_id.';



CREATE SEQUENCE IF NOT EXISTS "public"."auth_client_revocations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."auth_client_revocations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."auth_client_revocations_id_seq" OWNED BY "public"."auth_client_revocations"."id";



CREATE TABLE IF NOT EXISTS "public"."auth_client_singleton" (
    "auth_id" "uuid" NOT NULL,
    "current_client_instance_id" "text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."auth_client_singleton" OWNER TO "postgres";


COMMENT ON TABLE "public"."auth_client_singleton" IS 'Cliente/instalação atualmente autorizado para a conta. Fonte autoritativa de observabilidade de sessão única.';



CREATE TABLE IF NOT EXISTS "public"."auth_session_revocations" (
    "id" bigint NOT NULL,
    "auth_id" "uuid" NOT NULL,
    "revoked_jti" "text" NOT NULL,
    "revoked_reason" "text" NOT NULL,
    "revoked_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "new_jti" "text" NOT NULL,
    CONSTRAINT "auth_session_revocations_reason_chk" CHECK (("revoked_reason" = ANY (ARRAY['none'::"text", 'user_action'::"text", 'session_expired'::"text", 'security_logout'::"text"])))
);


ALTER TABLE "public"."auth_session_revocations" OWNER TO "postgres";


COMMENT ON TABLE "public"."auth_session_revocations" IS 'Log append-only de revogações de sessão (auditoria).';



CREATE SEQUENCE IF NOT EXISTS "public"."auth_session_revocations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."auth_session_revocations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."auth_session_revocations_id_seq" OWNED BY "public"."auth_session_revocations"."id";



CREATE TABLE IF NOT EXISTS "public"."auth_session_singleton" (
    "auth_id" "uuid" NOT NULL,
    "current_jti" "text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."auth_session_singleton" OWNER TO "postgres";


COMMENT ON TABLE "public"."auth_session_singleton" IS 'Sessão vigente (jti) por conta. Base para regra de sessão única e para session_revoked_reason.';



CREATE TABLE IF NOT EXISTS "public"."automacoes_execucoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "workflow" "text" NOT NULL,
    "correlation_id" "text" NOT NULL,
    "evento_id" "uuid",
    "status" "text" NOT NULL,
    "error" "jsonb",
    "meta" "jsonb"
);


ALTER TABLE "public"."automacoes_execucoes" OWNER TO "postgres";


COMMENT ON TABLE "public"."automacoes_execucoes" IS 'Observabilidade mínima de execuções (n8n/rotinas). Referencia evento quando aplicável.';



CREATE TABLE IF NOT EXISTS "public"."billing_assinaturas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "gateway_cliente_id" "text",
    "gateway_assinatura_id" "text",
    "plano" "text" NOT NULL,
    "status_assinatura" "text" NOT NULL,
    "trial_inicio" timestamp with time zone,
    "trial_fim" timestamp with time zone,
    "vigente_inicio" timestamp with time zone,
    "vigente_fim" timestamp with time zone,
    "auto_renovacao" boolean DEFAULT false NOT NULL,
    "origem" "text" DEFAULT 'billing'::"text" NOT NULL,
    "ultimo_gateway_event_id" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_assinaturas_status_chk" CHECK (("status_assinatura" = ANY (ARRAY['trial'::"text", 'ativa'::"text", 'inadimplente'::"text", 'cancelada'::"text", 'expirada'::"text", 'suspensa'::"text", 'pendente'::"text"])))
);


ALTER TABLE "public"."billing_assinaturas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "gateway_nome" "text",
    "gateway_event_id" "text",
    "event_type" "text",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."billing_eventos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_notificacoes_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid",
    "assinatura_id" "uuid",
    "pagamento_id" "uuid",
    "tipo_evento" "text" NOT NULL,
    "canal" "text" NOT NULL,
    "destinatario" "text",
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enviado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status_envio" "text" DEFAULT 'pendente'::"text" NOT NULL,
    "erro" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_notificacoes_log_status_chk" CHECK (("status_envio" = ANY (ARRAY['pendente'::"text", 'enviado'::"text", 'falhou'::"text", 'ignorado'::"text"])))
);


ALTER TABLE "public"."billing_notificacoes_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_pagamentos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "assinatura_id" "uuid",
    "gateway_nome" "text" DEFAULT 'n8n'::"text" NOT NULL,
    "gateway_event_id" "text" NOT NULL,
    "gateway_pagamento_id" "text",
    "status_pagamento" "text" NOT NULL,
    "valor_centavos" bigint NOT NULL,
    "moeda" "text" DEFAULT 'BRL'::"text" NOT NULL,
    "plano_referenciado" "text",
    "competencia_inicio" timestamp with time zone,
    "competencia_fim" timestamp with time zone,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "processado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_pagamentos_status_chk" CHECK (("status_pagamento" = ANY (ARRAY['recebido'::"text", 'confirmado'::"text", 'falhou'::"text", 'estornado'::"text", 'cancelado'::"text", 'pendente'::"text"]))),
    CONSTRAINT "billing_pagamentos_valor_chk" CHECK (("valor_centavos" >= 0))
);


ALTER TABLE "public"."billing_pagamentos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_reconciliacao" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "gateway_nome" "text" DEFAULT 'interno'::"text" NOT NULL,
    "gateway_event_id" "text",
    "recruta_id" "uuid",
    "assinatura_id" "uuid",
    "pagamento_id" "uuid",
    "acao" "text" NOT NULL,
    "status_execucao" "text" NOT NULL,
    "detalhes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "observacao" "text",
    "executado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_reconciliacao_status_chk" CHECK (("status_execucao" = ANY (ARRAY['sucesso'::"text", 'ignorado'::"text", 'erro'::"text", 'pendente'::"text"])))
);


ALTER TABLE "public"."billing_reconciliacao" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_reconciliation_issues" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "executado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "gateway_event_id" "text",
    "recruta_id" "uuid",
    "assinatura_id" "uuid",
    "pagamento_id" "uuid",
    "tipo_divergencia" "text" NOT NULL,
    "detalhes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status_execucao" "text" DEFAULT 'pendente'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_reconciliation_issues_status_chk" CHECK (("status_execucao" = ANY (ARRAY['pendente'::"text", 'sucesso'::"text", 'erro'::"text", 'ignorado'::"text"])))
);


ALTER TABLE "public"."billing_reconciliation_issues" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c5_alertas_operacionais" (
    "id_alerta" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tipo_alerta" "text" NOT NULL,
    "dominio_analitico" "text" NOT NULL,
    "entidade" "text" NOT NULL,
    "valor_detectado" bigint NOT NULL,
    "limite_configurado" bigint NOT NULL,
    "detectado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "regra_origem" "text" NOT NULL,
    "detalhe" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "c5_alertas_operacionais_dominio_chk" CHECK (("dominio_analitico" = ANY (ARRAY['auth'::"text", 'medalha'::"text", 'patente'::"text", 'mensageria'::"text", 'workflow'::"text", 'outros'::"text"]))),
    CONSTRAINT "c5_alertas_operacionais_entidade_chk" CHECK (("btrim"("entidade") <> ''::"text")),
    CONSTRAINT "c5_alertas_operacionais_limite_chk" CHECK (("limite_configurado" > 0)),
    CONSTRAINT "c5_alertas_operacionais_tipo_chk" CHECK (("btrim"("tipo_alerta") <> ''::"text")),
    CONSTRAINT "c5_alertas_operacionais_valor_chk" CHECK (("valor_detectado" >= 0))
);


ALTER TABLE "public"."c5_alertas_operacionais" OWNER TO "postgres";


COMMENT ON TABLE "public"."c5_alertas_operacionais" IS 'Registro append-only de alertas operacionais detectados no C5. Não executa ações automáticas.';



COMMENT ON COLUMN "public"."c5_alertas_operacionais"."tipo_alerta" IS 'Categoria do alerta detectado.';



COMMENT ON COLUMN "public"."c5_alertas_operacionais"."dominio_analitico" IS 'Domínio afetado pela anomalia.';



COMMENT ON COLUMN "public"."c5_alertas_operacionais"."entidade" IS 'Entidade afetada: sistema ou recruta:<uuid>.';



COMMENT ON COLUMN "public"."c5_alertas_operacionais"."valor_detectado" IS 'Valor observado no momento da detecção.';



COMMENT ON COLUMN "public"."c5_alertas_operacionais"."limite_configurado" IS 'Limite da regra configurada que foi ultrapassado.';



COMMENT ON COLUMN "public"."c5_alertas_operacionais"."detectado_em" IS 'Timestamp da detecção.';



COMMENT ON COLUMN "public"."c5_alertas_operacionais"."regra_origem" IS 'Regra institucional que originou o alerta.';



COMMENT ON COLUMN "public"."c5_alertas_operacionais"."detalhe" IS 'Payload resumido de apoio à investigação.';



CREATE TABLE IF NOT EXISTS "public"."c5_audit_eventos_institucionais" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "evento_id" "uuid",
    "operacao" "text" NOT NULL,
    "tabela" "text" DEFAULT 'eventos_institucionais'::"text" NOT NULL,
    "current_user_name" "text" DEFAULT CURRENT_USER NOT NULL,
    "session_user_name" "text" DEFAULT SESSION_USER NOT NULL,
    "jwt_role" "text",
    "jwt_sub" "uuid",
    "registrado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "old_row" "jsonb",
    "new_row" "jsonb"
);


ALTER TABLE "public"."c5_audit_eventos_institucionais" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."eventos_institucionais" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "referencia_id" "uuid" NOT NULL,
    "titulo" "text" NOT NULL,
    "descricao" "text" NOT NULL,
    "prioridade" integer DEFAULT 1 NOT NULL,
    "cycle_id" "uuid",
    "emitido_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processado" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tipo_evento" "text",
    "idempotency_key" "text",
    "correlation_id" "text",
    "origem" "text",
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'received'::"text" NOT NULL,
    "error" "jsonb",
    CONSTRAINT "chk_c5_eventos_origem" CHECK ((("origem" IS NULL) OR ("origem" = ANY (ARRAY['n8n'::"text", 'chat_central'::"text", 'sistema'::"text"])))),
    CONSTRAINT "chk_c5_eventos_status" CHECK (("status" = ANY (ARRAY['received'::"text", 'processed'::"text", 'duplicate'::"text", 'failed'::"text"]))),
    CONSTRAINT "chk_eventos_origem" CHECK (("origem" = ANY (ARRAY['n8n'::"text", 'chat_central'::"text", 'sistema'::"text"]))),
    CONSTRAINT "chk_eventos_status" CHECK (("status" = ANY (ARRAY['received'::"text", 'processed'::"text", 'duplicate'::"text", 'failed'::"text"]))),
    CONSTRAINT "eventos_institucionais_prioridade_check" CHECK ((("prioridade" >= 1) AND ("prioridade" <= 5))),
    CONSTRAINT "eventos_institucionais_tipo_check" CHECK (("tipo" = ANY (ARRAY['medalha'::"text", 'patente'::"text", 'auth'::"text"])))
);


ALTER TABLE "public"."eventos_institucionais" OWNER TO "postgres";


COMMENT ON TABLE "public"."eventos_institucionais" IS 'C5: eventos institucionais idempotentes. Fonte única da verdade para efeitos/merito.';



COMMENT ON CONSTRAINT "eventos_institucionais_tipo_check" ON "public"."eventos_institucionais" IS 'C5: domínios institucionais válidos do pipeline. Permitidos: medalha, patente, auth.';



CREATE OR REPLACE VIEW "public"."c5_eventos_view" WITH ("security_invoker"='true') AS
 SELECT "id",
    "recruta_id",
    "tipo_evento",
    "idempotency_key",
    "correlation_id",
    "origem",
    "payload",
    "status",
    "error",
    "created_at"
   FROM "public"."eventos_institucionais" "e"
  WHERE ("idempotency_key" IS NOT NULL);


ALTER VIEW "public"."c5_eventos_view" OWNER TO "postgres";


COMMENT ON VIEW "public"."c5_eventos_view" IS 'Interface canônica C5 (somente leitura). Expõe apenas eventos modernos (idempotency_key != null). NÃO usar public.eventos_institucionais diretamente no app para fluxo C5.';



CREATE OR REPLACE VIEW "public"."c5_eventos_view_v2" AS
 SELECT "id",
    "recruta_id",
    "tipo" AS "dominio",
    "tipo_evento",
    "idempotency_key",
    "correlation_id",
    "origem",
    "payload",
    "status",
    "error",
    "created_at"
   FROM "public"."eventos_institucionais"
  WHERE ("idempotency_key" IS NOT NULL);


ALTER VIEW "public"."c5_eventos_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c5_fatos_analytics" (
    "id_evento" "uuid" NOT NULL,
    "id_recruta" "uuid" NOT NULL,
    "timestamp_evento" timestamp with time zone NOT NULL,
    "dia" "date" NOT NULL,
    "dominio_analitico" "text" NOT NULL,
    "evento_analitico" "text" NOT NULL,
    "origem" "text",
    "sessao_logica" "uuid",
    "sequencia_ordem" integer
);


ALTER TABLE "public"."c5_fatos_analytics" OWNER TO "postgres";


COMMENT ON TABLE "public"."c5_fatos_analytics" IS 'Tabela fato oficial de analytics do C5. Estrutura enxuta e derivada da public.v_c5_eventos_dominios_v3, sem duplicar metadata.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."id_evento" IS 'Referência única ao evento institucional original.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."id_recruta" IS 'Recruta associado ao evento analítico.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."timestamp_evento" IS 'Timestamp do evento analítico.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."dia" IS 'Partição temporal lógica do fato analítico.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."dominio_analitico" IS 'Domínio institucional do evento.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."evento_analitico" IS 'Evento granular para analytics.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."origem" IS 'Origem operacional do evento.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."sessao_logica" IS 'Agrupamento lógico de sessão para análises futuras de jornada.';



COMMENT ON COLUMN "public"."c5_fatos_analytics"."sequencia_ordem" IS 'Ordem do evento dentro da sessão lógica, quando aplicável.';



CREATE TABLE IF NOT EXISTS "public"."c5_jobs_execucao_log" (
    "id" bigint NOT NULL,
    "job" "text" NOT NULL,
    "executado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "linhas_processadas" bigint DEFAULT 0 NOT NULL,
    "status" "text" NOT NULL,
    "detalhe" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "c5_jobs_execucao_log_job_chk" CHECK (("btrim"("job") <> ''::"text")),
    CONSTRAINT "c5_jobs_execucao_log_linhas_chk" CHECK (("linhas_processadas" >= 0)),
    CONSTRAINT "c5_jobs_execucao_log_status_chk" CHECK (("status" = ANY (ARRAY['success'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."c5_jobs_execucao_log" OWNER TO "postgres";


COMMENT ON TABLE "public"."c5_jobs_execucao_log" IS 'Log operacional append-only dos jobs institucionais de métricas do C5.';



COMMENT ON COLUMN "public"."c5_jobs_execucao_log"."job" IS 'Nome lógico do job executado.';



COMMENT ON COLUMN "public"."c5_jobs_execucao_log"."executado_em" IS 'Timestamp da execução do job.';



COMMENT ON COLUMN "public"."c5_jobs_execucao_log"."linhas_processadas" IS 'Quantidade de linhas agregadas/upsertadas na tabela de destino.';



COMMENT ON COLUMN "public"."c5_jobs_execucao_log"."status" IS 'Resultado da execução: success ou failed.';



COMMENT ON COLUMN "public"."c5_jobs_execucao_log"."detalhe" IS 'Payload resumido da execução para observabilidade operacional.';



CREATE SEQUENCE IF NOT EXISTS "public"."c5_jobs_execucao_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."c5_jobs_execucao_log_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."c5_jobs_execucao_log_id_seq" OWNED BY "public"."c5_jobs_execucao_log"."id";



CREATE TABLE IF NOT EXISTS "public"."c5_metricas_diarias" (
    "dia" "date" NOT NULL,
    "dominio_analitico" "text" NOT NULL,
    "evento_analitico" "text" NOT NULL,
    "total_eventos" bigint DEFAULT 0 NOT NULL,
    CONSTRAINT "c5_metricas_diarias_dominio_chk" CHECK (("dominio_analitico" = ANY (ARRAY['auth'::"text", 'medalha'::"text", 'patente'::"text", 'mensageria'::"text", 'workflow'::"text", 'outros'::"text"]))),
    CONSTRAINT "c5_metricas_diarias_evento_chk" CHECK (("btrim"("evento_analitico") <> ''::"text")),
    CONSTRAINT "c5_metricas_diarias_total_chk" CHECK (("total_eventos" >= 0))
);


ALTER TABLE "public"."c5_metricas_diarias" OWNER TO "postgres";


COMMENT ON TABLE "public"."c5_metricas_diarias" IS 'Camada oficial de métricas operacionais materializadas do C5. Derivada de public.v_c5_eventos_dominios_v3. Não substitui eventos brutos e pode ser reconstruída integralmente.';



COMMENT ON COLUMN "public"."c5_metricas_diarias"."dia" IS 'Data da agregação diária.';



COMMENT ON COLUMN "public"."c5_metricas_diarias"."dominio_analitico" IS 'Agrupador institucional estável do C5.';



COMMENT ON COLUMN "public"."c5_metricas_diarias"."evento_analitico" IS 'Evento granular agregado na métrica diária.';



COMMENT ON COLUMN "public"."c5_metricas_diarias"."total_eventos" IS 'Contagem materializada de eventos para a combinação (dia, domínio, evento).';



CREATE TABLE IF NOT EXISTS "public"."c5_metricas_recruta" (
    "id_recruta" "uuid" NOT NULL,
    "dia" "date" NOT NULL,
    "dominio_analitico" "text" NOT NULL,
    "evento_analitico" "text" NOT NULL,
    "total_eventos" bigint DEFAULT 0 NOT NULL,
    CONSTRAINT "c5_metricas_recruta_dominio_chk" CHECK (("dominio_analitico" = ANY (ARRAY['auth'::"text", 'medalha'::"text", 'patente'::"text", 'mensageria'::"text", 'workflow'::"text", 'outros'::"text"]))),
    CONSTRAINT "c5_metricas_recruta_evento_chk" CHECK (("btrim"("evento_analitico") <> ''::"text")),
    CONSTRAINT "c5_metricas_recruta_total_chk" CHECK (("total_eventos" >= 0))
);


ALTER TABLE "public"."c5_metricas_recruta" OWNER TO "postgres";


COMMENT ON TABLE "public"."c5_metricas_recruta" IS 'Camada oficial de métricas comportamentais do C5. Derivada de public.v_c5_eventos_dominios_v3. Não substitui eventos brutos e pode ser reconstruída integralmente.';



COMMENT ON COLUMN "public"."c5_metricas_recruta"."id_recruta" IS 'Entidade institucional analisada na métrica comportamental.';



COMMENT ON COLUMN "public"."c5_metricas_recruta"."dia" IS 'Data da agregação diária.';



COMMENT ON COLUMN "public"."c5_metricas_recruta"."dominio_analitico" IS 'Agrupador institucional estável do C5.';



COMMENT ON COLUMN "public"."c5_metricas_recruta"."evento_analitico" IS 'Evento granular agregado na métrica comportamental.';



COMMENT ON COLUMN "public"."c5_metricas_recruta"."total_eventos" IS 'Contagem materializada de eventos para a combinação (recruta, dia, domínio, evento).';



CREATE TABLE IF NOT EXISTS "public"."c5_regras_alerta" (
    "tipo_alerta" "text" NOT NULL,
    "dominio_analitico" "text" NOT NULL,
    "evento_analitico" "text",
    "limite" bigint NOT NULL,
    "janela_tempo" interval NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "observacoes" "text",
    CONSTRAINT "c5_regras_alerta_dominio_chk" CHECK (("dominio_analitico" = ANY (ARRAY['auth'::"text", 'medalha'::"text", 'patente'::"text", 'mensageria'::"text", 'workflow'::"text", 'outros'::"text"]))),
    CONSTRAINT "c5_regras_alerta_janela_chk" CHECK (("janela_tempo" > '00:00:00'::interval)),
    CONSTRAINT "c5_regras_alerta_limite_chk" CHECK (("limite" > 0)),
    CONSTRAINT "c5_regras_alerta_tipo_chk" CHECK (("btrim"("tipo_alerta") <> ''::"text"))
);


ALTER TABLE "public"."c5_regras_alerta" OWNER TO "postgres";


COMMENT ON TABLE "public"."c5_regras_alerta" IS 'Tabela institucional de governança das regras de alerta operacional do C5.';



COMMENT ON COLUMN "public"."c5_regras_alerta"."tipo_alerta" IS 'Nome lógico da regra de alerta.';



COMMENT ON COLUMN "public"."c5_regras_alerta"."dominio_analitico" IS 'Domínio monitorado pela regra.';



COMMENT ON COLUMN "public"."c5_regras_alerta"."evento_analitico" IS 'Evento específico monitorado. Nulo significa todos os eventos do domínio.';



COMMENT ON COLUMN "public"."c5_regras_alerta"."limite" IS 'Valor limite configurado para disparo do alerta.';



COMMENT ON COLUMN "public"."c5_regras_alerta"."janela_tempo" IS 'Janela temporal analisada pela regra.';



COMMENT ON COLUMN "public"."c5_regras_alerta"."ativo" IS 'Habilita ou desabilita a regra sem removê-la.';



COMMENT ON COLUMN "public"."c5_regras_alerta"."observacoes" IS 'Documentação curta da regra.';



CREATE TABLE IF NOT EXISTS "public"."c5_taxonomia_eventos" (
    "tipo_evento" "text" NOT NULL,
    "evento_analitico" "text" NOT NULL,
    "dominio_analitico" "text" NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "observacoes" "text",
    "ordem" integer DEFAULT 100 NOT NULL,
    CONSTRAINT "c5_taxonomia_eventos_dominio_analitico_chk" CHECK (("dominio_analitico" = ANY (ARRAY['auth'::"text", 'medalha'::"text", 'patente'::"text", 'mensageria'::"text", 'workflow'::"text", 'outros'::"text"]))),
    CONSTRAINT "c5_taxonomia_eventos_evento_analitico_chk" CHECK (("btrim"("evento_analitico") <> ''::"text")),
    CONSTRAINT "c5_taxonomia_eventos_tipo_evento_chk" CHECK (("btrim"("tipo_evento") <> ''::"text"))
);


ALTER TABLE "public"."c5_taxonomia_eventos" OWNER TO "postgres";


COMMENT ON TABLE "public"."c5_taxonomia_eventos" IS 'Tabela institucional de governança da classificação analítica do C5. V1 usa tipo_evento exato como chave física e lógica.';



COMMENT ON COLUMN "public"."c5_taxonomia_eventos"."tipo_evento" IS 'Chave moderna exata do evento C5.';



COMMENT ON COLUMN "public"."c5_taxonomia_eventos"."evento_analitico" IS 'Nome granular oficial do evento para leitura analítica.';



COMMENT ON COLUMN "public"."c5_taxonomia_eventos"."dominio_analitico" IS 'Agrupador institucional estável aprovado pelo Cérebro Institucional.';



COMMENT ON COLUMN "public"."c5_taxonomia_eventos"."ativo" IS 'Habilita ou desabilita o mapeamento sem apagar histórico da taxonomia.';



COMMENT ON COLUMN "public"."c5_taxonomia_eventos"."observacoes" IS 'Documentação curta da classificação.';



COMMENT ON COLUMN "public"."c5_taxonomia_eventos"."ordem" IS 'Apoio opcional para ordenação e relatórios.';



CREATE TABLE IF NOT EXISTS "public"."c6_contract_registry" (
    "contract_name" "text" NOT NULL,
    "contract_type" "text" NOT NULL,
    "status" "text" NOT NULL,
    "frontend_scope" "text",
    "notes" "text",
    "registered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "c6_contract_registry_contract_type_check" CHECK (("contract_type" = ANY (ARRAY['view'::"text", 'materialized_view'::"text", 'rpc'::"text"]))),
    CONSTRAINT "c6_contract_registry_status_check" CHECK (("status" = ANY (ARRAY['canonical'::"text", 'system'::"text", 'legacy'::"text", 'admin_audit'::"text", 'blocked'::"text"])))
);


ALTER TABLE "public"."c6_contract_registry" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c7_ciclos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "active" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."c7_ciclos" OWNER TO "postgres";


COMMENT ON TABLE "public"."c7_ciclos" IS 'C7: ciclos/versionamento de regras institucionais. Somente um ciclo deve ficar ativo por vez.';



CREATE TABLE IF NOT EXISTS "public"."c7_execucao_diaria_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "started_at" timestamp with time zone NOT NULL,
    "finished_at" timestamp with time zone NOT NULL,
    "recrutas_processados" integer NOT NULL,
    "medalhas_avaliadas" integer NOT NULL,
    "medalhas_concedidas" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."c7_execucao_diaria_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c7_regras_bloqueio_medalhas" (
    "medalha_slug" "text" NOT NULL,
    "motivo_bloqueio" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."c7_regras_bloqueio_medalhas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c7_regras_bloqueio_por_ciclo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "ciclo_id" "uuid" NOT NULL,
    "medalha_slug" "text" NOT NULL,
    "tipo_regra" "text" DEFAULT 'ausencia'::"text" NOT NULL,
    "descricao" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."c7_regras_bloqueio_por_ciclo" OWNER TO "postgres";


COMMENT ON TABLE "public"."c7_regras_bloqueio_por_ciclo" IS 'C7: regras de bloqueio por ciclo. Nesta fase: tipo_regra=ausencia (medalha obrigatória faltante).';



CREATE TABLE IF NOT EXISTS "public"."c9_aula_conteudos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "aula_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "titulo" "text",
    "corpo_markdown" "text" NOT NULL,
    "versao" integer DEFAULT 1 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "origem" "text" DEFAULT 'QD_FACTORY'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "c9_aula_conteudos_tipo_check" CHECK (("tipo" = ANY (ARRAY['roteiro'::"text", 'resumo'::"text", 'explicacao'::"text", 'markdown'::"text", 'material_complementar'::"text"]))),
    CONSTRAINT "c9_aula_conteudos_versao_check" CHECK (("versao" > 0))
);


ALTER TABLE "public"."c9_aula_conteudos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c9_aula_flashcards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "aula_id" "uuid" NOT NULL,
    "pergunta" "text" NOT NULL,
    "resposta" "text" NOT NULL,
    "ordem" integer DEFAULT 0 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "origem" "text" DEFAULT 'QD_FACTORY'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."c9_aula_flashcards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c9_aula_quiz_alternativas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pergunta_id" "uuid" NOT NULL,
    "texto" "text" NOT NULL,
    "correta" boolean DEFAULT false NOT NULL,
    "ordem" integer DEFAULT 0 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."c9_aula_quiz_alternativas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c9_aula_quiz_perguntas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "quiz_id" "uuid" NOT NULL,
    "enunciado" "text" NOT NULL,
    "explicacao" "text",
    "ordem" integer DEFAULT 0 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."c9_aula_quiz_perguntas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c9_aula_quiz_tentativas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "quiz_id" "uuid" NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "respostas" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "total_perguntas" integer DEFAULT 0 NOT NULL,
    "total_acertos" integer DEFAULT 0 NOT NULL,
    "percentual" numeric(5,2) DEFAULT 0 NOT NULL,
    "finalizada" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."c9_aula_quiz_tentativas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."c9_aula_quizzes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "aula_id" "uuid" NOT NULL,
    "titulo" "text" NOT NULL,
    "descricao" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "origem" "text" DEFAULT 'QD_FACTORY'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."c9_aula_quizzes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campeoes_mensais" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "forca" "text" NOT NULL,
    "mes_referencia" "date" NOT NULL,
    "xp_total" integer NOT NULL,
    "premiado" boolean DEFAULT false NOT NULL,
    "foto_url" "text",
    "status_premio" "text" DEFAULT 'aguardando_upload'::"text" NOT NULL,
    "lembretes_enviados" integer DEFAULT 0 NOT NULL,
    "ultimo_lembrete_em" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campeoes_mensais_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"])))
);


ALTER TABLE "public"."campeoes_mensais" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_audit_log" (
    "audit_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "uuid",
    "timestamp_utc" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "instructor_profile_id" "text",
    "access_mode" "text" NOT NULL,
    "interaction_type" "text" NOT NULL,
    "response_category" "text" NOT NULL,
    "source" "text" DEFAULT 'mobile_app'::"text",
    "agent" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    CONSTRAINT "chk_interaction_type" CHECK (("interaction_type" = ANY (ARRAY['question'::"text", 'explanation'::"text", 'quiz'::"text", 'review'::"text"]))),
    CONSTRAINT "chk_response_category" CHECK (("response_category" = ANY (ARRAY['answered_within_scope'::"text", 'blocked'::"text", 'redirected'::"text"])))
);


ALTER TABLE "public"."chat_audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_conversas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "instrutor_slug" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "opened_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_message_at" timestamp with time zone,
    "unread_count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chat_conversas_instrutor_slug_check" CHECK (("instrutor_slug" = ANY (ARRAY['objetivo'::"text", 'estrategico'::"text", 'didatico'::"text"]))),
    CONSTRAINT "chat_conversas_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'archived'::"text"]))),
    CONSTRAINT "chat_conversas_unread_count_check" CHECK (("unread_count" >= 0))
);


ALTER TABLE "public"."chat_conversas" OWNER TO "postgres";


COMMENT ON TABLE "public"."chat_conversas" IS 'RCC-0.5 Wave 1: canal visual institucional entre recruta e instrutor. Conversa nasce na primeira mensagem enviada.';



CREATE TABLE IF NOT EXISTS "public"."chat_events" (
    "event_id" "uuid" NOT NULL,
    "auth_id" "uuid" NOT NULL,
    "recruta_id" "uuid",
    "thread_id" "text",
    "run_id" "text",
    "status" "text" DEFAULT 'processing'::"text" NOT NULL,
    "response_json" "jsonb",
    "error_json" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone,
    CONSTRAINT "chat_events_status_check" CHECK (("status" = ANY (ARRAY['processing'::"text", 'completed'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."chat_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "correlation_id" "text" NOT NULL,
    "evento_id" "uuid" NOT NULL,
    "thread_id" "text",
    "modelo_usado" "text",
    "tokens_input" integer,
    "tokens_output" integer,
    "preco_input_token" numeric,
    "preco_output_token" numeric,
    "custo_total" numeric,
    "status" "text" NOT NULL,
    "request" "jsonb",
    "response" "jsonb",
    "error" "jsonb",
    CONSTRAINT "chk_chatlog_precos_nonneg" CHECK (((("preco_input_token" IS NULL) OR ("preco_input_token" >= (0)::numeric)) AND (("preco_output_token" IS NULL) OR ("preco_output_token" >= (0)::numeric)) AND (("custo_total" IS NULL) OR ("custo_total" >= (0)::numeric)))),
    CONSTRAINT "chk_chatlog_status" CHECK (("status" = ANY (ARRAY['started'::"text", 'completed'::"text", 'timeout'::"text", 'failed'::"text", 'duplicate'::"text", 'locked'::"text"]))),
    CONSTRAINT "chk_chatlog_tokens_nonneg" CHECK (((("tokens_input" IS NULL) OR ("tokens_input" >= 0)) AND (("tokens_output" IS NULL) OR ("tokens_output" >= 0))))
);


ALTER TABLE "public"."chat_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."chat_logs" IS 'Logs estruturados do Chat Central. Não é fonte de verdade. 1 log principal por evento (evento_id UNIQUE).';



CREATE TABLE IF NOT EXISTS "public"."chat_mensagens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "conversa_id" "uuid" NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "instrutor_slug" "text" NOT NULL,
    "role" "text" NOT NULL,
    "conteudo" "text" NOT NULL,
    "status" "text" DEFAULT 'sent'::"text" NOT NULL,
    "client_message_id" "text" NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "correlation_id" "text" NOT NULL,
    "origem" "text" DEFAULT 'app'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chat_mensagens_client_message_id_check" CHECK (("length"("btrim"("client_message_id")) > 0)),
    CONSTRAINT "chat_mensagens_conteudo_check" CHECK (("length"("btrim"("conteudo")) > 0)),
    CONSTRAINT "chat_mensagens_idempotency_key_check" CHECK (("idempotency_key" ~~ 'chat:%'::"text")),
    CONSTRAINT "chat_mensagens_instrutor_slug_check" CHECK (("instrutor_slug" = ANY (ARRAY['objetivo'::"text", 'estrategico'::"text", 'didatico'::"text"]))),
    CONSTRAINT "chat_mensagens_origem_check" CHECK (("origem" = ANY (ARRAY['app'::"text", 'edge_function'::"text", 'chat_central'::"text", 'sistema'::"text"]))),
    CONSTRAINT "chat_mensagens_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'assistant'::"text", 'system'::"text"]))),
    CONSTRAINT "chat_mensagens_status_check" CHECK (("status" = ANY (ARRAY['sent'::"text", 'read'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."chat_mensagens" OWNER TO "postgres";


COMMENT ON TABLE "public"."chat_mensagens" IS 'RCC-0.5 Wave 1: mensagens institucionais persistidas. Sem delivered, typing, streaming ou realtime.';



COMMENT ON COLUMN "public"."chat_mensagens"."client_message_id" IS 'Gerado pelo frontend para retry/dedupe. Reutilizado no retry manual.';



COMMENT ON COLUMN "public"."chat_mensagens"."idempotency_key" IS 'Formato base: chat:<recruta_id>:<client_message_id>:<role>.';



CREATE TABLE IF NOT EXISTS "public"."chat_reads" (
    "conversa_id" "uuid" NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "last_read_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."chat_reads" OWNER TO "postgres";


COMMENT ON TABLE "public"."chat_reads" IS 'RCC-0.5 Wave 1: ponteiro oficial de leitura para reset transacional de unread.';



CREATE TABLE IF NOT EXISTS "public"."chat_summaries" (
    "recruta_id" "uuid" NOT NULL,
    "thread_id" "text",
    "summary" "text" DEFAULT ''::"text" NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."chat_summaries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_threads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "forca" "text" NOT NULL,
    "thread_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."chat_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."conversation_locks" (
    "recruta_id" "uuid" NOT NULL,
    "locked_at" timestamp with time zone NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "correlation_id" "text" NOT NULL,
    "owner" "text" NOT NULL,
    CONSTRAINT "chk_lock_owner" CHECK (("owner" = ANY (ARRAY['n8n'::"text", 'chat_central'::"text"])))
);


ALTER TABLE "public"."conversation_locks" OWNER TO "postgres";


COMMENT ON TABLE "public"."conversation_locks" IS 'Lock por recruta com TTL. Fonte única para concorrência do Chat Central.';



CREATE TABLE IF NOT EXISTS "public"."cronograma_semanal" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "ciclo_id" "uuid" NOT NULL,
    "semana_num" integer NOT NULL,
    "data_inicio" "date" NOT NULL,
    "data_fim" "date" NOT NULL,
    "titulo" "text" NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "aulas_previstas_total" integer,
    CONSTRAINT "cronograma_semanal_semana_num_check" CHECK (("semana_num" > 0))
);


ALTER TABLE "public"."cronograma_semanal" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."eventos_ciclos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."eventos_ciclos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."eventos_consumidos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "evento_id" "uuid" NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "consumido_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."eventos_consumidos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."forcas" (
    "id" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "cor_primaria" "text" NOT NULL,
    "cor_secundaria" "text" NOT NULL,
    "cor_fundo" "text" NOT NULL,
    "icone" "text",
    "ativo" boolean DEFAULT true
);


ALTER TABLE "public"."forcas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."iea_marcos_emitidos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "ciclo_id" "uuid",
    "marco" integer NOT NULL,
    "snapshot_id" "uuid" NOT NULL,
    "emitido_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ciclo_chave" "uuid" NOT NULL,
    CONSTRAINT "iea_marcos_emitidos_marco_check" CHECK (("marco" = ANY (ARRAY[70, 80, 90, 95])))
);


ALTER TABLE "public"."iea_marcos_emitidos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."institutional_assets" (
    "asset_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tipo" "text" NOT NULL,
    "url" "text" NOT NULL,
    "forca" "text",
    "versao" integer DEFAULT 1 NOT NULL,
    "ativo" boolean DEFAULT true NOT NULL,
    "checksum" "text",
    "cache_policy" "text" DEFAULT 'public,max-age=86400'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "asset_key" "text",
    CONSTRAINT "institutional_assets_forca_check" CHECK ((("forca" IS NULL) OR ("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))))
);


ALTER TABLE "public"."institutional_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."institutional_notice_reads" (
    "notice_id" "uuid" NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "read_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."institutional_notice_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."institutional_notices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "priority" integer DEFAULT 0 NOT NULL,
    "deep_link" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."institutional_notices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."instructor_message_reads" (
    "message_id" "uuid" NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "read_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."instructor_message_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."instructor_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "deep_link" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."instructor_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."instrutor_threads" (
    "recruta_id" "uuid" NOT NULL,
    "agent_id" "text" NOT NULL,
    "thread_id" "text" NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"(),
    "atualizado_em" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."instrutor_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."instrutores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "descricao" "text",
    "ativo" boolean DEFAULT true NOT NULL,
    "ordem_exibicao" integer DEFAULT 100 NOT NULL,
    "avatar_asset_tipo" "text",
    "chat_icon_asset_tipo" "text",
    "whatsapp_asset_tipo" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "card_selected_asset_tipo" "text",
    "card_idle_asset_tipo" "text"
);


ALTER TABLE "public"."instrutores" OWNER TO "postgres";


COMMENT ON TABLE "public"."instrutores" IS 'RCC-0.5 Wave 1: catálogo de personas visuais institucionais de instrutores. Não representa IA nem provider.';



COMMENT ON COLUMN "public"."instrutores"."slug" IS 'Slug institucional lógico usado por recrutas.instructor_profile_id. Valores Wave 1: objetivo, estrategico, didatico.';



CREATE TABLE IF NOT EXISTS "public"."lessons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "force" "text" NOT NULL,
    "module" "text" NOT NULL,
    "lesson_order" integer NOT NULL,
    "title" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "video_playback_id" "text",
    "duration_seconds" integer,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."lessons" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."licoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "modulo_id" "uuid",
    "titulo" "text" NOT NULL,
    "conteudo" "text" NOT NULL,
    "ordem" integer NOT NULL,
    "premium" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."licoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."log_emissao_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "evento_id" "uuid" NOT NULL,
    "origem" "text" NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."log_emissao_eventos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."logs_acesso" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid",
    "acao" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."logs_acesso" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalha_regras" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "medalha_id" "uuid" NOT NULL,
    "metrica" "text" NOT NULL,
    "operador" "text" DEFAULT '>='::"text" NOT NULL,
    "valor" integer NOT NULL,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "tipo_regra" "text",
    "parametro" numeric,
    "comparador" "text",
    "acumulativa" boolean DEFAULT false,
    "ativa" boolean DEFAULT true,
    "criada_em" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."medalha_regras" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_alteracoes_pendentes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "medalha_id" "uuid" NOT NULL,
    "proposta_catalogo" "jsonb" NOT NULL,
    "proposta_regras" "jsonb" NOT NULL,
    "status" "text" DEFAULT 'PENDENTE'::"text" NOT NULL,
    "criado_por" "text" NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "aprovado_por" "text",
    "aprovado_em" timestamp with time zone,
    "aplicado" boolean DEFAULT false NOT NULL,
    CONSTRAINT "chk_status_alteracao" CHECK (("status" = ANY (ARRAY['PENDENTE'::"text", 'APROVADA'::"text", 'REJEITADA'::"text", 'APLICADA'::"text"])))
);


ALTER TABLE "public"."medalhas_alteracoes_pendentes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_catalogo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "descricao" "text",
    "icon_url" "text",
    "categoria" "text" DEFAULT 'geral'::"text",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."medalhas_catalogo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_catalogo_versionamento" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "medalha_id" "uuid" NOT NULL,
    "versao" integer NOT NULL,
    "snapshot_catalogo" "jsonb" NOT NULL,
    "snapshot_regras" "jsonb" NOT NULL,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."medalhas_catalogo_versionamento" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_categorias" (
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "ativa" boolean DEFAULT true,
    "ordem" integer NOT NULL
);


ALTER TABLE "public"."medalhas_categorias" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_concedidas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "medalha_id" "uuid" NOT NULL,
    "granted_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."medalhas_concedidas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_concessao_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "run_id" "uuid" NOT NULL,
    "run_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "medalha_id" "uuid" NOT NULL,
    "medalha_slug" "text" NOT NULL,
    "elegivel" boolean NOT NULL,
    "ja_concedida" boolean NOT NULL,
    "concedida_agora" boolean NOT NULL,
    "motivo_bloqueio" "text",
    "faltantes" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "detalhes" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."medalhas_concessao_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "descricao" "text" NOT NULL,
    "ativa" boolean DEFAULT true,
    "inicio" "date",
    "fim" "date"
);


ALTER TABLE "public"."medalhas_eventos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_obrigatorias_map" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "forca" "text" NOT NULL,
    "medalha_slug" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "medalhas_obrigatorias_map_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"])))
);


ALTER TABLE "public"."medalhas_obrigatorias_map" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."medalhas_slug_aliases" (
    "slug_alias" "text" NOT NULL,
    "slug_canonico" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."medalhas_slug_aliases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mensagens_chat" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "forca" "text" NOT NULL,
    "role" "text" NOT NULL,
    "conteudo" "text" NOT NULL,
    "thread_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "mensagem_usuario" "text",
    "mensagem_assistant" "text"
);


ALTER TABLE "public"."mensagens_chat" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "role" "text" NOT NULL,
    "content" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."metrics_daily" (
    "date" "date" NOT NULL,
    "total" integer DEFAULT 0 NOT NULL,
    "completed" integer DEFAULT 0 NOT NULL,
    "cost" numeric(14,6) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."metrics_daily" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."missoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "descricao" "text" NOT NULL,
    "xp_recompensa" integer DEFAULT 0 NOT NULL,
    "ativa" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "forca" "text" DEFAULT 'marinha'::"text" NOT NULL,
    "xp" integer DEFAULT 0 NOT NULL,
    "tipo" "text",
    "modulo_id" "uuid",
    "ordem" integer,
    CONSTRAINT "chk_missoes_forca_valida" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "missoes_tipo_check" CHECK (("tipo" = ANY (ARRAY['aula'::"text", 'revisao'::"text"])))
);


ALTER TABLE "public"."missoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."modelos_precificacao_versionada" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "modelo" "text" NOT NULL,
    "versao" integer NOT NULL,
    "effective_from" timestamp with time zone DEFAULT "now"() NOT NULL,
    "preco_input_token" numeric NOT NULL,
    "preco_output_token" numeric NOT NULL,
    "criado_por" "text" NOT NULL,
    CONSTRAINT "chk_precos_nonneg" CHECK ((("preco_input_token" >= (0)::numeric) AND ("preco_output_token" >= (0)::numeric)))
);


ALTER TABLE "public"."modelos_precificacao_versionada" OWNER TO "postgres";


COMMENT ON TABLE "public"."modelos_precificacao_versionada" IS 'Tabela institucional: precificação versionada por modelo (custo/token).';



CREATE TABLE IF NOT EXISTS "public"."modulos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "forca" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "descricao" "text",
    "ordem" integer NOT NULL,
    "ativo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_degustacao" boolean DEFAULT false,
    CONSTRAINT "chk_forca_modulos" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "modulos_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"])))
);


ALTER TABLE "public"."modulos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_bloqueio_por_log_resumo" AS
 WITH "base" AS (
         SELECT "l"."medalha_slug",
            "l"."motivo_bloqueio"
           FROM "public"."medalhas_concessao_log" "l"
          WHERE ("l"."motivo_bloqueio" IS NOT NULL)
        ), "agg" AS (
         SELECT "b"."medalha_slug",
            "b"."motivo_bloqueio",
            ("count"(*))::integer AS "total_bloqueios"
           FROM "base" "b"
          GROUP BY "b"."medalha_slug", "b"."motivo_bloqueio"
        )
 SELECT "medalha_slug",
    "motivo_bloqueio",
    "total_bloqueios",
    "round"(((("total_bloqueios")::numeric / (NULLIF("sum"("total_bloqueios") OVER (PARTITION BY "medalha_slug"), 0))::numeric) * (100)::numeric), 2) AS "percentual_bloqueio_sobre_total_da_medalha"
   FROM "agg" "a"
  ORDER BY "total_bloqueios" DESC, "medalha_slug", "motivo_bloqueio";


ALTER VIEW "public"."v_c7_bloqueio_por_log_resumo" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_c7_bloqueio_por_medalha" AS
 SELECT "medalha_slug",
    "motivo_bloqueio",
    "total_bloqueios",
    "percentual_bloqueio_sobre_total_da_medalha"
   FROM "public"."v_c7_bloqueio_por_log_resumo"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_c7_bloqueio_por_medalha" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_metricas_problema" AS
 WITH "exploded" AS (
         SELECT "l"."created_at",
            "unnest"("l"."faltantes") AS "faltante"
           FROM "public"."medalhas_concessao_log" "l"
        ), "norm" AS (
         SELECT
                CASE
                    WHEN ("e"."faltante" ~~ 'FONTE_NAO_MAPEADA:%'::"text") THEN "split_part"("e"."faltante", ':'::"text", 2)
                    WHEN ("e"."faltante" ~~ 'SEM_DADO:%'::"text") THEN "split_part"("e"."faltante", ':'::"text", 2)
                    ELSE "e"."faltante"
                END AS "metrica",
                CASE
                    WHEN ("e"."faltante" ~~ 'FONTE_NAO_MAPEADA:%'::"text") THEN 'FONTE_NAO_MAPEADA'::"text"
                    WHEN ("e"."faltante" ~~ 'SEM_DADO:%'::"text") THEN 'SEM_DADO'::"text"
                    ELSE 'NAO_ELEGIVEL'::"text"
                END AS "tipo_problema",
            "e"."created_at"
           FROM "exploded" "e"
          WHERE (("e"."faltante" IS NOT NULL) AND ("e"."faltante" <> ''::"text"))
        )
 SELECT "metrica",
    "tipo_problema",
    ("count"(*))::integer AS "total_ocorrencias",
    "max"("created_at") AS "ultima_ocorrencia"
   FROM "norm" "n"
  GROUP BY "metrica", "tipo_problema"
  ORDER BY (("count"(*))::integer) DESC, "metrica", "tipo_problema";


ALTER VIEW "public"."v_c7_metricas_problema" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_c7_metricas_problema_resumo" AS
 SELECT "metrica",
    "tipo_problema",
    "total_ocorrencias",
    "ultima_ocorrencia"
   FROM "public"."v_c7_metricas_problema" "v"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_c7_metricas_problema_resumo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_status_atual_recruta" AS
 WITH "ultimo_run" AS (
         SELECT DISTINCT ON ("l"."recruta_id") "l"."recruta_id",
            "l"."run_id",
            "l"."run_at"
           FROM "public"."medalhas_concessao_log" "l"
          ORDER BY "l"."recruta_id", "l"."run_at" DESC, "l"."created_at" DESC
        ), "agg" AS (
         SELECT "l"."recruta_id",
            "l"."run_id",
            ("count"(*))::integer AS "total_medalhas_avaliadas",
            ("count"(*) FILTER (WHERE ("l"."elegivel" IS TRUE)))::integer AS "total_elegiveis",
            ("count"(*) FILTER (WHERE ("l"."concedida_agora" IS TRUE)))::integer AS "total_concedidas",
            ("count"(*) FILTER (WHERE ("l"."motivo_bloqueio" IS NOT NULL)))::integer AS "total_bloqueadas"
           FROM ("public"."medalhas_concessao_log" "l"
             JOIN "ultimo_run" "u_1" ON ((("u_1"."recruta_id" = "l"."recruta_id") AND ("u_1"."run_id" = "l"."run_id"))))
          GROUP BY "l"."recruta_id", "l"."run_id"
        )
 SELECT "r"."id" AS "recruta_id",
    "r"."nome",
    "r"."status",
    "a"."total_medalhas_avaliadas",
    "a"."total_elegiveis",
    "a"."total_concedidas",
    "a"."total_bloqueadas",
    "u"."run_at" AS "ultimo_run_at"
   FROM (("ultimo_run" "u"
     JOIN "agg" "a" ON ((("a"."recruta_id" = "u"."recruta_id") AND ("a"."run_id" = "u"."run_id"))))
     JOIN "public"."recrutas" "r" ON (("r"."id" = "u"."recruta_id")))
  ORDER BY "u"."run_at" DESC, "r"."nome";


ALTER VIEW "public"."v_c7_status_atual_recruta" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_c7_status_recruta_atual" AS
 SELECT "recruta_id",
    "nome",
    "status",
    "total_medalhas_avaliadas",
    "total_elegiveis",
    "total_concedidas",
    "total_bloqueadas",
    "ultimo_run_at"
   FROM "public"."v_c7_status_atual_recruta" "v"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_c7_status_recruta_atual" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."xp_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "forca" "text" NOT NULL,
    "quantidade" integer NOT NULL,
    "origem" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "referencia_id" "uuid",
    CONSTRAINT "xp_eventos_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "xp_eventos_quantidade_check" CHECK (("quantidade" > 0))
);


ALTER TABLE "public"."xp_eventos" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_xp_mensal_recruta" AS
 SELECT "recruta_id",
    "forca",
    ("date_trunc"('month'::"text", "created_at"))::"date" AS "mes_referencia",
    "sum"("quantidade") AS "xp_total"
   FROM "public"."xp_eventos" "xe"
  GROUP BY "recruta_id", "forca", ("date_trunc"('month'::"text", "created_at"))
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_xp_mensal_recruta" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_ranking_mensal" AS
 SELECT "recruta_id",
    "forca",
    "mes_referencia",
    "xp_total",
    "rank"() OVER (PARTITION BY "forca", "mes_referencia" ORDER BY "xp_total" DESC) AS "posicao"
   FROM "public"."mv_xp_mensal_recruta" "x"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_ranking_mensal" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_campeao_mensal" AS
 SELECT "recruta_id",
    "forca",
    "mes_referencia"
   FROM "public"."mv_ranking_mensal" "r"
  WHERE ("posicao" = 1)
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_campeao_mensal" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."os_task_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "task_id" "uuid",
    "correlation_id" "uuid",
    "level" "text" DEFAULT 'info'::"text" NOT NULL,
    "event_type" "text" NOT NULL,
    "message" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "os_task_logs_level_check" CHECK (("level" = ANY (ARRAY['debug'::"text", 'info'::"text", 'warn'::"text", 'error'::"text"])))
);


ALTER TABLE "public"."os_task_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."patente_regras" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patente_id" "uuid" NOT NULL,
    "metrica" "text" NOT NULL,
    "operador" "text" DEFAULT '>='::"text" NOT NULL,
    "valor" integer NOT NULL,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."patente_regras" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."patentes_catalogo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "nivel" integer NOT NULL,
    "descricao" "text",
    "icone_url" "text",
    "ativo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."patentes_catalogo" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."premiacoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "periodo_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "descricao" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."premiacoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "username" "text",
    "nome" "text" NOT NULL,
    "role" "text" DEFAULT 'recruta'::"text",
    "nivel_atual" "text" DEFAULT 'Tropa Base'::"text",
    "ativo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "email" "text",
    "whatsapp" "text",
    "tipo_acesso" "text" DEFAULT 'degustacao'::"text",
    "origem" "text" DEFAULT 'app'::"text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "paid_at" timestamp with time zone,
    "xp" integer DEFAULT 0 NOT NULL,
    "forca" "text" DEFAULT 'marinha'::"text" NOT NULL,
    "patente" "text" DEFAULT 'Recruta'::"text" NOT NULL,
    "foto" "text",
    "instructor_profile_id" "text" DEFAULT 'objetivo'::"text",
    CONSTRAINT "chk_forca_profiles" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"]))),
    CONSTRAINT "instructor_profile_check" CHECK (("instructor_profile_id" = ANY (ARRAY['objetivo'::"text", 'estrategico'::"text", 'didatico'::"text"]))),
    CONSTRAINT "profiles_forca_check" CHECK (("forca" = ANY (ARRAY['marinha'::"text", 'exercito'::"text", 'aeronautica'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."profiles" IS 'CORE BLOCKED TABLE. Direct frontend access forbidden. Use RCC views and canonical RPCs only. RLS enabled.';



CREATE TABLE IF NOT EXISTS "public"."progresso_aulas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "aula_id" "uuid",
    "concluida" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"())
);


ALTER TABLE "public"."progresso_aulas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."progresso_missoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "missao_id" "uuid" NOT NULL,
    "concluida" boolean DEFAULT false,
    "concluida_em" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."progresso_missoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."progresso_recruta" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid",
    "licao_id" "uuid",
    "concluida" boolean DEFAULT false,
    "data_conclusao" timestamp with time zone
);


ALTER TABLE "public"."progresso_recruta" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_padrao_galeria" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "periodo_id" "uuid" NOT NULL,
    "foto_url" "text" NOT NULL,
    "aprovado" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."recruta_padrao_galeria" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."public_recrutas_padrao" AS
 SELECT "id",
    "periodo_id",
    "foto_url",
    "created_at"
   FROM "public"."recruta_padrao_galeria" "rpg"
  WHERE ("aprovado" = true)
  ORDER BY "created_at" DESC;


ALTER VIEW "public"."public_recrutas_padrao" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."qd_migration_rdm_lessons_20260503" (
    "lesson_id" "uuid" NOT NULL,
    "migrated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."qd_migration_rdm_lessons_20260503" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ranking_periodos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tipo" "text" NOT NULL,
    "inicio" "date" NOT NULL,
    "fim" "date" NOT NULL,
    "status" "text" DEFAULT 'ativo'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."ranking_periodos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ranking_resultados" (
    "periodo_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "posicao" integer NOT NULL,
    "xp_periodo" integer NOT NULL,
    "xp_merito" integer NOT NULL,
    "media_simulados" numeric,
    "foi_premiado" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."ranking_resultados" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_ciclo_status" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "ciclo_id" "uuid" NOT NULL,
    "semana_atual" integer DEFAULT 1 NOT NULL,
    "semanas_em_atraso_consec" integer DEFAULT 0 NOT NULL,
    "regularidade_status" "text" DEFAULT 'ok'::"text" NOT NULL,
    "comprometeu_em" timestamp with time zone,
    "criado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "atualizado_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "semanas_perfeitas_consec" integer DEFAULT 0 NOT NULL,
    "semanas_validas" integer DEFAULT 0 NOT NULL,
    "dias_validos" integer DEFAULT 0 NOT NULL,
    "ultima_semana_num" integer,
    "data_inicio_individual" "date",
    CONSTRAINT "recruta_ciclo_status_regularidade_status_check" CHECK (("regularidade_status" = ANY (ARRAY['regular'::"text", 'atencao'::"text", 'comprometida'::"text", 'recuperacao'::"text"])))
);


ALTER TABLE "public"."recruta_ciclo_status" OWNER TO "postgres";


COMMENT ON COLUMN "public"."recruta_ciclo_status"."data_inicio_individual" IS 'C6.2: Data de início individual do ciclo (base para semana_relativa e regularidade relativa).';



CREATE TABLE IF NOT EXISTS "public"."recruta_desempenho_revisoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "revisao_id" "uuid" NOT NULL,
    "percentual_acerto" integer NOT NULL,
    "tentativas" integer DEFAULT 1,
    "atualizado_em" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "recruta_desempenho_revisoes_percentual_acerto_check" CHECK ((("percentual_acerto" >= 0) AND ("percentual_acerto" <= 100)))
);


ALTER TABLE "public"."recruta_desempenho_revisoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_licoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "licao_id" "uuid" NOT NULL,
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."recruta_licoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_medalhas_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "medalha_evento_id" "uuid" NOT NULL,
    "concedida_em" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."recruta_medalhas_eventos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_modulos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "modulo_id" "uuid" NOT NULL,
    "liberado" boolean DEFAULT false NOT NULL,
    "liberado_em" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "first_access_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "degustacao_notificada" boolean DEFAULT false,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."recruta_modulos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_patentes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "patente_id" "uuid" NOT NULL,
    "promovido_em" timestamp with time zone DEFAULT "now"(),
    "motivo" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."recruta_patentes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_progresso" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "status" "text" NOT NULL,
    "completed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "xp_granted" integer DEFAULT 0 NOT NULL,
    "source" "text" DEFAULT 'lesson_completion'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "recruta_progresso_status_check" CHECK (("status" = 'completed'::"text"))
);


ALTER TABLE "public"."recruta_progresso" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recruta_progressos_modulos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "modulo_id" "uuid" NOT NULL,
    "aulas_concluidas" integer DEFAULT 0,
    "total_aulas" integer NOT NULL,
    "revisoes_concluidas" integer DEFAULT 0,
    "total_revisoes" integer NOT NULL,
    "concluido" boolean DEFAULT false,
    "atualizado_em" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."recruta_progressos_modulos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."revisoes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "missao_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "status" "text" NOT NULL,
    "origem" "text" NOT NULL,
    "xp_recompensa" integer DEFAULT 0,
    "criada_em" timestamp with time zone DEFAULT "now"(),
    "concluida_em" timestamp with time zone,
    CONSTRAINT "revisoes_origem_check" CHECK (("origem" = ANY (ARRAY['app'::"text", 'whatsapp'::"text"]))),
    CONSTRAINT "revisoes_status_check" CHECK (("status" = ANY (ARRAY['pendente'::"text", 'concluida'::"text"]))),
    CONSTRAINT "revisoes_tipo_check" CHECK (("tipo" = ANY (ARRAY['desempenho'::"text", 'espacada'::"text", 'whatsapp'::"text"])))
);


ALTER TABLE "public"."revisoes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."roles" (
    "id" integer NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "permissions" "jsonb" DEFAULT '{}'::"jsonb"
);


ALTER TABLE "public"."roles" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."roles_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."roles_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."roles_id_seq" OWNED BY "public"."roles"."id";



CREATE TABLE IF NOT EXISTS "public"."sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "token" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."usage_stats" (
    "id" integer NOT NULL,
    "user_id" "uuid",
    "route" "text",
    "tokens_used" integer DEFAULT 0,
    "latency_ms" integer,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."usage_stats" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."usage_stats_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."usage_stats_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."usage_stats_id_seq" OWNED BY "public"."usage_stats"."id";



CREATE TABLE IF NOT EXISTS "public"."user_xp" (
    "user_id" "uuid" NOT NULL,
    "xp_total" integer DEFAULT 0 NOT NULL,
    "xp_periodo" integer DEFAULT 0 NOT NULL,
    "xp_merito" integer DEFAULT 0 NOT NULL,
    "xp_constancia" integer DEFAULT 0 NOT NULL,
    "nivel" integer DEFAULT 1 NOT NULL,
    "last_xp_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."user_xp" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text" NOT NULL,
    "password_hash" "text",
    "display_name" "text",
    "role_id" integer,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_seen" timestamp with time zone
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."usuarios" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "thread_id" "text"
);


ALTER TABLE "public"."usuarios" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_identidade_recruta" AS
 SELECT "id",
    "id" AS "recruta_id",
    "auth_id",
    "nome" AS "nome_completo",
    "nome_guerra",
    COALESCE("nome_guerra", "nome") AS "nome_operacional",
    "email",
    "forca",
    "patente",
    "patente_virtual",
    "plano",
    "status",
    "data_pagamento",
    "validade",
    "onboarding_concluido",
    "created_at",
    "updated_at",
    "thread_id",
    "nome",
    NULL::integer AS "xp",
    NULL::"text" AS "avatar_url",
    "instructor_profile_id",
    "plano" AS "tipo_acesso",
    ("lower"(COALESCE("status", ''::"text")) = 'ativo'::"text") AS "ativo"
   FROM "public"."recrutas" "r"
  WHERE (("auth"."role"() = 'service_role'::"text") OR ("auth_id" = "auth"."uid"()));


ALTER VIEW "public"."v_identidade_recruta" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_identidade_recruta" IS 'CANONICAL RCC identity view. Direct source: recrutas. Legacy dependency removed.';



CREATE OR REPLACE VIEW "public"."v_app_bootstrap_institucional" AS
 SELECT "recruta_id",
    "auth_id",
    "nome_completo" AS "nome",
    "nome_guerra",
    "nome_operacional",
    "email",
    "forca",
    "patente",
    "patente_virtual",
    "status",
    "plano",
    "validade",
    "onboarding_concluido",
    "thread_id"
   FROM "public"."v_identidade_recruta" "v"
  WHERE ("auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_app_bootstrap_institucional" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_app_bootstrap_institucional" IS 'LEGACY BLOCKED. Replaced by public.v_app_bootstrap_institucional_rcc. Kept only for temporary backward compatibility. Do not expose to frontend.';



CREATE OR REPLACE VIEW "public"."v_app_bootstrap_institucional_rcc" WITH ("security_invoker"='true') AS
 SELECT "recruta_id",
    "nome",
    "nome_guerra",
    "nome_operacional",
    "forca",
    "patente",
    "patente_virtual",
    "status",
    "onboarding_concluido",
    'none'::"text" AS "subscription_state"
   FROM "public"."v_identidade_recruta";


ALTER VIEW "public"."v_app_bootstrap_institucional_rcc" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_app_bootstrap_institucional_rcc" IS 'CANONICAL RCC FRONTEND BOOTSTRAP. Safe institutional projection. Source: public.v_identidade_recruta.';



CREATE OR REPLACE VIEW "public"."v_execucao_diaria_dashboard" AS
 WITH "ciclo" AS (
         SELECT "v"."recruta_id",
            "v"."ciclo_id",
            "v"."forca",
            "v"."codigo",
            "v"."titulo",
            "v"."data_inicio",
            "v"."data_fim",
            "v"."semanas_total",
            "v"."vigente"
           FROM "public"."v_recruta_ciclo_atual" "v"
        )
 SELECT "ciclo"."recruta_id",
    "ciclo"."ciclo_id",
    "public"."calcular_semana_relativa"("ciclo"."recruta_id") AS "semana_atual",
    COALESCE("cr"."data_inicio", ("cs"."data_inicio_individual" + (("public"."calcular_semana_relativa"("ciclo"."recruta_id") - 1) * 7))) AS "semana_inicio",
    COALESCE("cr"."data_fim", (("cs"."data_inicio_individual" + (("public"."calcular_semana_relativa"("ciclo"."recruta_id") - 1) * 7)) + 6)) AS "semana_fim",
    COALESCE("cr"."titulo", ('Semana '::"text" || ("public"."calcular_semana_relativa"("ciclo"."recruta_id"))::"text")) AS "semana_titulo",
    "cs"."semanas_em_atraso_consec",
    "cs"."regularidade_status",
    "cs"."comprometeu_em"
   FROM (("ciclo"
     JOIN "public"."recruta_ciclo_status" "cs" ON ((("cs"."recruta_id" = "ciclo"."recruta_id") AND ("cs"."ciclo_id" = "ciclo"."ciclo_id"))))
     LEFT JOIN "public"."cronograma_semanal" "cr" ON ((("cr"."ciclo_id" = "ciclo"."ciclo_id") AND ("cr"."semana_num" = (("public"."fn_semana_base_calendario"("ciclo"."ciclo_id", "cs"."data_inicio_individual") + "public"."calcular_semana_relativa"("ciclo"."recruta_id")) - 1)))));


ALTER VIEW "public"."v_execucao_diaria_dashboard" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_execucao_diaria_dashboard" IS 'C6.2: Execução diária (semana_atual/intervalo) em base relativa, preservando contrato.';



CREATE OR REPLACE VIEW "public"."v_execucao_diaria_dashboard_expandido" AS
 WITH "base" AS (
         SELECT "d"."recruta_id",
            "d"."ciclo_id",
            "d"."semana_atual",
            "d"."semana_inicio",
            "d"."semana_fim",
            "d"."semana_titulo",
            "d"."semanas_em_atraso_consec",
            "d"."regularidade_status",
            "d"."comprometeu_em"
           FROM "public"."v_execucao_diaria_dashboard" "d"
        ), "ciclo" AS (
         SELECT "cf"."id" AS "ciclo_id",
            "cf"."data_inicio",
            "cf"."data_fim",
            "cf"."semanas_total"
           FROM "public"."ciclos_formativos" "cf"
        ), "c6" AS (
         SELECT "rcs"."recruta_id",
            "rcs"."ciclo_id",
            "rcs"."semanas_validas",
            "rcs"."dias_validos",
            "rcs"."ultima_semana_num",
            "rcs"."data_inicio_individual"
           FROM "public"."recruta_ciclo_status" "rcs"
        ), "xp" AS (
         SELECT "b1"."recruta_id",
            "b1"."ciclo_id",
            (COALESCE("sum"("xe"."quantidade"), (0)::bigint))::integer AS "xp_ciclo"
           FROM (("base" "b1"
             JOIN "ciclo" "c1" ON (("c1"."ciclo_id" = "b1"."ciclo_id")))
             LEFT JOIN "public"."xp_eventos" "xe" ON ((("xe"."recruta_id" = "b1"."recruta_id") AND ("xe"."created_at" >= ("c1"."data_inicio")::timestamp with time zone) AND ("xe"."created_at" < (("c1"."data_fim")::timestamp with time zone + '1 day'::interval)))))
          GROUP BY "b1"."recruta_id", "b1"."ciclo_id"
        ), "iea" AS (
         SELECT "v"."recruta_id",
            "v"."ciclo_id",
            "v"."iea_score",
            "v"."conceito",
            "v"."calculado_em",
            "v"."calculado_em_br"
           FROM "public"."v_iea_atual" "v"
        )
 SELECT "b"."recruta_id",
    "b"."ciclo_id",
    "b"."semana_atual",
    "b"."semana_inicio",
    "b"."semana_fim",
    "b"."semana_titulo",
    "b"."semanas_em_atraso_consec",
    "b"."regularidade_status" AS "status_regularidade",
    "b"."comprometeu_em",
    12 AS "semanas_total",
    COALESCE("c6"."semanas_validas", 0) AS "semanas_validas",
        CASE
            WHEN ("c6"."data_inicio_individual" IS NULL) THEN NULL::numeric
            WHEN (CURRENT_DATE < "c6"."data_inicio_individual") THEN NULL::numeric
            ELSE "public"."calcular_regularidade_relativa"("b"."recruta_id")
        END AS "regularidade_percentual",
    COALESCE("i"."iea_score", 0) AS "iea_score",
    "i"."conceito" AS "iea_conceito",
    "i"."calculado_em" AS "iea_calculado_em_utc",
    "i"."calculado_em_br" AS "iea_calculado_em_br",
    COALESCE("x"."xp_ciclo", 0) AS "xp_ciclo",
    COALESCE("c6"."dias_validos", 0) AS "dias_validos",
    "c6"."ultima_semana_num",
    "c"."semanas_total" AS "semanas_total_ciclo"
   FROM (((("base" "b"
     LEFT JOIN "ciclo" "c" ON (("c"."ciclo_id" = "b"."ciclo_id")))
     LEFT JOIN "c6" ON ((("c6"."recruta_id" = "b"."recruta_id") AND ("c6"."ciclo_id" = "b"."ciclo_id"))))
     LEFT JOIN "xp" "x" ON ((("x"."recruta_id" = "b"."recruta_id") AND ("x"."ciclo_id" = "b"."ciclo_id"))))
     LEFT JOIN "iea" "i" ON ((("i"."recruta_id" = "b"."recruta_id") AND (NOT ("i"."ciclo_id" IS DISTINCT FROM "b"."ciclo_id")))));


ALTER VIEW "public"."v_execucao_diaria_dashboard_expandido" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_execucao_diaria_dashboard_expandido" IS 'C6.2: Expandido com regularidade_percentual relativa (semanas_validas/12) e semanas_total_ciclo para auditoria.';



CREATE OR REPLACE VIEW "public"."v_assiduidade_ouro_status" AS
 SELECT "recruta_id",
    "ciclo_id",
    (("regularidade_percentual" IS NOT NULL) AND ("regularidade_percentual" >= 0.70)) AS "ok",
        CASE
            WHEN ("ciclo_id" IS NULL) THEN 'SEM_CICLO_VIGENTE'::"text"
            WHEN ("regularidade_percentual" IS NULL) THEN 'CICLO_NAO_INICIADO'::"text"
            WHEN ("regularidade_percentual" >= 0.70) THEN 'OK'::"text"
            ELSE 'REGULARIDADE_INFERIOR_A_70_PORCENTO'::"text"
        END AS "detalhe"
   FROM "public"."v_execucao_diaria_dashboard_expandido" "d";


ALTER VIEW "public"."v_assiduidade_ouro_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_audit_eventos" AS
 SELECT "gen_random_uuid"() AS "event_id",
    "lp"."user_id",
    "l"."force",
    'lesson_completed'::"text" AS "event_type",
    "lp"."lesson_id" AS "reference_id",
    ("lp"."completed_at" AT TIME ZONE 'utc'::"text") AS "event_timestamp",
    'app'::"text" AS "event_origin"
   FROM ("public"."lesson_progress" "lp"
     JOIN "public"."lessons" "l" ON (("l"."id" = "lp"."lesson_id")))
  WHERE ("lp"."completed_at" IS NOT NULL)
UNION ALL
 SELECT "gen_random_uuid"() AS "event_id",
    "xe"."recruta_id" AS "user_id",
    "xe"."forca" AS "force",
    'xp_granted'::"text" AS "event_type",
    "xe"."id" AS "reference_id",
    ("xe"."created_at" AT TIME ZONE 'utc'::"text") AS "event_timestamp",
    'system'::"text" AS "event_origin"
   FROM "public"."xp_eventos" "xe"
UNION ALL
 SELECT "gen_random_uuid"() AS "event_id",
    "mc"."recruta_id" AS "user_id",
    "m"."categoria" AS "force",
    'medal_granted'::"text" AS "event_type",
    "mc"."medalha_id" AS "reference_id",
    ("mc"."granted_at" AT TIME ZONE 'utc'::"text") AS "event_timestamp",
    'system'::"text" AS "event_origin"
   FROM ("public"."medalhas_concedidas" "mc"
     JOIN "public"."medalhas_catalogo" "m" ON (("m"."id" = "mc"."medalha_id")));


ALTER VIEW "public"."v_audit_eventos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_audit_medalhas" AS
 SELECT "mc"."recruta_id",
    "m"."categoria" AS "force",
    "mc"."medalha_id",
    "m"."titulo" AS "medalha_nome",
    ("mc"."granted_at" AT TIME ZONE 'utc'::"text") AS "data_concessao",
    'Critérios previstos em regulamento vigente'::"text" AS "criterios_atendidos",
    ( SELECT "jsonb_agg"("jsonb_build_object"('event_id', "ae"."event_id", 'event_type', "ae"."event_type", 'event_timestamp', "ae"."event_timestamp") ORDER BY "ae"."event_timestamp") AS "jsonb_agg"
           FROM "public"."v_audit_eventos" "ae"
          WHERE (("ae"."user_id" = "mc"."recruta_id") AND ("ae"."force" = "m"."categoria") AND ("ae"."event_timestamp" <= "mc"."granted_at"))) AS "eventos_fundamentadores",
    'Regulamento vigente — versão institucional C5'::"text" AS "versao_regulamento"
   FROM ("public"."medalhas_concedidas" "mc"
     JOIN "public"."medalhas_catalogo" "m" ON (("m"."id" = "mc"."medalha_id")));


ALTER VIEW "public"."v_audit_medalhas" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_audit_xp" AS
 SELECT "xe"."recruta_id",
    "xe"."forca" AS "force",
    "xe"."quantidade" AS "xp_value",
    'institucional'::"text" AS "xp_type",
    NULL::"uuid" AS "aula_id",
    NULL::"uuid" AS "quiz_id",
    "ae"."event_id",
    ("xe"."created_at" AT TIME ZONE 'utc'::"text") AS "event_timestamp",
    "xe"."origem" AS "fundamento_normativo"
   FROM ("public"."xp_eventos" "xe"
     JOIN "public"."v_audit_eventos" "ae" ON ((("ae"."reference_id" = "xe"."id") AND ("ae"."event_type" = 'xp_granted'::"text"))))
UNION ALL
 SELECT "ae"."user_id" AS "recruta_id",
    "ae"."force",
    "xe"."quantidade" AS "xp_value",
    'aula'::"text" AS "xp_type",
    "ae"."reference_id" AS "aula_id",
    NULL::"uuid" AS "quiz_id",
    "ae"."event_id",
    "ae"."event_timestamp",
    'Conclusão de Aula'::"text" AS "fundamento_normativo"
   FROM ("public"."v_audit_eventos" "ae"
     JOIN "public"."xp_eventos" "xe" ON ((("xe"."recruta_id" = "ae"."user_id") AND ("xe"."origem" = 'lesson_completed'::"text"))))
  WHERE ("ae"."event_type" = 'lesson_completed'::"text")
UNION ALL
 SELECT "ae"."user_id" AS "recruta_id",
    "ae"."force",
    "xe"."quantidade" AS "xp_value",
    'quiz_merito'::"text" AS "xp_type",
    NULL::"uuid" AS "aula_id",
    "ae"."reference_id" AS "quiz_id",
    "ae"."event_id",
    "ae"."event_timestamp",
    'Quiz — 100% na 1ª tentativa'::"text" AS "fundamento_normativo"
   FROM ("public"."v_audit_eventos" "ae"
     JOIN "public"."xp_eventos" "xe" ON ((("xe"."recruta_id" = "ae"."user_id") AND ("xe"."origem" = 'quiz_perfect_first_try'::"text"))))
  WHERE ("ae"."event_type" = 'quiz_perfect_first_try'::"text");


ALTER VIEW "public"."v_audit_xp" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_auth_active_sessions" AS
 SELECT "auth_id",
    "current_client_instance_id" AS "client_instance_id",
    (('Cliente institucional ['::"text" || "substr"("md5"("current_client_instance_id"), 1, 8)) || ']'::"text") AS "device_name",
    "updated_at" AS "last_seen_at",
    true AS "is_current"
   FROM "public"."auth_client_singleton" "s"
  WHERE ("auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_auth_active_sessions" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_auth_active_sessions" IS 'View read-only canônica do AUTH DOMAIN. Compatível com o modelo singleton do RCC v0.3. Lista apenas o cliente vigente visível ao auth.uid(); não representa multi-device pleno. device_name é técnico/neutro e last_seen_at deriva de updated_at.';



CREATE OR REPLACE VIEW "public"."v_auth_app_config" AS
 SELECT false AS "requires_mfa_globally",
    30 AS "inactivity_days_limit",
    false AS "lock_policy_enabled",
    'RCC-0.5'::"text" AS "auth_contract_version";


ALTER VIEW "public"."v_auth_app_config" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_auth_login_methods" AS
 SELECT "auth"."uid"() AS "auth_id",
    'password'::"text" AS "method",
    true AS "enabled"
  WHERE ("auth"."uid"() IS NOT NULL);


ALTER VIEW "public"."v_auth_login_methods" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_auth_mfa_status" AS
 SELECT "auth"."uid"() AS "auth_id",
    false AS "mfa_enabled",
    false AS "mfa_required",
    false AS "mfa_verified_recently",
    NULL::timestamp with time zone AS "last_mfa_at"
  WHERE ("auth"."uid"() IS NOT NULL);


ALTER VIEW "public"."v_auth_mfa_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_auth_session" AS
 SELECT "auth"."uid"() AS "auth_id",
    "id" AS "recruta_id",
    "email",
        CASE
            WHEN ("status" = 'ativo'::"text") THEN 'active'::"text"
            WHEN ("status" = 'bloqueado'::"text") THEN 'locked'::"text"
            WHEN ("status" = 'inativo'::"text") THEN 'inactive'::"text"
            ELSE 'active'::"text"
        END AS "status_conta",
    false AS "requires_mfa",
    false AS "account_locked",
    false AS "password_expired",
        CASE
            WHEN ("status" = 'inativo'::"text") THEN true
            ELSE false
        END AS "inactive_user",
    "updated_at" AS "ultima_atividade",
    "now"() AS "session_checked_at",
    'none'::"text" AS "session_revoked_reason"
   FROM "public"."recrutas" "r"
  WHERE ("auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_auth_session" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_billing_status_recruta" AS
 WITH "base" AS (
         SELECT "r"."id" AS "recruta_id",
            "r"."auth_id",
            COALESCE("ba"."plano", "r"."plano", 'basico'::"text") AS "plano_atual",
            COALESCE("ba"."status_assinatura",
                CASE
                    WHEN (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())) >= "now"()) THEN 'trial'::"text"
                    ELSE 'sem_assinatura'::"text"
                END) AS "status_assinatura",
                CASE
                    WHEN ("ba"."status_assinatura" = 'trial'::"text") THEN COALESCE("ba"."trial_fim", (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())))::timestamp with time zone)
                    WHEN ("ba"."status_assinatura" = 'ativa'::"text") THEN COALESCE("ba"."vigente_fim", ("r"."validade")::timestamp with time zone)
                    WHEN (("ba"."status_assinatura" IS NULL) AND (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())) >= "now"())) THEN (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())))::timestamp with time zone
                    ELSE COALESCE("ba"."vigente_fim", ("r"."validade")::timestamp with time zone)
                END AS "validade",
                CASE
                    WHEN ("ba"."status_assinatura" = 'trial'::"text") THEN (GREATEST((0)::numeric, "ceil"((EXTRACT(epoch FROM (COALESCE("ba"."trial_fim", (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())))::timestamp with time zone) - "now"())) / 86400.0))))::integer
                    WHEN (("ba"."status_assinatura" IS NULL) AND (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())) >= "now"())) THEN (GREATEST((0)::numeric, "ceil"((EXTRACT(epoch FROM ((("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())))::timestamp with time zone - "now"())) / 86400.0))))::integer
                    ELSE 0
                END AS "trial_restante",
                CASE
                    WHEN (("ba"."status_assinatura" = 'ativa'::"text") AND (COALESCE("ba"."vigente_fim", ("r"."validade")::timestamp with time zone, "now"()) >= "now"())) THEN true
                    WHEN (("ba"."status_assinatura" = 'trial'::"text") AND (COALESCE("ba"."trial_fim", (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())))::timestamp with time zone) >= "now"())) THEN true
                    WHEN (("ba"."status_assinatura" IS NULL) AND (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())) >= "now"())) THEN true
                    WHEN (("r"."validade" IS NOT NULL) AND ("r"."validade" >= "now"())) THEN true
                    ELSE false
                END AS "acesso_liberado",
                CASE
                    WHEN (("ba"."status_assinatura" = 'ativa'::"text") AND (COALESCE("ba"."vigente_fim", ("r"."validade")::timestamp with time zone, "now"()) >= "now"())) THEN 'assinatura_ativa'::"text"
                    WHEN (("ba"."status_assinatura" = 'trial'::"text") AND (COALESCE("ba"."trial_fim", (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())))::timestamp with time zone) >= "now"())) THEN 'trial_assinatura'::"text"
                    WHEN (("ba"."status_assinatura" IS NULL) AND (("r"."created_at" + "make_interval"("days" => "public"."fn_billing_trial_dias"())) >= "now"())) THEN 'trial_implicito'::"text"
                    WHEN ("ba"."status_assinatura" = ANY (ARRAY['inadimplente'::"text", 'cancelada'::"text", 'expirada'::"text", 'suspensa'::"text"])) THEN 'sem_acesso_billing'::"text"
                    WHEN (("r"."validade" IS NOT NULL) AND ("r"."validade" >= "now"())) THEN 'validade_legacy'::"text"
                    ELSE 'sem_acesso'::"text"
                END AS "origem_status"
           FROM ("public"."recrutas" "r"
             LEFT JOIN "public"."billing_assinaturas" "ba" ON (("ba"."recruta_id" = "r"."id")))
        )
 SELECT "recruta_id",
    "auth_id",
    "plano_atual",
    "status_assinatura",
    "validade",
    "trial_restante",
    "acesso_liberado",
    "origem_status"
   FROM "base" "b"
  WHERE (("auth"."role"() = 'service_role'::"text") OR ("auth_id" = "auth"."uid"()));


ALTER VIEW "public"."v_billing_status_recruta" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_billing_status_recruta_v2" AS
 SELECT "recruta_id",
    "acesso_liberado",
    "plano_atual",
    "status_assinatura",
    "validade",
    "trial_restante"
   FROM "public"."v_billing_status_recruta";


ALTER VIEW "public"."v_billing_status_recruta_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_billing_trial_monitoramento" AS
 SELECT "recruta_id",
    "auth_id",
    "plano_atual",
    "validade",
    "trial_restante",
    "acesso_liberado",
        CASE
            WHEN ("origem_status" <> ALL (ARRAY['trial_assinatura'::"text", 'trial_implicito'::"text"])) THEN 'nao_trial'::"text"
            WHEN ("validade" IS NULL) THEN 'trial_indefinido'::"text"
            WHEN (("validade" >= "now"()) AND ("trial_restante" > 0)) THEN 'trial_expirando'::"text"
            WHEN ("validade" < "now"()) THEN 'trial_expirado'::"text"
            ELSE 'nao_trial'::"text"
        END AS "estado_trial"
   FROM "public"."v_billing_status_recruta" "v"
  WHERE (("auth"."role"() = 'service_role'::"text") OR ("auth_id" = "auth"."uid"()));


ALTER VIEW "public"."v_billing_trial_monitoramento" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c5_backlog_nao_consumido" AS
 SELECT "id" AS "evento_id",
    "recruta_id",
    "tipo_evento",
    "correlation_id",
    "origem",
    "status",
    "created_at"
   FROM "public"."c5_eventos_view" "e"
  WHERE ("status" = ANY (ARRAY['received'::"text", 'failed'::"text"]));


ALTER VIEW "public"."v_c5_backlog_nao_consumido" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c5_backlog_nao_consumido" IS 'Observabilidade C5 (read-only): backlog operacional (status received/failed). Se houver tabela de consumo formal (ex.: eventos_consumidos), aplicar patch para excluir consumidos via JOIN/NOT EXISTS.';



CREATE OR REPLACE VIEW "public"."v_c5_duplicados_recentes" AS
 SELECT "id" AS "evento_id",
    "recruta_id",
    "tipo_evento",
    "idempotency_key",
    "correlation_id",
    "origem",
    "created_at",
    "status"
   FROM "public"."c5_eventos_view" "e"
  WHERE (("status" = 'duplicate'::"text") AND ("created_at" >= ("now"() - '7 days'::interval)));


ALTER VIEW "public"."v_c5_duplicados_recentes" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c5_duplicados_recentes" IS 'Observabilidade C5 (read-only): duplicados recentes (últimos 7 dias) via public.c5_eventos_view. Inclui coluna status ao final para validação operacional.';



CREATE OR REPLACE VIEW "public"."v_c5_eventos_dominios" AS
 SELECT "id" AS "id_evento",
    "recruta_id" AS "id_recruta",
    "tipo",
    "origem",
    COALESCE(NULLIF("btrim"("tipo_evento"), ''::"text"), "tipo") AS "evento",
    "emitido_em" AS "timestamp_evento",
    "created_at" AS "criado_em",
    "payload" AS "metadata",
        CASE
            WHEN (NULLIF("btrim"("tipo_evento"), ''::"text") = 'auth'::"text") THEN 'auth'::"text"
            WHEN (NULLIF("btrim"("tipo_evento"), ''::"text") IS NOT NULL) THEN "lower"("btrim"("tipo_evento"))
            WHEN ("tipo" = ANY (ARRAY['medalha'::"text", 'patente'::"text"])) THEN "tipo"
            ELSE COALESCE(NULLIF("lower"("btrim"("tipo")), ''::"text"), 'desconhecido'::"text")
        END AS "dominio_analitico",
        CASE
            WHEN (NULLIF("btrim"("tipo_evento"), ''::"text") = 'auth'::"text") THEN false
            WHEN ((NULLIF("btrim"("tipo_evento"), ''::"text") IS NULL) AND ("tipo" = 'medalha'::"text") AND ("origem" = 'auth'::"text")) THEN true
            ELSE false
        END AS "legado_auth",
    "idempotency_key",
    "correlation_id",
    "status",
    "error",
    "titulo",
    "descricao",
    "referencia_id"
   FROM "public"."eventos_institucionais" "e";


ALTER VIEW "public"."v_c5_eventos_dominios" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c5_eventos_dominios" IS 'View read-only analítica de domínios C5. Prioriza tipo_evento, usa tipo como fallback legado e classifica auth sem alterar eventos históricos.';



CREATE OR REPLACE VIEW "public"."v_c5_eventos_dominios_v2" AS
 SELECT "id" AS "id_evento",
    "recruta_id" AS "id_recruta",
    "tipo",
    "origem",
    COALESCE(NULLIF("btrim"("tipo_evento"), ''::"text"), "tipo") AS "evento_analitico",
        CASE
            WHEN (NULLIF("btrim"("tipo_evento"), ''::"text") = 'auth'::"text") THEN 'auth'::"text"
            WHEN (NULLIF("btrim"("tipo_evento"), ''::"text") = 'CHAT-MSG'::"text") THEN 'mensageria'::"text"
            WHEN (NULLIF("btrim"("tipo_evento"), ''::"text") ~~ 'QD-%'::"text") THEN 'workflow'::"text"
            WHEN ((NULLIF("btrim"("tipo_evento"), ''::"text") IS NULL) AND ("tipo" = 'medalha'::"text")) THEN 'medalha'::"text"
            WHEN ((NULLIF("btrim"("tipo_evento"), ''::"text") IS NULL) AND ("tipo" = 'patente'::"text")) THEN 'patente'::"text"
            ELSE 'outros'::"text"
        END AS "dominio_analitico",
    "emitido_em" AS "timestamp_evento",
    "created_at" AS "criado_em",
    "payload" AS "metadata",
        CASE
            WHEN (("tipo" = 'medalha'::"text") AND (NULLIF("btrim"("tipo_evento"), ''::"text") IS NULL) AND ("origem" = 'auth'::"text")) THEN true
            ELSE false
        END AS "legado_auth",
    "idempotency_key",
    "correlation_id",
    "status",
    "error",
    "titulo",
    "descricao",
    "referencia_id"
   FROM "public"."eventos_institucionais" "ei";


ALTER VIEW "public"."v_c5_eventos_dominios_v2" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c5_eventos_dominios_v2" IS 'View read-only analítica C5 v2. Separa evento_analitico (granular) de dominio_analitico (agrupador estável). Base física: public.eventos_institucionais. Preserva compatibilidade com v1 e fallback legado.';



CREATE OR REPLACE VIEW "public"."v_c5_eventos_dominios_v3" AS
 SELECT "e"."id" AS "id_evento",
    "e"."recruta_id" AS "id_recruta",
    "e"."tipo",
    "e"."tipo_evento",
    "e"."origem",
    COALESCE("t"."evento_analitico", "e"."tipo_evento", "e"."tipo") AS "evento_analitico",
        CASE
            WHEN ("t"."dominio_analitico" IS NOT NULL) THEN "t"."dominio_analitico"
            WHEN ("e"."tipo" = 'auth'::"text") THEN 'auth'::"text"
            WHEN (("e"."tipo" = 'medalha'::"text") AND ("e"."tipo_evento" = 'auth'::"text")) THEN 'auth'::"text"
            WHEN ("e"."tipo" = 'medalha'::"text") THEN 'medalha'::"text"
            WHEN ("e"."tipo" = 'patente'::"text") THEN 'patente'::"text"
            ELSE 'outros'::"text"
        END AS "dominio_analitico",
    "e"."payload" AS "metadata",
    "e"."emitido_em" AS "timestamp_evento",
    "e"."created_at" AS "criado_em",
    "e"."idempotency_key",
    "e"."correlation_id",
    "e"."status",
    "e"."error",
    "e"."titulo",
    "e"."descricao",
    "e"."referencia_id"
   FROM ("public"."eventos_institucionais" "e"
     LEFT JOIN "public"."c5_taxonomia_eventos" "t" ON ((("t"."tipo_evento" = "e"."tipo_evento") AND ("t"."ativo" = true))));


ALTER VIEW "public"."v_c5_eventos_dominios_v3" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c5_eventos_por_recruta_resumo" AS
 SELECT "recruta_id",
    "count"(*) AS "total_eventos",
    "count"(*) FILTER (WHERE ("status" = 'duplicate'::"text")) AS "total_duplicate",
    "count"(*) FILTER (WHERE ("status" = 'failed'::"text")) AS "total_failed",
    "max"("created_at") AS "ultima_emissao_at"
   FROM "public"."c5_eventos_view" "e"
  WHERE ("created_at" >= ("now"() - '7 days'::interval))
  GROUP BY "recruta_id";


ALTER VIEW "public"."v_c5_eventos_por_recruta_resumo" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c5_eventos_por_recruta_resumo" IS 'Observabilidade C5 (read-only): volume por recruta (últimos 7 dias) via public.c5_eventos_view.';



CREATE OR REPLACE VIEW "public"."v_c5_idempotencia_taxa" AS
 SELECT "origem",
    "tipo_evento",
    "count"(*) AS "total_eventos",
    "count"(*) FILTER (WHERE ("status" = 'duplicate'::"text")) AS "total_duplicate",
    "round"(((("count"(*) FILTER (WHERE ("status" = 'duplicate'::"text")))::numeric * 100.0) / NULLIF(("count"(*))::numeric, (0)::numeric)), 2) AS "perc_duplicate"
   FROM "public"."c5_eventos_view" "e"
  WHERE ("created_at" >= ("now"() - '7 days'::interval))
  GROUP BY "origem", "tipo_evento";


ALTER VIEW "public"."v_c5_idempotencia_taxa" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c5_idempotencia_taxa" IS 'Observabilidade C5 (read-only): taxa de duplicidade por origem e tipo_evento (últimos 7 dias), via public.c5_eventos_view.';



CREATE OR REPLACE VIEW "public"."v_c5_metricas_operacionais" AS
 SELECT "date_trunc"('day'::"text", "timestamp_evento") AS "dia",
    "dominio_analitico",
    "evento_analitico",
    "count"(*) AS "total_eventos"
   FROM "public"."v_c5_eventos_dominios_v3"
  GROUP BY ("date_trunc"('day'::"text", "timestamp_evento")), "dominio_analitico", "evento_analitico";


ALTER VIEW "public"."v_c5_metricas_operacionais" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c5_metricas_recruta" AS
 SELECT "id_recruta",
    "date_trunc"('day'::"text", "timestamp_evento") AS "dia",
    "dominio_analitico",
    "evento_analitico",
    "count"(*) AS "total_eventos"
   FROM "public"."v_c5_eventos_dominios_v3"
  GROUP BY "id_recruta", ("date_trunc"('day'::"text", "timestamp_evento")), "dominio_analitico", "evento_analitico";


ALTER VIEW "public"."v_c5_metricas_recruta" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c5_origens_volume_diario" AS
 SELECT ("date_trunc"('day'::"text", "created_at"))::"date" AS "dia",
    "origem",
    "count"(*) AS "total_eventos",
    "count"(*) FILTER (WHERE ("status" = 'failed'::"text")) AS "total_failed",
    "count"(*) FILTER (WHERE ("status" = 'duplicate'::"text")) AS "total_duplicate"
   FROM "public"."c5_eventos_view" "e"
  WHERE ("created_at" >= ("now"() - '30 days'::interval))
  GROUP BY (("date_trunc"('day'::"text", "created_at"))::"date"), "origem";


ALTER VIEW "public"."v_c5_origens_volume_diario" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c5_origens_volume_diario" IS 'Observabilidade C5 (read-only): série diária por origem (últimos 30 dias) via public.c5_eventos_view.';



CREATE OR REPLACE VIEW "public"."v_c5_saude_resumo" AS
 WITH "base" AS (
         SELECT "e"."status",
            "e"."error",
            "e"."created_at"
           FROM "public"."c5_eventos_view" "e"
        ), "agg_total" AS (
         SELECT 'total'::"text" AS "periodo",
            "count"(*) AS "total_eventos_c5",
            "count"(*) FILTER (WHERE ("base"."status" = 'received'::"text")) AS "total_received",
            "count"(*) FILTER (WHERE ("base"."status" = 'processed'::"text")) AS "total_processed",
            "count"(*) FILTER (WHERE ("base"."status" = 'duplicate'::"text")) AS "total_duplicate",
            "count"(*) FILTER (WHERE ("base"."status" = 'failed'::"text")) AS "total_failed",
            "count"(*) FILTER (WHERE ("base"."error" IS NOT NULL)) AS "total_com_error",
            "max"("base"."created_at") AS "ultima_emissao_at",
            "max"("base"."created_at") AS "ultima_atualizacao_at"
           FROM "base"
        ), "agg_24h" AS (
         SELECT '24h'::"text" AS "periodo",
            "count"(*) AS "total_eventos_c5",
            "count"(*) FILTER (WHERE ("base"."status" = 'received'::"text")) AS "total_received",
            "count"(*) FILTER (WHERE ("base"."status" = 'processed'::"text")) AS "total_processed",
            "count"(*) FILTER (WHERE ("base"."status" = 'duplicate'::"text")) AS "total_duplicate",
            "count"(*) FILTER (WHERE ("base"."status" = 'failed'::"text")) AS "total_failed",
            "count"(*) FILTER (WHERE ("base"."error" IS NOT NULL)) AS "total_com_error",
            "max"("base"."created_at") AS "ultima_emissao_at",
            "max"("base"."created_at") AS "ultima_atualizacao_at"
           FROM "base"
          WHERE ("base"."created_at" >= ("now"() - '24:00:00'::interval))
        )
 SELECT "agg_24h"."periodo",
    "agg_24h"."total_eventos_c5",
    "agg_24h"."total_received",
    "agg_24h"."total_processed",
    "agg_24h"."total_duplicate",
    "agg_24h"."total_failed",
    "agg_24h"."total_com_error",
    "agg_24h"."ultima_emissao_at",
    "agg_24h"."ultima_atualizacao_at"
   FROM "agg_24h"
UNION ALL
 SELECT "agg_total"."periodo",
    "agg_total"."total_eventos_c5",
    "agg_total"."total_received",
    "agg_total"."total_processed",
    "agg_total"."total_duplicate",
    "agg_total"."total_failed",
    "agg_total"."total_com_error",
    "agg_total"."ultima_emissao_at",
    "agg_total"."ultima_atualizacao_at"
   FROM "agg_total";


ALTER VIEW "public"."v_c5_saude_resumo" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c5_saude_resumo" IS 'Observabilidade C5 (read-only): resumo de saúde em duas janelas (24h e total), baseado em public.c5_eventos_view.';



CREATE OR REPLACE VIEW "public"."v_c6_contracts_validos" AS
 SELECT "contract_name",
    "contract_type",
    "status",
    "frontend_scope"
   FROM "public"."c6_contract_registry"
  WHERE ("status" = ANY (ARRAY['canonical'::"text", 'system'::"text"]));


ALTER VIEW "public"."v_c6_contracts_validos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_bloqueio_oficial" AS
 WITH "me" AS (
         SELECT "r"."id" AS "recruta_id"
           FROM "public"."recrutas" "r"
          WHERE ("r"."auth_id" = "auth"."uid"())
         LIMIT 1
        ), "ciclo" AS (
         SELECT "c_1"."id" AS "ciclo_id",
            "c_1"."slug" AS "ciclo_slug"
           FROM "public"."c7_ciclos" "c_1"
          WHERE ("c_1"."active" = true)
         LIMIT 1
        ), "regras" AS (
         SELECT "rc"."ciclo_id",
            "rc"."medalha_slug",
            "rc"."tipo_regra",
            "rc"."descricao"
           FROM ("public"."c7_regras_bloqueio_por_ciclo" "rc"
             JOIN "ciclo" "ciclo_1" ON (("ciclo_1"."ciclo_id" = "rc"."ciclo_id")))
          WHERE (("rc"."active" = true) AND ("rc"."tipo_regra" = 'ausencia'::"text"))
        ), "concedidas" AS (
         SELECT "mc"."recruta_id",
            "cat"."slug" AS "medalha_slug"
           FROM (("public"."medalhas_concedidas" "mc"
             JOIN "public"."medalhas_catalogo" "cat" ON (("cat"."id" = "mc"."medalha_id")))
             JOIN "me" "me_1" ON (("me_1"."recruta_id" = "mc"."recruta_id")))
          WHERE ("cat"."active" = true)
        )
 SELECT "me"."recruta_id",
    "ciclo"."ciclo_id",
    "ciclo"."ciclo_slug",
    "regras"."medalha_slug" AS "medalha_obrigatoria_slug",
    "regras"."descricao" AS "motivo_bloqueio",
    "now"() AS "avaliado_em"
   FROM ((("me"
     CROSS JOIN "ciclo")
     JOIN "regras" ON (true))
     LEFT JOIN "concedidas" "c" ON ((("c"."recruta_id" = "me"."recruta_id") AND ("c"."medalha_slug" = "regras"."medalha_slug"))))
  WHERE ("c"."medalha_slug" IS NULL);


ALTER VIEW "public"."v_c7_bloqueio_oficial" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c7_bloqueio_oficial" IS 'C7 Bloqueio Oficial (v1): bloqueios = medalhas obrigatórias AUSENTES, por ciclo ativo. Fonte: medalhas_concedidas.';



CREATE OR REPLACE VIEW "public"."v_c7_bloqueio_oficial_admin" AS
 WITH "ciclo" AS (
         SELECT "c_1"."id" AS "ciclo_id",
            "c_1"."slug" AS "ciclo_slug"
           FROM "public"."c7_ciclos" "c_1"
          WHERE ("c_1"."active" = true)
          ORDER BY "c_1"."created_at" DESC
         LIMIT 1
        ), "regras" AS (
         SELECT "rc"."ciclo_id",
            "rc"."medalha_slug",
            "rc"."tipo_regra",
            "rc"."descricao"
           FROM ("public"."c7_regras_bloqueio_por_ciclo" "rc"
             JOIN "ciclo" "c_1" ON (("c_1"."ciclo_id" = "rc"."ciclo_id")))
          WHERE (("rc"."active" = true) AND ("rc"."tipo_regra" = 'ausencia'::"text"))
        ), "concedidas" AS (
         SELECT "mc"."recruta_id",
            "cat"."slug" AS "medalha_slug"
           FROM ("public"."medalhas_concedidas" "mc"
             JOIN "public"."medalhas_catalogo" "cat" ON (("cat"."id" = "mc"."medalha_id")))
          WHERE ("cat"."active" = true)
        )
 SELECT "r"."id" AS "recruta_id",
    "c"."ciclo_id",
    "c"."ciclo_slug",
    "rg"."medalha_slug" AS "medalha_obrigatoria_slug",
    "rg"."descricao" AS "motivo_bloqueio",
    "now"() AS "avaliado_em"
   FROM ((("public"."recrutas" "r"
     CROSS JOIN "ciclo" "c")
     JOIN "regras" "rg" ON (true))
     LEFT JOIN "concedidas" "cd" ON ((("cd"."recruta_id" = "r"."id") AND ("cd"."medalha_slug" = "rg"."medalha_slug"))))
  WHERE ("cd"."medalha_slug" IS NULL);


ALTER VIEW "public"."v_c7_bloqueio_oficial_admin" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_c7_bloqueio_oficial_admin" IS 'C7 Bloqueio Oficial (Admin/Auditoria). Não depende de auth.uid(). Não expor ao cliente. Filtrar por recruta_id no consumo.';



CREATE OR REPLACE VIEW "public"."v_c7_bloqueio_oficial_legado" AS
 SELECT "recruta_id",
    "ciclo_id",
    "ciclo_slug" AS "medalha_slug",
    "medalha_obrigatoria_slug",
    "motivo_bloqueio",
    "avaliado_em"
   FROM "public"."v_c7_bloqueio_oficial";


ALTER VIEW "public"."v_c7_bloqueio_oficial_legado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_bloqueio_oficial_por_medalha" AS
 SELECT "mc"."recruta_id",
    "cat"."slug" AS "medalha_slug",
    "rb"."motivo_bloqueio",
    "mc"."granted_at" AS "concedida_em"
   FROM (("public"."medalhas_concedidas" "mc"
     JOIN "public"."medalhas_catalogo" "cat" ON ((("cat"."id" = "mc"."medalha_id") AND ("cat"."active" = true))))
     JOIN "public"."c7_regras_bloqueio_medalhas" "rb" ON ((("rb"."medalha_slug" = "cat"."slug") AND ("rb"."active" = true))));


ALTER VIEW "public"."v_c7_bloqueio_oficial_por_medalha" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_data_quality_resumo" AS
 WITH "r" AS (
         SELECT "count"(1) AS "total_recrutas",
            "count"(1) AS "total_recrutas_ativos"
           FROM "public"."recrutas"
        ), "mc" AS (
         SELECT "count"(1) AS "total_medalhas_catalogo",
            "count"(1) FILTER (WHERE ("medalhas_catalogo"."active" IS TRUE)) AS "total_medalhas_ativas"
           FROM "public"."medalhas_catalogo"
        ), "mr" AS (
         SELECT "count"(1) FILTER (WHERE ("medalha_regras"."ativa" IS FALSE)) AS "total_regras_inativas"
           FROM "public"."medalha_regras"
        ), "msr" AS (
         SELECT ( SELECT "count"(1) AS "count"
                   FROM "public"."medalhas_catalogo" "c"
                  WHERE (NOT (EXISTS ( SELECT 1
                           FROM "public"."medalha_regras" "r_1"
                          WHERE ("r_1"."medalha_id" = "c"."id"))))) AS "total_medalhas_sem_regras"
        ), "mlog" AS (
         SELECT "count"(1) FILTER (WHERE (("medalhas_concessao_log"."detalhes" IS NULL) OR ("medalhas_concessao_log"."detalhes" = '{}'::"jsonb"))) AS "total_logs_sem_detalhes",
            (0)::bigint AS "total_logs_com_fonte_nao_mapeada",
            (0)::bigint AS "total_logs_com_sem_dado"
           FROM "public"."medalhas_concessao_log"
        )
 SELECT "r"."total_recrutas",
    "r"."total_recrutas_ativos",
    "mc"."total_medalhas_catalogo",
    "mc"."total_medalhas_ativas",
    "msr"."total_medalhas_sem_regras",
    "mr"."total_regras_inativas",
    "mlog"."total_logs_sem_detalhes",
    "mlog"."total_logs_com_fonte_nao_mapeada",
    "mlog"."total_logs_com_sem_dado"
   FROM (((("r"
     CROSS JOIN "mc")
     CROSS JOIN "mr")
     CROSS JOIN "msr")
     CROSS JOIN "mlog");


ALTER VIEW "public"."v_c7_data_quality_resumo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_execucoes_historico" AS
 SELECT "id",
    "started_at",
    "finished_at",
    "recrutas_processados",
    "medalhas_avaliadas",
    "medalhas_concedidas",
    "created_at",
    ((EXTRACT(epoch FROM ("finished_at" - "started_at")) * (1000)::numeric))::bigint AS "duracao_ms"
   FROM "public"."c7_execucao_diaria_log" "l"
  ORDER BY "created_at" DESC;


ALTER VIEW "public"."v_c7_execucoes_historico" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_integridade_relacional" AS
 WITH "base_concedidas" AS (
         SELECT 'MEDALHA_CONCEDIDA_SEM_CATALOGO'::"text" AS "tipo_inconsistencia",
            "count"(1) AS "quantidade",
            NULL::timestamp with time zone AS "ultima_ocorrencia"
           FROM ("public"."medalhas_concedidas" "mc"
             LEFT JOIN "public"."medalhas_catalogo" "c" ON (("mc"."medalha_id" = "c"."id")))
          WHERE ("c"."id" IS NULL)
        ), "base_recrutas_concedidas" AS (
         SELECT 'MEDALHA_CONCEDIDA_RECRUTA_INEXISTENTE'::"text" AS "tipo_inconsistencia",
            "count"(1) AS "quantidade",
            NULL::timestamp with time zone AS "ultima_ocorrencia"
           FROM ("public"."medalhas_concedidas" "mc"
             LEFT JOIN "public"."recrutas" "r" ON (("mc"."recruta_id" = "r"."id")))
          WHERE ("r"."id" IS NULL)
        ), "base_logs_medalha" AS (
         SELECT 'LOG_REFERENCIA_MEDALHA_INEXISTENTE'::"text" AS "tipo_inconsistencia",
            "count"(1) AS "quantidade",
            "max"("l"."created_at") AS "ultima_ocorrencia"
           FROM ("public"."medalhas_concessao_log" "l"
             LEFT JOIN "public"."medalhas_catalogo" "c" ON (("l"."medalha_id" = "c"."id")))
          WHERE ("c"."id" IS NULL)
        ), "base_logs_recruta" AS (
         SELECT 'LOG_REFERENCIA_RECRUTA_INEXISTENTE'::"text" AS "tipo_inconsistencia",
            "count"(1) AS "quantidade",
            "max"("l"."created_at") AS "ultima_ocorrencia"
           FROM ("public"."medalhas_concessao_log" "l"
             LEFT JOIN "public"."recrutas" "r" ON (("l"."recruta_id" = "r"."id")))
          WHERE ("r"."id" IS NULL)
        )
 SELECT "base_concedidas"."tipo_inconsistencia",
    "base_concedidas"."quantidade",
    "base_concedidas"."ultima_ocorrencia"
   FROM "base_concedidas"
UNION ALL
 SELECT "base_recrutas_concedidas"."tipo_inconsistencia",
    "base_recrutas_concedidas"."quantidade",
    "base_recrutas_concedidas"."ultima_ocorrencia"
   FROM "base_recrutas_concedidas"
UNION ALL
 SELECT "base_logs_medalha"."tipo_inconsistencia",
    "base_logs_medalha"."quantidade",
    "base_logs_medalha"."ultima_ocorrencia"
   FROM "base_logs_medalha"
UNION ALL
 SELECT "base_logs_recruta"."tipo_inconsistencia",
    "base_logs_recruta"."quantidade",
    "base_logs_recruta"."ultima_ocorrencia"
   FROM "base_logs_recruta";


ALTER VIEW "public"."v_c7_integridade_relacional" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_medalhas_bloqueio_resumo" AS
 WITH "base" AS (
         SELECT "l"."medalha_slug",
            "l"."motivo_bloqueio"
           FROM "public"."medalhas_concessao_log" "l"
          WHERE ("l"."motivo_bloqueio" IS NOT NULL)
        ), "agg" AS (
         SELECT "b"."medalha_slug",
            "b"."motivo_bloqueio",
            ("count"(*))::integer AS "total_bloqueios"
           FROM "base" "b"
          GROUP BY "b"."medalha_slug", "b"."motivo_bloqueio"
        )
 SELECT "medalha_slug",
    "motivo_bloqueio",
    "total_bloqueios",
    "round"(((("total_bloqueios")::numeric / (NULLIF("sum"("total_bloqueios") OVER (PARTITION BY "medalha_slug"), 0))::numeric) * (100)::numeric), 2) AS "percentual_bloqueio_sobre_total_da_medalha"
   FROM "agg" "a"
  ORDER BY "total_bloqueios" DESC, "medalha_slug", "motivo_bloqueio";


ALTER VIEW "public"."v_c7_medalhas_bloqueio_resumo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_medalhas_concedidas_detalhado" AS
 SELECT "mc"."recruta_id",
    "r"."nome",
    "cat"."slug" AS "medalha_slug",
    "cat"."titulo",
    "cat"."categoria",
    "mc"."granted_at"
   FROM (("public"."medalhas_concedidas" "mc"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "mc"."recruta_id")))
     JOIN "public"."medalhas_catalogo" "cat" ON (("cat"."id" = "mc"."medalha_id")))
  ORDER BY "mc"."granted_at" DESC;


ALTER VIEW "public"."v_c7_medalhas_concedidas_detalhado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_medalhas_concedidas_detalhado_v2" AS
 SELECT "mc"."recruta_id",
    "r"."nome",
    "mc"."medalha_id",
    "cat"."slug" AS "medalha_slug",
    "cat"."titulo",
    "cat"."categoria",
    "cat"."active" AS "medalha_active",
    "mc"."granted_at"
   FROM (("public"."medalhas_concedidas" "mc"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "mc"."recruta_id")))
     JOIN "public"."medalhas_catalogo" "cat" ON (("cat"."id" = "mc"."medalha_id")))
  ORDER BY "mc"."granted_at" DESC;


ALTER VIEW "public"."v_c7_medalhas_concedidas_detalhado_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c7_ultima_execucao" AS
 SELECT "id",
    "started_at",
    "finished_at",
    "recrutas_processados",
    "medalhas_avaliadas",
    "medalhas_concedidas",
    ((EXTRACT(epoch FROM ("finished_at" - "started_at")) * (1000)::numeric))::bigint AS "duracao_ms"
   FROM ( SELECT "l"."id",
            "l"."started_at",
            "l"."finished_at",
            "l"."recrutas_processados",
            "l"."medalhas_avaliadas",
            "l"."medalhas_concedidas",
            "l"."created_at"
           FROM "public"."c7_execucao_diaria_log" "l"
          ORDER BY "l"."created_at" DESC
         LIMIT 1) "x";


ALTER VIEW "public"."v_c7_ultima_execucao" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c8_medalhas_sem_versionamento" AS
 SELECT "id" AS "medalha_id",
    "slug",
    "active",
    (EXISTS ( SELECT 1
           FROM "public"."medalhas_catalogo_versionamento" "mv"
          WHERE ("mv"."medalha_id" = "mc"."id"))) AS "possui_versionamento"
   FROM "public"."medalhas_catalogo" "mc"
  WHERE (("active" IS TRUE) AND (NOT (EXISTS ( SELECT 1
           FROM "public"."medalhas_catalogo_versionamento" "mv"
          WHERE ("mv"."medalha_id" = "mc"."id")))));


ALTER VIEW "public"."v_c8_medalhas_sem_versionamento" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c9_aula_execucao" WITH ("security_invoker"='true') AS
 SELECT "id" AS "aula_id",
    "modulo_id",
    "titulo" AS "aula_titulo",
    "ordem" AS "aula_ordem",
    "video_url",
    "pdf_url",
    COALESCE(( SELECT "jsonb_agg"("jsonb_build_object"('conteudo_id', "c"."id", 'tipo', "c"."tipo", 'titulo', "c"."titulo", 'corpo_markdown', "c"."corpo_markdown", 'versao', "c"."versao", 'metadata', "c"."metadata") ORDER BY "c"."tipo", "c"."versao" DESC) AS "jsonb_agg"
           FROM "public"."c9_aula_conteudos" "c"
          WHERE (("c"."aula_id" = "a"."id") AND ("c"."ativo" = true) AND ("c"."deleted_at" IS NULL))), '[]'::"jsonb") AS "conteudos",
    COALESCE(( SELECT "jsonb_agg"("jsonb_build_object"('flashcard_id', "f"."id", 'pergunta', "f"."pergunta", 'resposta', "f"."resposta", 'ordem', "f"."ordem", 'metadata', "f"."metadata") ORDER BY "f"."ordem") AS "jsonb_agg"
           FROM "public"."c9_aula_flashcards" "f"
          WHERE (("f"."aula_id" = "a"."id") AND ("f"."ativo" = true) AND ("f"."deleted_at" IS NULL))), '[]'::"jsonb") AS "flashcards",
    COALESCE(( SELECT "jsonb_agg"("jsonb_build_object"('quiz_id', "q"."id", 'titulo', "q"."titulo", 'descricao', "q"."descricao", 'metadata', "q"."metadata") ORDER BY "q"."created_at") AS "jsonb_agg"
           FROM "public"."c9_aula_quizzes" "q"
          WHERE (("q"."aula_id" = "a"."id") AND ("q"."ativo" = true) AND ("q"."deleted_at" IS NULL))), '[]'::"jsonb") AS "quizzes"
   FROM "public"."aulas" "a";


ALTER VIEW "public"."v_c9_aula_execucao" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c9_quiz_execucao" AS
SELECT
    NULL::"uuid" AS "quiz_id",
    NULL::"uuid" AS "aula_id",
    NULL::"text" AS "titulo",
    NULL::"text" AS "descricao",
    NULL::"jsonb" AS "metadata",
    NULL::"jsonb" AS "perguntas",
    NULL::integer AS "total_perguntas";


ALTER VIEW "public"."v_c9_quiz_execucao" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_c9_quiz_resultado" WITH ("security_invoker"='true') AS
 WITH "respostas_expandidas" AS (
         SELECT "t_1"."id" AS "tentativa_id",
            "t_1"."quiz_id",
            "t_1"."recruta_id",
            "t_1"."created_at",
            (("r"."value" ->> 'pergunta_id'::"text"))::"uuid" AS "pergunta_id",
            (("r"."value" ->> 'alternativa_id'::"text"))::"uuid" AS "alternativa_id"
           FROM ("public"."c9_aula_quiz_tentativas" "t_1"
             CROSS JOIN LATERAL "jsonb_array_elements"(
                CASE
                    WHEN ("jsonb_typeof"("t_1"."respostas") = 'array'::"text") THEN "t_1"."respostas"
                    ELSE '[]'::"jsonb"
                END) "r"("value"))
        ), "avaliadas" AS (
         SELECT "re"."tentativa_id",
            "re"."quiz_id",
            "re"."recruta_id",
            "re"."created_at",
            "p"."id" AS "pergunta_id",
            "p"."enunciado",
            "p"."explicacao",
            "p"."ordem",
            "re"."alternativa_id",
            "a"."texto" AS "alternativa_texto",
            COALESCE("a"."correta", false) AS "correta"
           FROM (("respostas_expandidas" "re"
             JOIN "public"."c9_aula_quiz_perguntas" "p" ON (("p"."id" = "re"."pergunta_id")))
             LEFT JOIN "public"."c9_aula_quiz_alternativas" "a" ON ((("a"."id" = "re"."alternativa_id") AND ("a"."pergunta_id" = "p"."id"))))
        )
 SELECT "t"."id" AS "tentativa_id",
    "t"."quiz_id",
    "t"."recruta_id",
    "t"."created_at",
    "t"."total_perguntas",
    "t"."total_acertos",
    "t"."percentual",
    "t"."finalizada",
    COALESCE("jsonb_agg"("jsonb_build_object"('pergunta_id', "av"."pergunta_id", 'enunciado', "av"."enunciado", 'alternativa_id', "av"."alternativa_id", 'alternativa_texto', "av"."alternativa_texto", 'correta', "av"."correta", 'status',
        CASE
            WHEN "av"."correta" THEN 'convergente'::"text"
            ELSE 'divergente'::"text"
        END, 'explicacao', "av"."explicacao", 'ordem', "av"."ordem") ORDER BY "av"."ordem") FILTER (WHERE ("av"."pergunta_id" IS NOT NULL)), '[]'::"jsonb") AS "questoes"
   FROM ("public"."c9_aula_quiz_tentativas" "t"
     LEFT JOIN "avaliadas" "av" ON (("av"."tentativa_id" = "t"."id")))
  GROUP BY "t"."id", "t"."quiz_id", "t"."recruta_id", "t"."created_at", "t"."total_perguntas", "t"."total_acertos", "t"."percentual", "t"."finalizada";


ALTER VIEW "public"."v_c9_quiz_resultado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_campeoes_mensais_rcc" WITH ("security_invoker"='true') AS
 SELECT "recruta_id",
    "forca",
    true AS "premiado"
   FROM "public"."mv_campeao_mensal" "cm"
  WHERE ("mes_referencia" = ("date_trunc"('month'::"text", "now"()))::"date");


ALTER VIEW "public"."v_campeoes_mensais_rcc" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_campeoes_mensais_rcc" IS 'CANONICAL RCC monthly champions view. Built over mv_campeao_mensal. Exposes premiado=true for UI compatibility.';



CREATE OR REPLACE VIEW "public"."v_chat_conversas_recruta" WITH ("security_invoker"='true') AS
 SELECT "c"."id" AS "conversa_id",
    "c"."recruta_id",
    "c"."instrutor_slug",
    "i"."nome" AS "instrutor_nome",
    "i"."titulo" AS "instrutor_titulo",
    "i"."avatar_asset_tipo",
    "i"."chat_icon_asset_tipo",
    "c"."status",
    "c"."unread_count",
    ("c"."unread_count" > 0) AS "has_unread",
    "c"."opened_at",
    "c"."last_message_at",
    "c"."updated_at"
   FROM (("public"."chat_conversas" "c"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "c"."recruta_id")))
     JOIN "public"."instrutores" "i" ON (("i"."slug" = "c"."instrutor_slug")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_chat_conversas_recruta" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_chat_conversas_recruta" IS 'RCC-0.5 Wave 1: conversas do recruta autenticado.';



CREATE OR REPLACE VIEW "public"."v_chat_mensagens_recruta" WITH ("security_invoker"='true') AS
 SELECT "m"."id" AS "mensagem_id",
    "m"."conversa_id",
    "m"."recruta_id",
    "m"."instrutor_slug",
    "m"."role",
    "m"."conteudo",
    "m"."status",
    "m"."client_message_id",
    "m"."correlation_id",
    "m"."origem",
    "m"."created_at"
   FROM (("public"."chat_mensagens" "m"
     JOIN "public"."chat_conversas" "c" ON (("c"."id" = "m"."conversa_id")))
     JOIN "public"."recrutas" "r" ON (("r"."id" = "c"."recruta_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_chat_mensagens_recruta" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_chat_mensagens_recruta" IS 'RCC-0.5 Wave 1: mensagens das conversas do recruta autenticado.';



CREATE OR REPLACE VIEW "public"."v_chat_unread_status" WITH ("security_invoker"='true') AS
 SELECT "c"."id" AS "conversa_id",
    "c"."recruta_id",
    "c"."instrutor_slug",
    "c"."unread_count",
    ("c"."unread_count" > 0) AS "has_unread",
    "cr"."last_read_at",
    "c"."updated_at"
   FROM (("public"."chat_conversas" "c"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "c"."recruta_id")))
     LEFT JOIN "public"."chat_reads" "cr" ON ((("cr"."conversa_id" = "c"."id") AND ("cr"."recruta_id" = "c"."recruta_id"))))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_chat_unread_status" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_chat_unread_status" IS 'RCC-0.5 Wave 1: unread governado por backend; frontend apenas renderiza.';



CREATE OR REPLACE VIEW "public"."v_classificacao_final_ciclo" AS
 WITH "d" AS (
         SELECT "v_execucao_diaria_dashboard_expandido"."recruta_id",
            "v_execucao_diaria_dashboard_expandido"."ciclo_id",
            "v_execucao_diaria_dashboard_expandido"."semana_atual",
            "v_execucao_diaria_dashboard_expandido"."semana_inicio",
            "v_execucao_diaria_dashboard_expandido"."semana_fim",
            "v_execucao_diaria_dashboard_expandido"."semana_titulo",
            "v_execucao_diaria_dashboard_expandido"."semanas_em_atraso_consec",
            "v_execucao_diaria_dashboard_expandido"."status_regularidade",
            "v_execucao_diaria_dashboard_expandido"."comprometeu_em",
            "v_execucao_diaria_dashboard_expandido"."semanas_total",
            "v_execucao_diaria_dashboard_expandido"."semanas_validas",
            "v_execucao_diaria_dashboard_expandido"."regularidade_percentual",
            "v_execucao_diaria_dashboard_expandido"."iea_score",
            "v_execucao_diaria_dashboard_expandido"."iea_conceito",
            "v_execucao_diaria_dashboard_expandido"."iea_calculado_em_utc",
            "v_execucao_diaria_dashboard_expandido"."iea_calculado_em_br",
            "v_execucao_diaria_dashboard_expandido"."xp_ciclo",
            "v_execucao_diaria_dashboard_expandido"."dias_validos",
            "v_execucao_diaria_dashboard_expandido"."ultima_semana_num"
           FROM "public"."v_execucao_diaria_dashboard_expandido"
        ), "mx" AS (
         SELECT "d"."ciclo_id",
            "max"("d"."xp_ciclo") AS "xp_max_ciclo"
           FROM "d"
          GROUP BY "d"."ciclo_id"
        ), "calc" AS (
         SELECT "d"."recruta_id",
            "d"."ciclo_id",
            ("d"."iea_score")::numeric AS "iea_score",
            ("d"."xp_ciclo")::numeric AS "xp_ciclo",
            "d"."status_regularidade",
            "d"."regularidade_percentual",
                CASE
                    WHEN (("mx"."xp_max_ciclo" IS NULL) OR ("mx"."xp_max_ciclo" <= 0)) THEN 0
                    ELSE LEAST(100, GREATEST(0, (("d"."xp_ciclo" / "mx"."xp_max_ciclo") * 100)))
                END AS "xp_normalizado"
           FROM ("d"
             LEFT JOIN "mx" ON ((NOT ("mx"."ciclo_id" IS DISTINCT FROM "d"."ciclo_id"))))
        ), "score" AS (
         SELECT "c"."recruta_id",
            "c"."ciclo_id",
            "c"."iea_score",
            "c"."xp_ciclo",
            "c"."status_regularidade",
            "c"."regularidade_percentual",
            "c"."xp_normalizado",
            (("c"."iea_score" * 0.6) + (("c"."xp_normalizado")::numeric * 0.4)) AS "score_final"
           FROM "calc" "c"
        )
 SELECT "recruta_id",
    "ciclo_id",
    ("round"("iea_score"))::integer AS "iea_score",
    ("round"(("xp_normalizado")::double precision))::integer AS "xp_normalizado",
    ("round"("score_final"))::integer AS "score_final",
    "status_regularidade",
    "regularidade_percentual",
        CASE
            WHEN (("status_regularidade" = 'comprometida'::"text") OR (("regularidade_percentual" IS NOT NULL) AND ("regularidade_percentual" < 0.70))) THEN 'Regular'::"text"
            WHEN ("score_final" >= (90)::numeric) THEN 'Excelência'::"text"
            WHEN ("score_final" >= (80)::numeric) THEN 'Vanguarda'::"text"
            WHEN ("score_final" >= (70)::numeric) THEN 'Combatente'::"text"
            WHEN ("score_final" >= (60)::numeric) THEN 'Operacional'::"text"
            ELSE 'Recruta'::"text"
        END AS "hierarquia_atual"
   FROM "score" "s";


ALTER VIEW "public"."v_classificacao_final_ciclo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_classificacao_final_ciclo_v2" AS
 SELECT "recruta_id",
    "ciclo_id",
    ("iea_score")::numeric AS "iea_score",
    "xp_normalizado",
    "score_final",
    "status_regularidade",
    "regularidade_percentual",
    "hierarquia_atual"
   FROM "public"."v_classificacao_final_ciclo";


ALTER VIEW "public"."v_classificacao_final_ciclo_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_medalhas_obrigatorias_status" AS
 WITH "me" AS (
         SELECT "r"."id" AS "recruta_id"
           FROM "public"."recrutas" "r"
          WHERE ("r"."auth_id" = "auth"."uid"())
         LIMIT 1
        ), "ciclo" AS (
         SELECT "d"."ciclo_id"
           FROM ("public"."v_execucao_diaria_dashboard_expandido" "d"
             JOIN "me" "me_1" ON (("me_1"."recruta_id" = "d"."recruta_id")))
         LIMIT 1
        )
 SELECT "recruta_id",
    ( SELECT "ciclo"."ciclo_id"
           FROM "ciclo") AS "ciclo_id",
    false AS "ok",
    'MAPEAMENTO_MEDALHAS_OBRIGATORIAS_PENDENTE'::"text" AS "detalhe"
   FROM "me";


ALTER VIEW "public"."v_medalhas_obrigatorias_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_elegibilidade_elite" AS
 WITH "me" AS (
         SELECT "r"."id" AS "recruta_id"
           FROM "public"."recrutas" "r"
          WHERE ("r"."auth_id" = "auth"."uid"())
         LIMIT 1
        ), "d" AS (
         SELECT "x"."recruta_id",
            "x"."ciclo_id",
            "x"."semana_atual",
            "x"."semana_inicio",
            "x"."semana_fim",
            "x"."semana_titulo",
            "x"."semanas_em_atraso_consec",
            "x"."status_regularidade",
            "x"."comprometeu_em",
            "x"."semanas_total",
            "x"."semanas_validas",
            "x"."regularidade_percentual",
            "x"."iea_score",
            "x"."iea_conceito",
            "x"."iea_calculado_em_utc",
            "x"."iea_calculado_em_br",
            "x"."xp_ciclo",
            "x"."dias_validos",
            "x"."ultima_semana_num"
           FROM ("public"."v_execucao_diaria_dashboard_expandido" "x"
             JOIN "me" ON (("me"."recruta_id" = "x"."recruta_id")))
         LIMIT 1
        ), "ass" AS (
         SELECT "a"."ok" AS "assiduidade_ouro_ok",
            "a"."detalhe" AS "ass_det"
           FROM ("public"."v_assiduidade_ouro_status" "a"
             JOIN "me" ON (("me"."recruta_id" = "a"."recruta_id")))
          WHERE (NOT ("a"."ciclo_id" IS DISTINCT FROM ( SELECT "d"."ciclo_id"
                   FROM "d")))
         LIMIT 1
        ), "med" AS (
         SELECT "m"."ok" AS "medalhas_obrigatorias_ok",
            "m"."detalhe" AS "medalhas_detalhe"
           FROM ("public"."v_medalhas_obrigatorias_status" "m"
             JOIN "me" ON (("me"."recruta_id" = "m"."recruta_id")))
         LIMIT 1
        ), "calc" AS (
         SELECT "d"."recruta_id",
            "d"."ciclo_id",
            "d"."iea_score",
            "d"."regularidade_percentual",
            COALESCE("ass"."assiduidade_ouro_ok", false) AS "assiduidade_ouro_ok",
            COALESCE("med"."medalhas_obrigatorias_ok", false) AS "medalhas_obrigatorias_ok",
            "array_remove"(ARRAY[
                CASE
                    WHEN ("d"."ciclo_id" IS NULL) THEN 'SEM_CICLO_VIGENTE'::"text"
                    ELSE NULL::"text"
                END,
                CASE
                    WHEN ("d"."regularidade_percentual" IS NULL) THEN 'CICLO_NAO_INICIADO'::"text"
                    ELSE NULL::"text"
                END,
                CASE
                    WHEN ("d"."iea_score" < 85) THEN 'IEA_INSUFICIENTE'::"text"
                    ELSE NULL::"text"
                END,
                CASE
                    WHEN ("d"."status_regularidade" = 'comprometida'::"text") THEN 'REGULARIDADE_COMPROMETIDA'::"text"
                    ELSE NULL::"text"
                END,
                CASE
                    WHEN (("d"."regularidade_percentual" IS NOT NULL) AND ("d"."regularidade_percentual" < 0.70)) THEN 'REGULARIDADE_INSUFICIENTE'::"text"
                    ELSE NULL::"text"
                END,
                CASE
                    WHEN (COALESCE("ass"."assiduidade_ouro_ok", false) IS NOT TRUE) THEN 'ASSIDUIDADE_OURO_PENDENTE'::"text"
                    ELSE NULL::"text"
                END,
                CASE
                    WHEN (COALESCE("med"."medalhas_obrigatorias_ok", false) IS NOT TRUE) THEN 'MEDALHAS_OBRIGATORIAS_PENDENTES'::"text"
                    ELSE NULL::"text"
                END,
                CASE
                    WHEN (COALESCE("med"."medalhas_detalhe", ''::"text") = 'MAPEAMENTO_MEDALHAS_OBRIGATORIAS_PENDENTE'::"text") THEN 'MAPEAMENTO_MEDALHAS_OBRIGATORIAS_PENDENTE'::"text"
                    ELSE NULL::"text"
                END], NULL::"text") AS "motivos_negacao"
           FROM (("d"
             LEFT JOIN "ass" ON (true))
             LEFT JOIN "med" ON (true))
        )
 SELECT "recruta_id",
    "ciclo_id",
    "iea_score",
    "regularidade_percentual",
    "medalhas_obrigatorias_ok",
    "assiduidade_ouro_ok",
    ("array_length"("motivos_negacao", 1) IS NULL) AS "elegivel_elite",
    "motivos_negacao"
   FROM "calc";


ALTER VIEW "public"."v_elegibilidade_elite" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_elegibilidade_elite" IS 'C6.2: Elegibilidade elite consumindo regularidade_percentual relativa (via v_execucao_diaria_dashboard_expandido).';



CREATE OR REPLACE VIEW "public"."v_elegibilidade_elite_v2" AS
 SELECT "recruta_id",
    "elegivel_elite",
    ("regularidade_percentual")::integer AS "regularidade_percentual",
    "motivos_negacao"
   FROM "public"."v_elegibilidade_elite";


ALTER VIEW "public"."v_elegibilidade_elite_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_eventos_pendentes" AS
 SELECT "e"."id",
    "e"."recruta_id",
    "e"."tipo",
    "e"."referencia_id",
    "e"."titulo",
    "e"."descricao",
    "e"."prioridade",
    "e"."cycle_id",
    "e"."emitido_em",
    "e"."processado"
   FROM ("public"."eventos_institucionais" "e"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "e"."recruta_id")))
  WHERE (("r"."auth_id" = "auth"."uid"()) AND ("e"."processado" = false) AND (NOT (EXISTS ( SELECT 1
           FROM "public"."eventos_consumidos" "c"
          WHERE (("c"."evento_id" = "e"."id") AND ("c"."recruta_id" = "e"."recruta_id"))))))
  ORDER BY ("e"."cycle_id" IS NULL), "e"."cycle_id", "e"."prioridade", "e"."emitido_em";


ALTER VIEW "public"."v_eventos_pendentes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_eventos_pendentes_padronizados" AS
 SELECT "e"."id",
    "e"."recruta_id",
    "e"."tipo",
    "e"."referencia_id",
        CASE
            WHEN (("e"."tipo" = 'patente'::"text") AND ("e"."titulo" = 'x'::"text") AND ("e"."descricao" = 'x'::"text")) THEN 'Promoção de Patente'::"text"
            ELSE "e"."titulo"
        END AS "titulo",
        CASE
            WHEN (("e"."tipo" = 'patente'::"text") AND ("e"."titulo" = 'x'::"text") AND ("e"."descricao" = 'x'::"text")) THEN 'Promoção registrada conforme regulamento institucional'::"text"
            ELSE "e"."descricao"
        END AS "descricao",
    "e"."prioridade",
    "e"."cycle_id",
    "e"."emitido_em",
    "e"."processado",
        CASE
            WHEN ("e"."tipo" = 'patente'::"text") THEN 'promocao'::"text"
            WHEN ("e"."tipo" = 'medalha'::"text") THEN 'concessao'::"text"
            ELSE NULL::"text"
        END AS "subtipo"
   FROM ("public"."eventos_institucionais" "e"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "e"."recruta_id")))
  WHERE (("r"."auth_id" = "auth"."uid"()) AND ("e"."processado" = false) AND (NOT (EXISTS ( SELECT 1
           FROM "public"."eventos_consumidos" "c"
          WHERE (("c"."evento_id" = "e"."id") AND ("c"."recruta_id" = "e"."recruta_id"))))))
  ORDER BY ("e"."cycle_id" IS NULL), "e"."cycle_id", "e"."prioridade", "e"."emitido_em";


ALTER VIEW "public"."v_eventos_pendentes_padronizados" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_execucao_diaria_dashboard_c6" AS
 WITH "me" AS (
         SELECT "r"."id" AS "recruta_id",
            "r"."forca"
           FROM "public"."recrutas" "r"
          WHERE ("r"."auth_id" = "auth"."uid"())
         LIMIT 1
        ), "ciclo" AS (
         SELECT "c"."id",
            "c"."forca",
            "c"."codigo",
            "c"."titulo",
            "c"."data_inicio",
            "c"."data_fim",
            "c"."semanas_total",
            "c"."vigente",
            "c"."criado_em"
           FROM ("public"."ciclos_formativos" "c"
             JOIN "me" "me_1" ON (("me_1"."forca" = "c"."forca")))
          WHERE ((CURRENT_DATE >= "c"."data_inicio") AND (CURRENT_DATE <= "c"."data_fim"))
          ORDER BY "c"."data_inicio" DESC
         LIMIT 1
        ), "status" AS (
         SELECT "rcs"."id",
            "rcs"."recruta_id",
            "rcs"."ciclo_id",
            "rcs"."semana_atual",
            "rcs"."semanas_em_atraso_consec",
            "rcs"."regularidade_status",
            "rcs"."comprometeu_em",
            "rcs"."criado_em",
            "rcs"."atualizado_em",
            "rcs"."semanas_perfeitas_consec",
            "rcs"."semanas_validas",
            "rcs"."dias_validos",
            "rcs"."ultima_semana_num"
           FROM (("public"."recruta_ciclo_status" "rcs"
             JOIN "me" "me_1" ON (("me_1"."recruta_id" = "rcs"."recruta_id")))
             JOIN "ciclo" "c" ON (("c"."id" = "rcs"."ciclo_id")))
         LIMIT 1
        )
 SELECT "me"."recruta_id",
    "ciclo"."id" AS "ciclo_id",
    COALESCE("status"."regularidade_status", 'regular'::"text") AS "status_regularidade",
    COALESCE("status"."semanas_em_atraso_consec", 0) AS "semanas_em_atraso_consec",
    COALESCE("status"."semanas_validas", 0) AS "semanas_validas",
    (("public"."verificar_elegibilidade_grau6"("me"."recruta_id") ->> 'ok'::"text"))::boolean AS "elegivel_elite",
    "public"."c6_get_iea_score"("me"."recruta_id", "ciclo"."id") AS "iea_score",
    COALESCE(( SELECT "sum"("xe"."quantidade") AS "sum"
           FROM "public"."xp_eventos" "xe"
          WHERE (("xe"."recruta_id" = "me"."recruta_id") AND ((("xe"."created_at")::"date" >= "ciclo"."data_inicio") AND (("xe"."created_at")::"date" <= "ciclo"."data_fim")))), (0)::bigint) AS "xp_ciclo"
   FROM (("me"
     LEFT JOIN "ciclo" ON (true))
     LEFT JOIN "status" ON (true));


ALTER VIEW "public"."v_execucao_diaria_dashboard_c6" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_forcas_theme" AS
 SELECT "id",
    "nome",
    "cor_primaria",
    "cor_secundaria",
    "cor_fundo",
    "icone",
    "ativo"
   FROM "public"."forcas"
  WHERE ("ativo" = true);


ALTER VIEW "public"."v_forcas_theme" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_historico_atividade_recruta_v2" AS
 SELECT "id",
    'progresso'::"text" AS "event_type",
    'Aula concluída'::"text" AS "title",
    ('Aula concluída em '::"text" || "lesson_id") AS "description",
    "completed_at" AS "created_at"
   FROM "public"."recruta_progresso"
  WHERE ("status" = 'completed'::"text");


ALTER VIEW "public"."v_historico_atividade_recruta_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_historico_atividade_recruta_v3" AS
 SELECT "rp"."id",
    "rp"."recruta_id",
    'progresso'::"text" AS "event_type",
    'Aula concluída'::"text" AS "title",
    ('Aula concluída em '::"text" || "rp"."lesson_id") AS "description",
    "rp"."completed_at" AS "created_at"
   FROM "public"."recruta_progresso" "rp"
  WHERE ("rp"."status" = 'completed'::"text")
UNION ALL
 SELECT "xe"."id",
    "xe"."recruta_id",
    'xp'::"text" AS "event_type",
    'XP recebido'::"text" AS "title",
    ('Ganho de XP: '::"text" || "xe"."quantidade") AS "description",
    "xe"."created_at"
   FROM "public"."xp_eventos" "xe";


ALTER VIEW "public"."v_historico_atividade_recruta_v3" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_historico_atividade_recruta_v3" IS 'CANONICAL RCC FRONTEND VIEW. Activity history projection. Frontend may SELECT through authenticated role.';



CREATE OR REPLACE VIEW "public"."v_historico_progresso_recruta" AS
 SELECT "base"."recruta_id",
    "base"."force",
    "base"."data_evento",
    "base"."tipo_evento",
    "base"."aula_id",
    "base"."revisao_id",
    "base"."quiz_id",
    "base"."medalha_id",
    "base"."descricao_institucional",
    "base"."xp_impacto",
    "base"."medalha_impacto",
    "base"."referencia",
    "r"."id",
    "r"."auth_id",
    "r"."nome",
    "r"."email",
    "r"."forca",
    "r"."patente",
    "r"."plano",
    "r"."status",
    "r"."data_pagamento",
    "r"."validade",
    "r"."created_at",
    "r"."updated_at",
    "r"."onboarding_concluido",
    "r"."patente_virtual",
    "r"."thread_id"
   FROM (( SELECT "ae"."user_id" AS "recruta_id",
            "ae"."force",
            "ae"."event_timestamp" AS "data_evento",
            "ae"."event_type" AS "tipo_evento",
                CASE
                    WHEN ("ae"."event_type" = 'lesson_completed'::"text") THEN "ae"."reference_id"
                    ELSE NULL::"uuid"
                END AS "aula_id",
            NULL::"uuid" AS "revisao_id",
            NULL::"uuid" AS "quiz_id",
            NULL::"uuid" AS "medalha_id",
            'Evento institucional registrado'::"text" AS "descricao_institucional",
            NULL::integer AS "xp_impacto",
            NULL::"text" AS "medalha_impacto",
            "ae"."reference_id" AS "referencia"
           FROM "public"."v_audit_eventos" "ae"
        UNION ALL
         SELECT "ax"."recruta_id",
            "ax"."force",
            "ax"."event_timestamp",
            'xp'::"text",
            "ax"."aula_id",
            NULL::"uuid",
            "ax"."quiz_id",
            NULL::"uuid",
            "ax"."fundamento_normativo",
            "ax"."xp_value",
            NULL::"text",
            "ax"."event_id"
           FROM "public"."v_audit_xp" "ax"
        UNION ALL
         SELECT "am"."recruta_id",
            "am"."force",
            "am"."data_concessao",
            'medalha_concedida'::"text",
            NULL::"uuid",
            NULL::"uuid",
            NULL::"uuid",
            "am"."medalha_id",
            ('Medalha concedida: '::"text" || "am"."medalha_nome"),
            NULL::integer,
            "am"."medalha_nome",
            "am"."medalha_id"
           FROM "public"."v_audit_medalhas" "am") "base"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "base"."recruta_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_historico_progresso_recruta" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_identidade_recruta_legacy_20260503" AS
 SELECT "id",
    "id" AS "recruta_id",
    "auth_id",
    "nome" AS "nome_completo",
    "nome_guerra",
    COALESCE("nome_guerra", "nome") AS "nome_operacional",
    "email",
    "forca",
    "patente",
    "patente_virtual",
    "plano",
    "status",
    "data_pagamento",
    "validade",
    "onboarding_concluido",
    "created_at",
    "updated_at",
    "thread_id"
   FROM "public"."recrutas" "r"
  WHERE (("auth"."role"() = 'service_role'::"text") OR ("auth_id" = "auth"."uid"()));


ALTER VIEW "public"."v_identidade_recruta_legacy_20260503" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_identidade_recruta_legacy_20260503" IS 'LEGACY BLOCKED. Contains sensitive fields: auth_id, email, billing dates, thread_id. Frontend access forbidden.';



CREATE OR REPLACE VIEW "public"."v_iea_atual_v2" AS
 SELECT "recruta_id",
    ("iea_score")::numeric AS "score",
    "conceito" AS "concept",
    "calculado_em" AS "updated_at"
   FROM "public"."v_iea_atual";


ALTER VIEW "public"."v_iea_atual_v2" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_iea_atual_v2" IS 'CANONICAL RCC FRONTEND VIEW. Current IEA projection. Frontend may SELECT through authenticated role.';



CREATE OR REPLACE VIEW "public"."v_iea_audit" AS
 SELECT "s"."recruta_id",
    "s"."ciclo_id",
    "s"."iea_score",
    "s"."componentes",
    "s"."calculado_em",
    ("s"."calculado_em" AT TIME ZONE 'America/Sao_Paulo'::"text") AS "calculado_em_br"
   FROM ("public"."iea_snapshots" "s"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "s"."recruta_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_iea_audit" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_iea_eventos_audit" AS
 SELECT "s"."recruta_id",
    "s"."ciclo_id",
    "s"."iea_score",
    "s"."conceito",
    "s"."calculado_em" AS "calculado_em_utc",
    ("s"."calculado_em" AT TIME ZONE 'America/Sao_Paulo'::"text") AS "calculado_em_br",
    "ei"."id" AS "evento_id",
    "ei"."tipo",
    "ei"."titulo",
    "ei"."descricao",
    "ei"."prioridade",
    "ei"."emitido_em" AS "emitido_em_utc",
    ("ei"."emitido_em" AT TIME ZONE 'America/Sao_Paulo'::"text") AS "emitido_em_br"
   FROM (("public"."iea_snapshots" "s"
     JOIN "public"."eventos_institucionais" "ei" ON (("ei"."referencia_id" = "s"."id")))
     JOIN "public"."recrutas" "r" ON (("r"."id" = "s"."recruta_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_iea_eventos_audit" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_institutional_assets" AS
 SELECT "asset_id",
    "tipo",
    "url",
    "forca",
    "versao",
    "ativo",
    "checksum",
    "cache_policy",
    "created_at",
    "asset_key"
   FROM "public"."institutional_assets"
  WHERE ("ativo" = true);


ALTER VIEW "public"."v_institutional_assets" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_institutional_notices" AS
 SELECT "id" AS "notice_id",
    "title",
    "body",
    "created_at",
    "priority",
    "deep_link",
    false AS "is_read"
   FROM "public"."institutional_notices" "n";


ALTER VIEW "public"."v_institutional_notices" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_instructor_messages" AS
 SELECT "id" AS "message_id",
    "title",
    "body",
    "created_at",
    "deep_link",
    false AS "is_read"
   FROM "public"."instructor_messages" "m";


ALTER VIEW "public"."v_instructor_messages" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_instrutores_app" WITH ("security_invoker"='true') AS
 SELECT "i"."id" AS "instrutor_id",
    "i"."slug",
    "i"."codigo",
    "i"."nome",
    "i"."titulo",
    "i"."descricao",
    "ia"."url" AS "avatar_url",
    "ci"."url" AS "chat_icon_url",
    "wa"."url" AS "whatsapp_avatar_url",
    "cs"."url" AS "card_selected_url",
    "cid"."url" AS "card_idle_url",
    "i"."ordem_exibicao",
    "i"."ativo"
   FROM ((((("public"."instrutores" "i"
     LEFT JOIN "public"."v_institutional_assets" "ia" ON (("ia"."asset_key" = "i"."avatar_asset_tipo")))
     LEFT JOIN "public"."v_institutional_assets" "ci" ON (("ci"."asset_key" = "i"."chat_icon_asset_tipo")))
     LEFT JOIN "public"."v_institutional_assets" "wa" ON (("wa"."asset_key" = "i"."whatsapp_asset_tipo")))
     LEFT JOIN "public"."v_institutional_assets" "cs" ON (("cs"."asset_key" = "i"."card_selected_asset_tipo")))
     LEFT JOIN "public"."v_institutional_assets" "cid" ON (("cid"."asset_key" = "i"."card_idle_asset_tipo")))
  WHERE ("i"."ativo" = true);


ALTER VIEW "public"."v_instrutores_app" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_lesson_completeness" AS
 SELECT "l"."id" AS "lesson_id",
    "l"."force",
    "l"."module",
    "l"."title",
    "bool_or"(("lm"."type" = 'video'::"text")) AS "has_video",
    "bool_or"(("lm"."type" = 'pdf'::"text")) AS "has_pdf",
    ("bool_or"(("lm"."type" = 'video'::"text")) AND "bool_or"(("lm"."type" = 'pdf'::"text"))) AS "is_complete"
   FROM ("public"."lessons" "l"
     LEFT JOIN "public"."lesson_media" "lm" ON (("lm"."lesson_id" = "l"."id")))
  GROUP BY "l"."id", "l"."force", "l"."module", "l"."title";


ALTER VIEW "public"."v_lesson_completeness" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_lesson_detail_panel" AS
 SELECT "id" AS "lesson_id",
    "title",
    "module",
    "lesson_order",
    "force"
   FROM "public"."lessons" "l";


ALTER VIEW "public"."v_lesson_detail_panel" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_lesson_media_panel" AS
 SELECT "lesson_id",
    "type" AS "media_type"
   FROM "public"."lesson_media" "lm";


ALTER VIEW "public"."v_lesson_media_panel" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_lesson_progress_panel" AS
 SELECT "user_id",
    "lesson_id",
    "completed_at"
   FROM "public"."lesson_progress" "lp";


ALTER VIEW "public"."v_lesson_progress_panel" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_lesson_progress_panel" IS 'CANONICAL RCC FRONTEND VIEW. Lesson progress projection. Frontend may SELECT through authenticated role.';



CREATE OR REPLACE VIEW "public"."v_lesson_review_overdue" AS
 SELECT "lp"."user_id",
    "lp"."lesson_id",
    "lp"."completed_at",
    "min"("lm"."available_after_hours") AS "available_after_hours",
    ("lp"."completed_at" + ('01:00:00'::interval * ("min"("lm"."available_after_hours"))::double precision)) AS "review_available_at",
    "now"() AS "checked_at"
   FROM ("public"."lesson_progress" "lp"
     JOIN "public"."lesson_media" "lm" ON (("lm"."lesson_id" = "lp"."lesson_id")))
  WHERE (("lm"."type" = ANY (ARRAY['review_video'::"text", 'review_audio'::"text"])) AND ("lp"."completed_at" IS NOT NULL) AND ("lp"."review_completed_at" IS NULL) AND ("now"() >= ("lp"."completed_at" + ('01:00:00'::interval * ("lm"."available_after_hours")::double precision))))
  GROUP BY "lp"."user_id", "lp"."lesson_id", "lp"."completed_at";


ALTER VIEW "public"."v_lesson_review_overdue" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_lesson_status_by_user" AS
 WITH "media_flags" AS (
         SELECT "lm"."lesson_id",
            "bool_or"(("lm"."type" = 'video'::"text")) AS "has_video",
            "bool_or"(("lm"."type" = 'pdf'::"text")) AS "has_pdf",
            "bool_or"(("lm"."type" = ANY (ARRAY['review_video'::"text", 'review_audio'::"text"]))) AS "has_review",
            "min"("lm"."available_after_hours") FILTER (WHERE ("lm"."type" = ANY (ARRAY['review_video'::"text", 'review_audio'::"text"]))) AS "review_delay_hours"
           FROM "public"."lesson_media" "lm"
          GROUP BY "lm"."lesson_id"
        )
 SELECT "lp"."user_id",
    "l"."id" AS "lesson_id",
    "l"."force",
    "l"."module",
    "l"."title",
    ("lp"."completed_at" IS NOT NULL) AS "lesson_completed",
    "lp"."completed_at",
    "mf"."has_video",
    "mf"."has_pdf",
    ("mf"."has_video" AND "mf"."has_pdf") AS "lesson_complete",
    "mf"."has_review",
    "mf"."review_delay_hours",
    ("mf"."has_review" AND ("lp"."completed_at" IS NOT NULL) AND ("now"() >= ("lp"."completed_at" + ('01:00:00'::interval * ("mf"."review_delay_hours")::double precision)))) AS "review_available",
    ("lp"."review_completed_at" IS NOT NULL) AS "review_completed",
    "lp"."review_completed_at"
   FROM (("public"."lesson_progress" "lp"
     JOIN "public"."lessons" "l" ON (("l"."id" = "lp"."lesson_id")))
     LEFT JOIN "media_flags" "mf" ON (("mf"."lesson_id" = "l"."id")));


ALTER VIEW "public"."v_lesson_status_by_user" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_lessons_panel" AS
 SELECT "a"."id" AS "lesson_id",
    "a"."titulo" AS "title",
    "a"."modulo_id" AS "module",
    "a"."ordem" AS "lesson_order",
    "m"."forca" AS "force"
   FROM ("public"."aulas" "a"
     JOIN "public"."modulos" "m" ON (("m"."id" = "a"."modulo_id")));


ALTER VIEW "public"."v_lessons_panel" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_lessons_panel" IS 'CANONICAL RCC FRONTEND VIEW. Lessons panel projection. Frontend may SELECT through authenticated role.';



CREATE OR REPLACE VIEW "public"."v_medalha_elegibilidade_status" AS
 SELECT "internal"."recruta_id",
    "internal"."force",
    "internal"."medalha_id",
    "internal"."medalha_nome",
    "internal"."status",
    "internal"."concedida",
    "internal"."elegivel",
    "internal"."nao_elegivel",
    "internal"."criterio_faltante",
    "internal"."ultimo_evento_relevante",
    "internal"."referencia_normativa"
   FROM (( WITH "base" AS (
                 SELECT "r_1"."id" AS "recruta_id",
                    "r_1"."forca" AS "force",
                    "m"."id" AS "medalha_id",
                    "m"."titulo" AS "medalha_nome",
                    "mc"."granted_at"
                   FROM (("public"."recrutas" "r_1"
                     CROSS JOIN "public"."medalhas_catalogo" "m")
                     LEFT JOIN "public"."medalhas_concedidas" "mc" ON ((("mc"."recruta_id" = "r_1"."id") AND ("mc"."medalha_id" = "m"."id"))))
                ), "eventos_relevantes" AS (
                 SELECT "ae"."user_id" AS "recruta_id",
                    "ae"."force",
                    "ae"."event_type",
                    "ae"."event_timestamp"
                   FROM "public"."v_audit_eventos" "ae"
                )
         SELECT "b"."recruta_id",
            "b"."force",
            "b"."medalha_id",
            "b"."medalha_nome",
                CASE
                    WHEN ("b"."granted_at" IS NOT NULL) THEN 'concedida'::"text"
                    WHEN (EXISTS ( SELECT 1
                       FROM "eventos_relevantes" "er"
                      WHERE (("er"."recruta_id" = "b"."recruta_id") AND ("er"."force" = "b"."force")))) THEN 'elegivel'::"text"
                    ELSE 'nao_elegivel'::"text"
                END AS "status",
            ("b"."granted_at" IS NOT NULL) AS "concedida",
            (("b"."granted_at" IS NULL) AND (EXISTS ( SELECT 1
                   FROM "eventos_relevantes" "er"
                  WHERE (("er"."recruta_id" = "b"."recruta_id") AND ("er"."force" = "b"."force"))))) AS "elegivel",
            (("b"."granted_at" IS NULL) AND (NOT (EXISTS ( SELECT 1
                   FROM "eventos_relevantes" "er"
                  WHERE (("er"."recruta_id" = "b"."recruta_id") AND ("er"."force" = "b"."force")))))) AS "nao_elegivel",
                CASE
                    WHEN ("b"."granted_at" IS NOT NULL) THEN NULL::"text"
                    WHEN (NOT (EXISTS ( SELECT 1
                       FROM "eventos_relevantes" "er"
                      WHERE (("er"."recruta_id" = "b"."recruta_id") AND ("er"."force" = "b"."force"))))) THEN 'Ausência de eventos auditáveis compatíveis com o regulamento'::"text"
                    ELSE 'Aguardando validação institucional da concessão'::"text"
                END AS "criterio_faltante",
            ( SELECT "jsonb_build_object"('event_type', "er"."event_type", 'event_timestamp', "er"."event_timestamp") AS "jsonb_build_object"
                   FROM "eventos_relevantes" "er"
                  WHERE (("er"."recruta_id" = "b"."recruta_id") AND ("er"."force" = "b"."force"))
                  ORDER BY "er"."event_timestamp" DESC
                 LIMIT 1) AS "ultimo_evento_relevante",
            'Regulamento de Condecorações — versão vigente'::"text" AS "referencia_normativa"
           FROM "base" "b") "internal"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "internal"."recruta_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_medalha_elegibilidade_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_medalhas_painel" AS
 SELECT "mc"."recruta_id",
    "mc"."granted_at",
    "cat"."slug",
    "cat"."titulo",
    "cat"."descricao",
    "cat"."icon_url",
    "cat"."categoria"
   FROM (("public"."medalhas_concedidas" "mc"
     JOIN "public"."medalhas_catalogo" "cat" ON (("cat"."id" = "mc"."medalha_id")))
     JOIN "public"."recrutas" "r" ON (("r"."id" = "mc"."recruta_id")))
  WHERE (("r"."auth_id" = "auth"."uid"()) AND ("cat"."active" = true));


ALTER VIEW "public"."v_medalhas_painel" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_recruta_medalhas_v2" AS
 SELECT "mc"."recruta_id",
    "mc"."medalha_id",
    "mc"."granted_at",
    "cat"."slug" AS "medalha_slug",
    "cat"."titulo",
    "cat"."descricao",
    "cat"."icon_url",
    "cat"."categoria",
    "cat"."active" AS "medalha_active"
   FROM (("public"."medalhas_concedidas" "mc"
     JOIN "public"."medalhas_catalogo" "cat" ON (("cat"."id" = "mc"."medalha_id")))
     JOIN "public"."recrutas" "r" ON (("r"."id" = "mc"."recruta_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_recruta_medalhas_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_medals_status_v2" AS
 SELECT "recruta_id",
    "medalha_id",
    "medalha_slug",
    "titulo" AS "medal_name",
    "descricao" AS "medal_description",
    "categoria",
    "icon_url",
    "medalha_active" AS "ativo",
    "granted_at" AS "conquistada_em",
    true AS "conquistada"
   FROM "public"."v_recruta_medalhas_v2";


ALTER VIEW "public"."v_medals_status_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_medals_status_v3" AS
 SELECT "mc"."recruta_id",
    "mc"."medalha_id",
    "cat"."slug" AS "medalha_slug",
    "cat"."titulo" AS "medal_name",
    "cat"."descricao" AS "medal_description",
    "cat"."categoria",
    "cat"."icon_url",
    "cat"."active" AS "ativo",
    "mc"."granted_at" AS "conquistada_em",
    true AS "conquistada"
   FROM ("public"."medalhas_concedidas" "mc"
     JOIN "public"."medalhas_catalogo" "cat" ON (("cat"."id" = "mc"."medalha_id")));


ALTER VIEW "public"."v_medals_status_v3" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_medals_status_v3" IS 'CANONICAL RCC FRONTEND VIEW. Medal status projection. Frontend may SELECT through authenticated role.';



CREATE OR REPLACE VIEW "public"."v_modelo_preco_atual" AS
 WITH "ranked" AS (
         SELECT "mpv"."modelo",
            "mpv"."versao",
            "mpv"."effective_from",
            "mpv"."preco_input_token",
            "mpv"."preco_output_token",
            "row_number"() OVER (PARTITION BY "mpv"."modelo" ORDER BY "mpv"."effective_from" DESC, "mpv"."versao" DESC) AS "rn"
           FROM "public"."modelos_precificacao_versionada" "mpv"
        )
 SELECT "modelo",
    "versao",
    "effective_from",
    "preco_input_token",
    "preco_output_token"
   FROM "ranked"
  WHERE ("rn" = 1);


ALTER VIEW "public"."v_modelo_preco_atual" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_modelo_preco_atual" IS 'Preço atual por modelo (baseado em effective_from/versao). Read-only.';



CREATE OR REPLACE VIEW "public"."v_modulos_catalogo" AS
 SELECT "id",
    "forca",
    "titulo",
    "descricao",
    "ordem",
    "ativo",
    "created_at",
    "is_degustacao"
   FROM "public"."modulos"
  WHERE ("ativo" = true);


ALTER VIEW "public"."v_modulos_catalogo" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_onboarding_pendente_recruta" AS
 SELECT "id" AS "recruta_id",
    "auth_id",
    COALESCE("nome_guerra", "nome") AS "nome",
    "email",
    NULL::"text" AS "telefone",
    "forca",
    "onboarding_concluido",
    "created_at"
   FROM "public"."recrutas" "r"
  WHERE ((COALESCE("onboarding_concluido", false) = false) AND (("auth"."role"() = 'service_role'::"text") OR ("auth_id" = "auth"."uid"())));


ALTER VIEW "public"."v_onboarding_pendente_recruta" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_onboarding_status" AS
 SELECT "id" AS "recruta_id",
    ("forca" IS NOT NULL) AS "forca_definida",
    COALESCE("onboarding_concluido", false) AS "onboarding_concluido",
    (NULLIF("btrim"(COALESCE("nome_guerra", ''::"text")), ''::"text") IS NOT NULL) AS "nome_guerra_definido"
   FROM "public"."recrutas" "r"
  WHERE ("auth_id" = "auth"."uid"());


ALTER VIEW "public"."v_onboarding_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_posicao_recruta_mes_rcc" WITH ("security_invoker"='true') AS
 SELECT "rm"."posicao",
    "rm"."recruta_id",
    "rm"."xp_total" AS "xp_mes"
   FROM ("public"."mv_ranking_mensal" "rm"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "rm"."recruta_id")))
  WHERE (("rm"."mes_referencia" = ("date_trunc"('month'::"text", "now"()))::"date") AND ("r"."auth_id" = "auth"."uid"()));


ALTER VIEW "public"."v_posicao_recruta_mes_rcc" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_posicao_recruta_mes_rcc" IS 'CANONICAL RCC self monthly ranking position view. Scoped by auth.uid().';



CREATE OR REPLACE VIEW "public"."v_ranking_force" AS
 SELECT "row_number"() OVER (PARTITION BY "xe"."forca" ORDER BY COALESCE("sum"("xe"."quantidade"), (0)::bigint) DESC, "xe"."recruta_id") AS "position",
    "xe"."recruta_id",
    "r"."nome",
    COALESCE("sum"("xe"."quantidade"), (0)::bigint) AS "xp_total",
    "xe"."forca"
   FROM ("public"."xp_eventos" "xe"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "xe"."recruta_id")))
  WHERE ("xe"."forca" IS NOT NULL)
  GROUP BY "xe"."recruta_id", "r"."nome", "xe"."forca";


ALTER VIEW "public"."v_ranking_force" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_recruta_xp_total" AS
 SELECT "xe"."recruta_id",
    "r"."forca",
    ("sum"("xe"."quantidade"))::integer AS "xp_total"
   FROM ("public"."xp_eventos" "xe"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "xe"."recruta_id")))
  GROUP BY "xe"."recruta_id", "r"."forca";


ALTER VIEW "public"."v_recruta_xp_total" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_recruta_xp_total" IS 'CANONICAL RCC FRONTEND VIEW. XP total projection. Frontend may SELECT through authenticated role.';



CREATE OR REPLACE VIEW "public"."v_ranking_force_v2" AS
 SELECT "row_number"() OVER (PARTITION BY "r"."forca" ORDER BY "xp"."xp_total" DESC, "r"."created_at") AS "position",
    "r"."id" AS "recruta_id",
    "r"."nome",
    "xp"."xp_total",
    "r"."forca"
   FROM ("public"."recrutas" "r"
     JOIN "public"."v_recruta_xp_total" "xp" ON (("xp"."recruta_id" = "r"."id")))
  WHERE ((COALESCE("r"."status", 'ativo'::"text") = 'ativo'::"text") AND ("r"."forca" IS NOT NULL));


ALTER VIEW "public"."v_ranking_force_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_ranking_global" AS
 SELECT "row_number"() OVER (ORDER BY COALESCE("sum"("xe"."quantidade"), (0)::bigint) DESC, "xe"."recruta_id") AS "position",
    "xe"."recruta_id",
    "r"."nome",
    COALESCE("sum"("xe"."quantidade"), (0)::bigint) AS "xp_total"
   FROM ("public"."xp_eventos" "xe"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "xe"."recruta_id")))
  GROUP BY "xe"."recruta_id", "r"."nome";


ALTER VIEW "public"."v_ranking_global" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_ranking_global_v2" AS
 SELECT "row_number"() OVER (ORDER BY "xp"."xp_total" DESC, "r"."created_at") AS "position",
    "r"."id" AS "recruta_id",
    "r"."nome",
    "xp"."xp_total"
   FROM ("public"."recrutas" "r"
     JOIN "public"."v_recruta_xp_total" "xp" ON (("xp"."recruta_id" = "r"."id")))
  WHERE (COALESCE("r"."status", 'ativo'::"text") = 'ativo'::"text");


ALTER VIEW "public"."v_ranking_global_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_ranking_mensal_rcc" WITH ("security_invoker"='true') AS
 SELECT "rm"."posicao",
    "rm"."recruta_id",
    COALESCE("r"."nome_guerra", "r"."nome", 'Recruta'::"text") AS "nome",
    "rm"."forca",
    "rm"."xp_total" AS "xp_mes"
   FROM ("public"."mv_ranking_mensal" "rm"
     LEFT JOIN "public"."recrutas" "r" ON (("r"."id" = "rm"."recruta_id")))
  WHERE ("rm"."mes_referencia" = ("date_trunc"('month'::"text", "now"()))::"date");


ALTER VIEW "public"."v_ranking_mensal_rcc" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_ranking_mensal_rcc" IS 'CANONICAL RCC monthly ranking view. Built over mv_ranking_mensal. Exposes UI-compatible frontend-safe contract.';



CREATE OR REPLACE VIEW "public"."v_recruta_medalhas" AS
 SELECT "mc"."recruta_id",
    "mc"."granted_at",
    "cat"."slug",
    "cat"."titulo",
    "cat"."descricao",
    "cat"."icon_url",
    "cat"."categoria"
   FROM (("public"."medalhas_concedidas" "mc"
     JOIN "public"."medalhas_catalogo" "cat" ON (("cat"."id" = "mc"."medalha_id")))
     JOIN "public"."recrutas" "r" ON (("r"."id" = "mc"."recruta_id")))
  WHERE (("r"."auth_id" = "auth"."uid"()) AND ("cat"."active" = true));


ALTER VIEW "public"."v_recruta_medalhas" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_recruta_patente_atual" AS
 WITH "ranked" AS (
         SELECT "rp"."recruta_id",
            "pc"."codigo",
            "pc"."titulo",
            "pc"."nivel",
            "pc"."icone_url",
            COALESCE("rp"."promovido_em", "rp"."created_at") AS "promovido_em",
            "rp"."motivo",
            "row_number"() OVER (PARTITION BY "rp"."recruta_id" ORDER BY "pc"."nivel" DESC, COALESCE("rp"."promovido_em", "rp"."created_at") DESC, "rp"."id" DESC) AS "rn"
           FROM (("public"."recruta_patentes" "rp"
             JOIN "public"."patentes_catalogo" "pc" ON (("pc"."id" = "rp"."patente_id")))
             JOIN "public"."recrutas" "r" ON (("r"."id" = "rp"."recruta_id")))
          WHERE ("r"."auth_id" = "auth"."uid"())
        )
 SELECT "recruta_id",
    "codigo",
    "titulo",
    "nivel",
    "icone_url",
    "promovido_em",
    "motivo"
   FROM "ranked"
  WHERE ("rn" = 1);


ALTER VIEW "public"."v_recruta_patente_atual" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_reengajamento_recruta" AS
 WITH "base" AS (
         SELECT "r"."id" AS "recruta_id",
            "r"."auth_id",
            COALESCE("r"."nome_guerra", "r"."nome") AS "nome",
            "r"."email",
            NULL::"text" AS "telefone",
            "vas"."ultima_atividade",
            (GREATEST((0)::numeric, "floor"((EXTRACT(epoch FROM ("now"() - (COALESCE("vas"."ultima_atividade", "r"."created_at"))::timestamp with time zone)) / 86400.0))))::integer AS "dias_inativo",
            "r"."onboarding_concluido",
            "vbsr"."acesso_liberado"
           FROM (("public"."recrutas" "r"
             LEFT JOIN "public"."v_auth_session" "vas" ON (("vas"."recruta_id" = "r"."id")))
             LEFT JOIN "public"."v_billing_status_recruta" "vbsr" ON (("vbsr"."recruta_id" = "r"."id")))
        )
 SELECT "recruta_id",
    "auth_id",
    "nome",
    "email",
    "telefone",
    "ultima_atividade",
    "dias_inativo",
    "onboarding_concluido",
    "acesso_liberado"
   FROM "base"
  WHERE (("auth"."role"() = 'service_role'::"text") OR ("auth_id" = "auth"."uid"()));


ALTER VIEW "public"."v_reengajamento_recruta" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_regularidade_status_recruta" AS
 WITH "ciclo" AS (
         SELECT "v"."recruta_id",
            "v"."ciclo_id",
            "v"."forca",
            "v"."codigo",
            "v"."titulo",
            "v"."data_inicio",
            "v"."data_fim",
            "v"."semanas_total",
            "v"."vigente"
           FROM "public"."v_recruta_ciclo_atual" "v"
        )
 SELECT "ciclo"."recruta_id",
    "ciclo"."ciclo_id",
    "public"."calcular_semana_relativa"("ciclo"."recruta_id") AS "semana_atual",
    "cs"."semanas_em_atraso_consec",
    "cs"."regularidade_status",
    "cs"."comprometeu_em"
   FROM ("ciclo"
     JOIN "public"."recruta_ciclo_status" "cs" ON ((("cs"."recruta_id" = "ciclo"."recruta_id") AND ("cs"."ciclo_id" = "ciclo"."ciclo_id"))));


ALTER VIEW "public"."v_regularidade_status_recruta" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_regularidade_status_recruta" IS 'C6.2: Status de regularidade com semana_atual relativa (contrato preservado).';



CREATE OR REPLACE VIEW "public"."v_review_panel" AS
 SELECT "lesson_id",
    "type" AS "review_type"
   FROM "public"."lesson_media" "lm"
  WHERE ("type" = ANY (ARRAY['review_video'::"text", 'review_audio'::"text"]));


ALTER VIEW "public"."v_review_panel" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_semana_atual_recruta" AS
 WITH "ciclo" AS (
         SELECT "v"."recruta_id",
            "v"."ciclo_id",
            "v"."forca",
            "v"."codigo",
            "v"."titulo",
            "v"."data_inicio",
            "v"."data_fim",
            "v"."semanas_total",
            "v"."vigente"
           FROM "public"."v_recruta_ciclo_atual" "v"
        )
 SELECT "ciclo"."recruta_id",
    "ciclo"."ciclo_id",
    "public"."calcular_semana_relativa"("ciclo"."recruta_id") AS "semana_atual",
    COALESCE("cr"."data_inicio", ("cs"."data_inicio_individual" + (("public"."calcular_semana_relativa"("ciclo"."recruta_id") - 1) * 7))) AS "semana_inicio",
    COALESCE("cr"."data_fim", (("cs"."data_inicio_individual" + (("public"."calcular_semana_relativa"("ciclo"."recruta_id") - 1) * 7)) + 6)) AS "semana_fim",
    COALESCE("cr"."titulo", ('Semana '::"text" || ("public"."calcular_semana_relativa"("ciclo"."recruta_id"))::"text")) AS "semana_titulo"
   FROM (("ciclo"
     JOIN "public"."recruta_ciclo_status" "cs" ON ((("cs"."recruta_id" = "ciclo"."recruta_id") AND ("cs"."ciclo_id" = "ciclo"."ciclo_id"))))
     LEFT JOIN "public"."cronograma_semanal" "cr" ON ((("cr"."ciclo_id" = "ciclo"."ciclo_id") AND ("cr"."semana_num" = (("public"."fn_semana_base_calendario"("ciclo"."ciclo_id", "cs"."data_inicio_individual") + "public"."calcular_semana_relativa"("ciclo"."recruta_id")) - 1)))));


ALTER VIEW "public"."v_semana_atual_recruta" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_semana_atual_recruta" IS 'C6.2: Semana atual do recruta em base relativa (mantém semana_inicio/fim/titulo).';



CREATE OR REPLACE VIEW "public"."vw_xp_mensal_recruta" AS
 WITH "periodo_atual" AS (
         SELECT "date_trunc"('month'::"text", "now"()) AS "inicio_mes",
            ("date_trunc"('month'::"text", "now"()) + '1 mon'::interval) AS "fim_mes"
        )
 SELECT "xe"."recruta_id",
    "xe"."forca" AS "force",
    ("p"."inicio_mes")::"date" AS "mes_referencia",
    "sum"("xe"."quantidade") AS "xp_total"
   FROM ("public"."xp_eventos" "xe"
     CROSS JOIN "periodo_atual" "p")
  WHERE (("xe"."created_at" >= "p"."inicio_mes") AND ("xe"."created_at" < "p"."fim_mes"))
  GROUP BY "xe"."recruta_id", "xe"."forca", "p"."inicio_mes";


ALTER VIEW "public"."vw_xp_mensal_recruta" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_ranking_mensal_derivado" AS
 SELECT "recruta_id",
    "force",
    "mes_referencia",
    "xp_total",
    "rank"() OVER (PARTITION BY "force", "mes_referencia" ORDER BY "xp_total" DESC) AS "posicao"
   FROM "public"."vw_xp_mensal_recruta" "v";


ALTER VIEW "public"."vw_ranking_mensal_derivado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_campeao_mensal_oficial" AS
 SELECT "recruta_id",
    "force",
    "mes_referencia",
    "xp_total"
   FROM "public"."vw_ranking_mensal_derivado" "r"
  WHERE ("posicao" = 1);


ALTER VIEW "public"."vw_campeao_mensal_oficial" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_campeao_mensal_detalhado" AS
 SELECT "c"."recruta_id",
    "r"."nome",
    "r"."forca",
    "r"."patente",
    "c"."mes_referencia",
    "c"."xp_total"
   FROM ("public"."vw_campeao_mensal_oficial" "c"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "c"."recruta_id")));


ALTER VIEW "public"."vw_campeao_mensal_detalhado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_campeao_mensal_aeronautica" AS
 SELECT "recruta_id",
    "nome",
    "forca",
    "patente",
    "mes_referencia",
    "xp_total"
   FROM "public"."vw_campeao_mensal_detalhado"
  WHERE ("forca" = 'aeronautica'::"text");


ALTER VIEW "public"."vw_campeao_mensal_aeronautica" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_campeao_mensal_exercito" AS
 SELECT "recruta_id",
    "nome",
    "forca",
    "patente",
    "mes_referencia",
    "xp_total"
   FROM "public"."vw_campeao_mensal_detalhado"
  WHERE ("forca" = 'exercito'::"text");


ALTER VIEW "public"."vw_campeao_mensal_exercito" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_campeao_mensal_marinha" AS
 SELECT "recruta_id",
    "nome",
    "forca",
    "patente",
    "mes_referencia",
    "xp_total"
   FROM "public"."vw_campeao_mensal_detalhado"
  WHERE ("forca" = 'marinha'::"text");


ALTER VIEW "public"."vw_campeao_mensal_marinha" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_campeoes_mensais_derivado" AS
 SELECT "recruta_id",
    "force",
    "mes_referencia",
    "posicao",
    "xp_total"
   FROM "public"."vw_ranking_mensal_derivado" "r"
  WHERE ("posicao" <= 3);


ALTER VIEW "public"."vw_campeoes_mensais_derivado" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_campeoes_pendentes" AS
 SELECT "id",
    "recruta_id",
    "forca",
    "mes_referencia",
    "xp_total",
    "status_premio",
    "lembretes_enviados",
    "ultimo_lembrete_em"
   FROM "public"."campeoes_mensais" "c"
  WHERE (("premiado" = true) AND ("status_premio" = 'aguardando_upload'::"text"));


ALTER VIEW "public"."vw_campeoes_pendentes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_lesson_progress_status" AS
 SELECT "user_id",
    "lesson_id",
    "completed_at",
    "review_completed_at",
        CASE
            WHEN ("completed_at" IS NOT NULL) THEN true
            ELSE false
        END AS "lesson_completed",
        CASE
            WHEN ("review_completed_at" IS NOT NULL) THEN true
            ELSE false
        END AS "review_completed"
   FROM "public"."lesson_progress" "lp";


ALTER VIEW "public"."vw_lesson_progress_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_lessons_with_media" AS
 SELECT "l"."id" AS "lesson_id",
    "l"."force",
    "l"."module",
    "l"."lesson_order",
    "l"."title" AS "lesson_title",
    "l"."slug" AS "lesson_slug",
    "l"."created_at" AS "lesson_created_at",
    "lm"."id" AS "media_id",
    "lm"."type" AS "media_type",
    "lm"."url" AS "media_url",
    "lm"."available_after_hours",
    "lm"."order" AS "media_order",
    "lm"."force" AS "media_force",
    "lm"."created_at" AS "media_created_at"
   FROM ("public"."lessons" "l"
     JOIN "public"."lesson_media" "lm" ON (("lm"."lesson_id" = "l"."id")));


ALTER VIEW "public"."vw_lessons_with_media" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_lesson_media_availability" AS
 SELECT "v"."lesson_id",
    "v"."force",
    "v"."module",
    "v"."lesson_order",
    "v"."lesson_title",
    "v"."media_id",
    "v"."media_type",
    "v"."media_url",
    "v"."media_order",
    "v"."available_after_hours",
    "v"."media_force",
    "lp"."user_id",
    "lp"."completed_at",
        CASE
            WHEN ("v"."available_after_hours" IS NULL) THEN true
            WHEN ("lp"."completed_at" IS NULL) THEN false
            WHEN ("now"() >= ("lp"."completed_at" + (("v"."available_after_hours" || ' hours'::"text"))::interval)) THEN true
            ELSE false
        END AS "is_available"
   FROM ("public"."vw_lessons_with_media" "v"
     LEFT JOIN "public"."vw_lesson_progress_status" "lp" ON (("lp"."lesson_id" = "v"."lesson_id")));


ALTER VIEW "public"."vw_lesson_media_availability" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_lesson_media_for_user" AS
 SELECT "lesson_id",
    "force",
    "module",
    "lesson_order",
    "lesson_title",
    "media_id",
    "media_type",
    "media_url",
    "media_order",
    "available_after_hours",
    "user_id",
    "is_available"
   FROM "public"."vw_lesson_media_availability";


ALTER VIEW "public"."vw_lesson_media_for_user" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_lesson_media_aeronautica" AS
 SELECT "lesson_id",
    "force",
    "module",
    "lesson_order",
    "lesson_title",
    "media_id",
    "media_type",
    "media_url",
    "media_order",
    "available_after_hours",
    "user_id",
    "is_available"
   FROM "public"."vw_lesson_media_for_user"
  WHERE ("force" = 'aeronautica'::"text");


ALTER VIEW "public"."vw_lesson_media_aeronautica" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_lesson_media_exercito" AS
 SELECT "lesson_id",
    "force",
    "module",
    "lesson_order",
    "lesson_title",
    "media_id",
    "media_type",
    "media_url",
    "media_order",
    "available_after_hours",
    "user_id",
    "is_available"
   FROM "public"."vw_lesson_media_for_user"
  WHERE ("force" = 'exercito'::"text");


ALTER VIEW "public"."vw_lesson_media_exercito" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_lesson_media_marinha" AS
 SELECT "lesson_id",
    "force",
    "module",
    "lesson_order",
    "lesson_title",
    "media_id",
    "media_type",
    "media_url",
    "media_order",
    "available_after_hours",
    "user_id",
    "is_available"
   FROM "public"."vw_lesson_media_for_user"
  WHERE ("force" = 'marinha'::"text");


ALTER VIEW "public"."vw_lesson_media_marinha" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_medalhas_obrigatorias" AS
 SELECT "id"
   FROM "public"."medalhas_catalogo"
  WHERE ("active" = true);


ALTER VIEW "public"."vw_medalhas_obrigatorias" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_medalhas_obrigatorias_ativas" AS
 SELECT "id" AS "medalha_id",
    "slug" AS "codigo",
    "titulo" AS "nome",
    "descricao",
    "categoria"
   FROM "public"."medalhas_catalogo"
  WHERE ("active" = true);


ALTER VIEW "public"."vw_medalhas_obrigatorias_ativas" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_module_totals" AS
 SELECT "l"."force",
    "l"."module",
    "count"(DISTINCT "l"."id") AS "total_lessons",
    "count"(DISTINCT "lm"."id") FILTER (WHERE ("lm"."available_after_hours" IS NOT NULL)) AS "total_reviews"
   FROM ("public"."lessons" "l"
     LEFT JOIN "public"."lesson_media" "lm" ON (("lm"."lesson_id" = "l"."id")))
  GROUP BY "l"."force", "l"."module";


ALTER VIEW "public"."vw_module_totals" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_ranking_mensal" AS
 SELECT "row_number"() OVER (ORDER BY "xp" DESC) AS "posicao",
    "id" AS "recruta_id",
    "nome",
    "foto",
    "patente",
    "forca",
    "xp"
   FROM "public"."profiles" "p"
  WHERE (("ativo" = true) AND ("xp" > 0))
  ORDER BY "xp" DESC;


ALTER VIEW "public"."vw_ranking_mensal" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_posicao_recruta_mes" AS
 SELECT "posicao",
    "recruta_id",
    "nome",
    "foto",
    "patente",
    "forca",
    "xp"
   FROM "public"."vw_ranking_mensal";


ALTER VIEW "public"."vw_posicao_recruta_mes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_ranking_mensal_aeronautica" AS
 SELECT "recruta_id",
    "force",
    "mes_referencia",
    "xp_total",
    "posicao"
   FROM "public"."vw_ranking_mensal_derivado"
  WHERE ("force" = 'aeronautica'::"text");


ALTER VIEW "public"."vw_ranking_mensal_aeronautica" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_ranking_mensal_exercito" AS
 SELECT "recruta_id",
    "force",
    "mes_referencia",
    "xp_total",
    "posicao"
   FROM "public"."vw_ranking_mensal_derivado"
  WHERE ("force" = 'exercito'::"text");


ALTER VIEW "public"."vw_ranking_mensal_exercito" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_ranking_mensal_marinha" AS
 SELECT "recruta_id",
    "force",
    "mes_referencia",
    "xp_total",
    "posicao"
   FROM "public"."vw_ranking_mensal_derivado"
  WHERE ("force" = 'marinha'::"text");


ALTER VIEW "public"."vw_ranking_mensal_marinha" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_rdm_lessons" AS
 SELECT "lesson_id",
    "force",
    "module",
    "lesson_order",
    "lesson_title",
    "lesson_slug",
    "lesson_created_at",
    "media_id",
    "media_type",
    "media_url",
    "available_after_hours",
    "media_order",
    "media_force",
    "media_created_at"
   FROM "public"."vw_lessons_with_media"
  WHERE ("module" = 'rdm'::"text");


ALTER VIEW "public"."vw_rdm_lessons" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_rdm_aeronautica" AS
 SELECT "lesson_id",
    "force",
    "module",
    "lesson_order",
    "lesson_title",
    "lesson_slug",
    "lesson_created_at",
    "media_id",
    "media_type",
    "media_url",
    "available_after_hours",
    "media_order",
    "media_force",
    "media_created_at"
   FROM "public"."vw_rdm_lessons"
  WHERE ("force" = 'aeronautica'::"text");


ALTER VIEW "public"."vw_rdm_aeronautica" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_rdm_exercito" AS
 SELECT "lesson_id",
    "force",
    "module",
    "lesson_order",
    "lesson_title",
    "lesson_slug",
    "lesson_created_at",
    "media_id",
    "media_type",
    "media_url",
    "available_after_hours",
    "media_order",
    "media_force",
    "media_created_at"
   FROM "public"."vw_rdm_lessons"
  WHERE ("force" = 'exercito'::"text");


ALTER VIEW "public"."vw_rdm_exercito" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_rdm_lessons_v2" AS
 SELECT "a"."id" AS "lesson_id",
    "a"."ordem" AS "lesson_order",
    "a"."titulo" AS "lesson_title",
    'available'::"text" AS "status",
    "m"."id" AS "module_id",
    "m"."titulo" AS "module_title",
    "m"."forca",
    "m"."is_degustacao",
    "a"."video_url",
    "a"."pdf_url"
   FROM ("public"."aulas" "a"
     JOIN "public"."modulos" "m" ON (("m"."id" = "a"."modulo_id")))
  WHERE ((COALESCE("m"."ativo", true) = true) AND (COALESCE("m"."is_degustacao", false) = true))
  ORDER BY "m"."ordem", "a"."ordem";


ALTER VIEW "public"."vw_rdm_lessons_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_rdm_marinha" AS
 SELECT "lesson_id",
    "force",
    "module",
    "lesson_order",
    "lesson_title",
    "lesson_slug",
    "lesson_created_at",
    "media_id",
    "media_type",
    "media_url",
    "available_after_hours",
    "media_order",
    "media_force",
    "media_created_at"
   FROM "public"."vw_rdm_lessons"
  WHERE ("force" = 'marinha'::"text");


ALTER VIEW "public"."vw_rdm_marinha" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_recruta_lesson_status" AS
 SELECT "lp"."user_id",
    "l"."id" AS "lesson_id",
    "l"."force",
    "l"."module",
        CASE
            WHEN ("lp"."completed_at" IS NOT NULL) THEN 1
            ELSE 0
        END AS "lesson_completed",
        CASE
            WHEN ("lp"."review_completed_at" IS NOT NULL) THEN 1
            ELSE 0
        END AS "review_completed"
   FROM ("public"."lessons" "l"
     LEFT JOIN "public"."lesson_progress" "lp" ON (("lp"."lesson_id" = "l"."id")));


ALTER VIEW "public"."vw_recruta_lesson_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_recruta_module_progress" AS
 SELECT "m"."id" AS "module_id",
    "m"."titulo" AS "module_title",
    "count"("a"."id") AS "total_lessons",
    "count"("rp"."id") AS "completed_lessons",
        CASE
            WHEN ("count"("a"."id") = 0) THEN 0
            ELSE ("round"(((("count"("rp"."id"))::numeric / ("count"("a"."id"))::numeric) * (100)::numeric)))::integer
        END AS "progress_percentage"
   FROM (("public"."modulos" "m"
     LEFT JOIN "public"."aulas" "a" ON (("a"."modulo_id" = "m"."id")))
     LEFT JOIN "public"."recruta_progresso" "rp" ON ((("rp"."lesson_id" = "a"."id") AND ("rp"."status" = 'completed'::"text") AND ("rp"."completed_at" IS NOT NULL))))
  WHERE (COALESCE("m"."ativo", true) = true)
  GROUP BY "m"."id", "m"."titulo", "m"."ordem"
  ORDER BY "m"."ordem";


ALTER VIEW "public"."vw_recruta_module_progress" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_recruta_module_progress_legacy_20260503" AS
 SELECT "base"."user_id",
    "base"."force",
    "base"."module",
    "base"."total_lessons",
    "base"."total_reviews",
    "base"."lessons_completed",
    "base"."reviews_completed",
    "base"."module_lessons_completed",
    "base"."module_reviews_completed",
    "r"."id",
    "r"."auth_id",
    "r"."nome",
    "r"."email",
    "r"."forca",
    "r"."patente",
    "r"."plano",
    "r"."status",
    "r"."data_pagamento",
    "r"."validade",
    "r"."created_at",
    "r"."updated_at",
    "r"."onboarding_concluido",
    "r"."patente_virtual",
    "r"."thread_id"
   FROM (( SELECT "rls"."user_id",
            "rls"."force",
            "rls"."module",
            "mt"."total_lessons",
            "mt"."total_reviews",
            "sum"("rls"."lesson_completed") AS "lessons_completed",
            "sum"("rls"."review_completed") AS "reviews_completed",
                CASE
                    WHEN ("sum"("rls"."lesson_completed") = "mt"."total_lessons") THEN true
                    ELSE false
                END AS "module_lessons_completed",
                CASE
                    WHEN ("mt"."total_reviews" = 0) THEN true
                    WHEN ("sum"("rls"."review_completed") = "mt"."total_reviews") THEN true
                    ELSE false
                END AS "module_reviews_completed"
           FROM ("public"."vw_recruta_lesson_status" "rls"
             JOIN "public"."vw_module_totals" "mt" ON ((("mt"."force" = "rls"."force") AND ("mt"."module" = "rls"."module"))))
          GROUP BY "rls"."user_id", "rls"."force", "rls"."module", "mt"."total_lessons", "mt"."total_reviews") "base"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "base"."user_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."vw_recruta_module_progress_legacy_20260503" OWNER TO "postgres";


COMMENT ON VIEW "public"."vw_recruta_module_progress_legacy_20260503" IS 'LEGACY BLOCKED. Contains sensitive identity/billing/thread fields. Use RCC canonical views only.';



CREATE OR REPLACE VIEW "public"."vw_recruta_module_progress_v2" AS
 SELECT "r"."id" AS "recruta_id",
    "m"."id" AS "module_id",
    "m"."titulo" AS "module_title",
    "count"("a"."id") AS "total_lessons",
    "count"("rp"."id") AS "completed_lessons",
        CASE
            WHEN ("count"("a"."id") = 0) THEN 0
            ELSE ("round"(((("count"("rp"."id"))::numeric / ("count"("a"."id"))::numeric) * (100)::numeric)))::integer
        END AS "progress_percentage"
   FROM ((("public"."recrutas" "r"
     JOIN "public"."modulos" "m" ON (((COALESCE("m"."ativo", true) = true) AND (("m"."forca" IS NULL) OR ("m"."forca" = "r"."forca")))))
     LEFT JOIN "public"."aulas" "a" ON (("a"."modulo_id" = "m"."id")))
     LEFT JOIN "public"."recruta_progresso" "rp" ON ((("rp"."lesson_id" = "a"."id") AND ("rp"."recruta_id" = "r"."id") AND ("rp"."status" = 'completed'::"text") AND ("rp"."completed_at" IS NOT NULL))))
  GROUP BY "r"."id", "m"."id", "m"."titulo", "m"."ordem"
  ORDER BY "m"."ordem";


ALTER VIEW "public"."vw_recruta_module_progress_v2" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_recruta_module_status" AS
 SELECT "base"."user_id",
    "base"."force",
    "base"."module",
    "base"."lessons_completed",
    "base"."total_lessons",
    "base"."reviews_completed",
    "base"."total_reviews",
        CASE
            WHEN (("base"."module_lessons_completed" = true) AND ("base"."module_reviews_completed" = true)) THEN true
            ELSE false
        END AS "module_completed",
    "r"."id",
    "r"."auth_id",
    "r"."nome",
    "r"."email",
    "r"."forca",
    "r"."patente",
    "r"."plano",
    "r"."status",
    "r"."data_pagamento",
    "r"."validade",
    "r"."created_at",
    "r"."updated_at",
    "r"."onboarding_concluido",
    "r"."patente_virtual",
    "r"."thread_id"
   FROM ("public"."vw_recruta_module_progress_legacy_20260503" "base"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "base"."user_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."vw_recruta_module_status" OWNER TO "postgres";


COMMENT ON VIEW "public"."vw_recruta_module_status" IS 'LEGACY/BLOCKED. Contains identity, billing and thread fields. Use public.vw_recruta_module_status_rcc.';



CREATE OR REPLACE VIEW "public"."vw_recruta_module_status_rcc" WITH ("security_invoker"='true') AS
 SELECT "base"."user_id",
    "base"."force",
    "base"."module",
    "base"."total_lessons",
    "base"."total_reviews",
    "base"."lessons_completed",
    "base"."reviews_completed",
    "base"."module_lessons_completed",
    "base"."module_reviews_completed"
   FROM (( SELECT "rls"."user_id",
            "rls"."force",
            "rls"."module",
            "mt"."total_lessons",
            "mt"."total_reviews",
            "sum"("rls"."lesson_completed") AS "lessons_completed",
            "sum"("rls"."review_completed") AS "reviews_completed",
                CASE
                    WHEN ("sum"("rls"."lesson_completed") = "mt"."total_lessons") THEN true
                    ELSE false
                END AS "module_lessons_completed",
                CASE
                    WHEN ("mt"."total_reviews" = 0) THEN true
                    WHEN ("sum"("rls"."review_completed") = "mt"."total_reviews") THEN true
                    ELSE false
                END AS "module_reviews_completed"
           FROM ("public"."vw_recruta_lesson_status" "rls"
             JOIN "public"."vw_module_totals" "mt" ON ((("mt"."force" = "rls"."force") AND ("mt"."module" = "rls"."module"))))
          GROUP BY "rls"."user_id", "rls"."force", "rls"."module", "mt"."total_lessons", "mt"."total_reviews") "base"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "base"."user_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."vw_recruta_module_status_rcc" OWNER TO "postgres";


COMMENT ON VIEW "public"."vw_recruta_module_status_rcc" IS 'RCC hardened module status view. Removes identity, billing and thread fields from legacy module status projection.';



CREATE OR REPLACE VIEW "public"."vw_status_recruta" AS
 SELECT "recruta_id",
    "patente",
    "nivel",
    "xp",
    "honra_maxima",
    "atualizado_em"
   FROM "public"."recruta_status";


ALTER VIEW "public"."vw_status_recruta" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_xp_lessons" AS
 SELECT "lp"."user_id",
    "l"."force",
    "l"."module",
    "l"."id" AS "lesson_id",
        CASE
            WHEN ("lp"."completed_at" IS NOT NULL) THEN 1
            ELSE 0
        END AS "xp_lesson"
   FROM ("public"."lessons" "l"
     LEFT JOIN "public"."lesson_progress" "lp" ON (("lp"."lesson_id" = "l"."id")));


ALTER VIEW "public"."vw_xp_lessons" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_xp_reviews" AS
 SELECT "lp"."user_id",
    "l"."force",
    "l"."module",
    "l"."id" AS "lesson_id",
        CASE
            WHEN ("lp"."review_completed_at" IS NOT NULL) THEN 1
            ELSE 0
        END AS "xp_review"
   FROM ("public"."lessons" "l"
     LEFT JOIN "public"."lesson_progress" "lp" ON (("lp"."lesson_id" = "l"."id")));


ALTER VIEW "public"."vw_xp_reviews" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_xp_module" AS
 SELECT "base"."user_id",
    "base"."force",
    "base"."module",
    "base"."xp_from_lessons",
    "base"."xp_from_reviews",
    "base"."xp_total",
    "r"."id",
    "r"."auth_id",
    "r"."nome",
    "r"."email",
    "r"."forca",
    "r"."patente",
    "r"."plano",
    "r"."status",
    "r"."data_pagamento",
    "r"."validade",
    "r"."created_at",
    "r"."updated_at",
    "r"."onboarding_concluido",
    "r"."patente_virtual",
    "r"."thread_id"
   FROM (( SELECT "xl"."user_id",
            "xl"."force",
            "xl"."module",
            "sum"("xl"."xp_lesson") AS "xp_from_lessons",
            "sum"("xr"."xp_review") AS "xp_from_reviews",
            ("sum"("xl"."xp_lesson") + "sum"("xr"."xp_review")) AS "xp_total"
           FROM ("public"."vw_xp_lessons" "xl"
             JOIN "public"."vw_xp_reviews" "xr" ON ((("xr"."user_id" = "xl"."user_id") AND ("xr"."lesson_id" = "xl"."lesson_id"))))
          GROUP BY "xl"."user_id", "xl"."force", "xl"."module") "base"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "base"."user_id")))
  WHERE ("r"."auth_id" = "auth"."uid"());


ALTER VIEW "public"."vw_xp_module" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."xp_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "xp" integer NOT NULL,
    "periodo" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "reference" "text"
);


ALTER TABLE "public"."xp_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL
);


ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."buckets_analytics" (
    "name" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'ANALYTICS'::"storage"."buckettype" NOT NULL,
    "format" "text" DEFAULT 'ICEBERG'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "storage"."buckets_analytics" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."buckets_vectors" (
    "id" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'VECTOR'::"storage"."buckettype" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."buckets_vectors" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."migrations" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "hash" character varying(40) NOT NULL,
    "executed_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "storage"."migrations" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb"
);


ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads" (
    "id" "text" NOT NULL,
    "in_progress_size" bigint DEFAULT 0 NOT NULL,
    "upload_signature" "text" NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "version" "text" NOT NULL,
    "owner_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_metadata" "jsonb",
    "metadata" "jsonb"
);


ALTER TABLE "storage"."s3_multipart_uploads" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "upload_id" "text" NOT NULL,
    "size" bigint DEFAULT 0 NOT NULL,
    "part_number" integer NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "etag" "text" NOT NULL,
    "owner_id" "text",
    "version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."s3_multipart_uploads_parts" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."vector_indexes" (
    "id" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "bucket_id" "text" NOT NULL,
    "data_type" "text" NOT NULL,
    "dimension" integer NOT NULL,
    "distance_metric" "text" NOT NULL,
    "metadata_configuration" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."vector_indexes" OWNER TO "supabase_storage_admin";


ALTER TABLE ONLY "auth"."refresh_tokens" ALTER COLUMN "id" SET DEFAULT "nextval"('"auth"."refresh_tokens_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."auth_client_revocations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."auth_client_revocations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."auth_session_revocations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."auth_session_revocations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."c5_jobs_execucao_log" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."c5_jobs_execucao_log_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."roles" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."roles_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."usage_stats" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."usage_stats_id_seq"'::"regclass");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "amr_id_pk" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."audit_log_entries"
    ADD CONSTRAINT "audit_log_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."custom_oauth_providers"
    ADD CONSTRAINT "custom_oauth_providers_identifier_key" UNIQUE ("identifier");



ALTER TABLE ONLY "auth"."custom_oauth_providers"
    ADD CONSTRAINT "custom_oauth_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."flow_state"
    ADD CONSTRAINT "flow_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_provider_id_provider_unique" UNIQUE ("provider_id", "provider");



ALTER TABLE ONLY "auth"."instances"
    ADD CONSTRAINT "instances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_authentication_method_pkey" UNIQUE ("session_id", "authentication_method");



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_last_challenged_at_key" UNIQUE ("last_challenged_at");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_code_key" UNIQUE ("authorization_code");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_id_key" UNIQUE ("authorization_id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_client_states"
    ADD CONSTRAINT "oauth_client_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_clients"
    ADD CONSTRAINT "oauth_clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_client_unique" UNIQUE ("user_id", "client_id");



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_token_unique" UNIQUE ("token");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_entity_id_key" UNIQUE ("entity_id");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."schema_migrations"
    ADD CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_providers"
    ADD CONSTRAINT "sso_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."webauthn_challenges"
    ADD CONSTRAINT "webauthn_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."webauthn_credentials"
    ADD CONSTRAINT "webauthn_credentials_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."_qd_migration_snapshots"
    ADD CONSTRAINT "_qd_migration_snapshots_pkey" PRIMARY KEY ("migration_id");



ALTER TABLE ONLY "public"."atividade_academica_log"
    ADD CONSTRAINT "atividade_academica_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."aula_pipeline_execucoes"
    ADD CONSTRAINT "aula_pipeline_execucoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."aula_pipeline_logs"
    ADD CONSTRAINT "aula_pipeline_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."aulas_concluidas"
    ADD CONSTRAINT "aulas_concluidas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."aulas"
    ADD CONSTRAINT "aulas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_client_revocations"
    ADD CONSTRAINT "auth_client_revocations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_client_singleton"
    ADD CONSTRAINT "auth_client_singleton_pkey" PRIMARY KEY ("auth_id");



ALTER TABLE ONLY "public"."auth_session_revocations"
    ADD CONSTRAINT "auth_session_revocations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_session_singleton"
    ADD CONSTRAINT "auth_session_singleton_pkey" PRIMARY KEY ("auth_id");



ALTER TABLE ONLY "public"."automacoes_execucoes"
    ADD CONSTRAINT "automacoes_execucoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_assinaturas"
    ADD CONSTRAINT "billing_assinaturas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_assinaturas"
    ADD CONSTRAINT "billing_assinaturas_recruta_unq" UNIQUE ("recruta_id");



ALTER TABLE ONLY "public"."billing_eventos"
    ADD CONSTRAINT "billing_eventos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_notificacoes_log"
    ADD CONSTRAINT "billing_notificacoes_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_pagamentos"
    ADD CONSTRAINT "billing_pagamentos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_reconciliacao"
    ADD CONSTRAINT "billing_reconciliacao_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_reconciliation_issues"
    ADD CONSTRAINT "billing_reconciliation_issues_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c5_alertas_operacionais"
    ADD CONSTRAINT "c5_alertas_operacionais_pkey" PRIMARY KEY ("id_alerta");



ALTER TABLE ONLY "public"."c5_audit_eventos_institucionais"
    ADD CONSTRAINT "c5_audit_eventos_institucionais_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c5_fatos_analytics"
    ADD CONSTRAINT "c5_fatos_analytics_pkey" PRIMARY KEY ("id_evento");



ALTER TABLE ONLY "public"."c5_jobs_execucao_log"
    ADD CONSTRAINT "c5_jobs_execucao_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c5_metricas_diarias"
    ADD CONSTRAINT "c5_metricas_diarias_pkey" PRIMARY KEY ("dia", "dominio_analitico", "evento_analitico");



ALTER TABLE ONLY "public"."c5_metricas_recruta"
    ADD CONSTRAINT "c5_metricas_recruta_pkey" PRIMARY KEY ("id_recruta", "dia", "dominio_analitico", "evento_analitico");



ALTER TABLE ONLY "public"."c5_regras_alerta"
    ADD CONSTRAINT "c5_regras_alerta_pkey" PRIMARY KEY ("tipo_alerta");



ALTER TABLE ONLY "public"."c5_taxonomia_eventos"
    ADD CONSTRAINT "c5_taxonomia_eventos_pkey" PRIMARY KEY ("tipo_evento");



ALTER TABLE ONLY "public"."c6_contract_registry"
    ADD CONSTRAINT "c6_contract_registry_pkey" PRIMARY KEY ("contract_name");



ALTER TABLE ONLY "public"."c7_ciclos"
    ADD CONSTRAINT "c7_ciclos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c7_ciclos"
    ADD CONSTRAINT "c7_ciclos_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."c7_execucao_diaria_log"
    ADD CONSTRAINT "c7_execucao_diaria_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c7_regras_bloqueio_medalhas"
    ADD CONSTRAINT "c7_regras_bloqueio_medalhas_pkey" PRIMARY KEY ("medalha_slug");



ALTER TABLE ONLY "public"."c7_regras_bloqueio_por_ciclo"
    ADD CONSTRAINT "c7_regras_bloqueio_por_ciclo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c9_aula_conteudos"
    ADD CONSTRAINT "c9_aula_conteudos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c9_aula_flashcards"
    ADD CONSTRAINT "c9_aula_flashcards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c9_aula_quiz_alternativas"
    ADD CONSTRAINT "c9_aula_quiz_alternativas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c9_aula_quiz_perguntas"
    ADD CONSTRAINT "c9_aula_quiz_perguntas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c9_aula_quiz_tentativas"
    ADD CONSTRAINT "c9_aula_quiz_tentativas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."c9_aula_quizzes"
    ADD CONSTRAINT "c9_aula_quizzes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campeoes_mensais"
    ADD CONSTRAINT "campeoes_mensais_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campeoes_mensais"
    ADD CONSTRAINT "campeoes_mensais_recruta_id_mes_referencia_key" UNIQUE ("recruta_id", "mes_referencia");



ALTER TABLE ONLY "public"."chat_audit_log"
    ADD CONSTRAINT "chat_audit_log_pkey" PRIMARY KEY ("audit_id");



ALTER TABLE ONLY "public"."chat_conversas"
    ADD CONSTRAINT "chat_conversas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_conversas"
    ADD CONSTRAINT "chat_conversas_recruta_instrutor_uk" UNIQUE ("recruta_id", "instrutor_slug");



ALTER TABLE ONLY "public"."chat_events"
    ADD CONSTRAINT "chat_events_pkey" PRIMARY KEY ("event_id");



ALTER TABLE ONLY "public"."chat_logs"
    ADD CONSTRAINT "chat_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_mensagens"
    ADD CONSTRAINT "chat_mensagens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_reads"
    ADD CONSTRAINT "chat_reads_pkey" PRIMARY KEY ("conversa_id", "recruta_id");



ALTER TABLE ONLY "public"."chat_summaries"
    ADD CONSTRAINT "chat_summaries_pkey" PRIMARY KEY ("recruta_id");



ALTER TABLE ONLY "public"."chat_threads"
    ADD CONSTRAINT "chat_threads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_threads"
    ADD CONSTRAINT "chat_threads_user_id_forca_key" UNIQUE ("user_id", "forca");



ALTER TABLE ONLY "public"."ciclos_formativos"
    ADD CONSTRAINT "ciclos_formativos_forca_codigo_key" UNIQUE ("forca", "codigo");



ALTER TABLE ONLY "public"."ciclos_formativos"
    ADD CONSTRAINT "ciclos_formativos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversation_locks"
    ADD CONSTRAINT "conversation_locks_pkey" PRIMARY KEY ("recruta_id");



ALTER TABLE ONLY "public"."cronograma_semanal"
    ADD CONSTRAINT "cronograma_semanal_ciclo_id_semana_num_key" UNIQUE ("ciclo_id", "semana_num");



ALTER TABLE ONLY "public"."cronograma_semanal"
    ADD CONSTRAINT "cronograma_semanal_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."eventos_ciclos"
    ADD CONSTRAINT "eventos_ciclos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."eventos_consumidos"
    ADD CONSTRAINT "eventos_consumidos_evento_id_recruta_id_key" UNIQUE ("evento_id", "recruta_id");



ALTER TABLE ONLY "public"."eventos_consumidos"
    ADD CONSTRAINT "eventos_consumidos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."eventos_institucionais"
    ADD CONSTRAINT "eventos_institucionais_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."forcas"
    ADD CONSTRAINT "forcas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."iea_marcos_emitidos"
    ADD CONSTRAINT "iea_marcos_emitidos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."iea_marcos_emitidos"
    ADD CONSTRAINT "iea_marcos_emitidos_unique_recruta_ciclochave_marco" UNIQUE ("recruta_id", "ciclo_chave", "marco");



ALTER TABLE ONLY "public"."iea_snapshots"
    ADD CONSTRAINT "iea_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."institutional_assets"
    ADD CONSTRAINT "institutional_assets_pkey" PRIMARY KEY ("asset_id");



ALTER TABLE ONLY "public"."institutional_notice_reads"
    ADD CONSTRAINT "institutional_notice_reads_pkey" PRIMARY KEY ("notice_id", "recruta_id");



ALTER TABLE ONLY "public"."institutional_notices"
    ADD CONSTRAINT "institutional_notices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."instructor_message_reads"
    ADD CONSTRAINT "instructor_message_reads_pkey" PRIMARY KEY ("message_id", "recruta_id");



ALTER TABLE ONLY "public"."instructor_messages"
    ADD CONSTRAINT "instructor_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."instrutor_threads"
    ADD CONSTRAINT "instrutor_threads_pkey" PRIMARY KEY ("recruta_id");



ALTER TABLE ONLY "public"."instrutores"
    ADD CONSTRAINT "instrutores_codigo_key" UNIQUE ("codigo");



ALTER TABLE ONLY "public"."instrutores"
    ADD CONSTRAINT "instrutores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."instrutores"
    ADD CONSTRAINT "instrutores_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."lesson_media"
    ADD CONSTRAINT "lesson_media_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lesson_progress"
    ADD CONSTRAINT "lesson_progress_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lesson_progress"
    ADD CONSTRAINT "lesson_progress_unique" UNIQUE ("user_id", "lesson_id");



ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_unique_order" UNIQUE ("force", "module", "lesson_order");



ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_unique_slug" UNIQUE ("force", "module", "slug");



ALTER TABLE ONLY "public"."licoes"
    ADD CONSTRAINT "licoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."log_emissao_eventos"
    ADD CONSTRAINT "log_emissao_eventos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."logs_acesso"
    ADD CONSTRAINT "logs_acesso_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalha_regras"
    ADD CONSTRAINT "medalha_regras_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalhas_alteracoes_pendentes"
    ADD CONSTRAINT "medalhas_alteracoes_pendentes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalhas_catalogo"
    ADD CONSTRAINT "medalhas_catalogo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalhas_catalogo"
    ADD CONSTRAINT "medalhas_catalogo_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."medalhas_catalogo"
    ADD CONSTRAINT "medalhas_catalogo_slug_uk" UNIQUE ("slug");



ALTER TABLE ONLY "public"."medalhas_catalogo_versionamento"
    ADD CONSTRAINT "medalhas_catalogo_versionamento_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalhas_categorias"
    ADD CONSTRAINT "medalhas_categorias_pkey" PRIMARY KEY ("codigo");



ALTER TABLE ONLY "public"."medalhas_concedidas"
    ADD CONSTRAINT "medalhas_concedidas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalhas_concedidas"
    ADD CONSTRAINT "medalhas_concedidas_recruta_id_medalha_id_key" UNIQUE ("recruta_id", "medalha_id");



ALTER TABLE ONLY "public"."medalhas_concedidas"
    ADD CONSTRAINT "medalhas_concedidas_recruta_medalha_uk" UNIQUE ("recruta_id", "medalha_id");



ALTER TABLE ONLY "public"."medalhas_concedidas"
    ADD CONSTRAINT "medalhas_concedidas_unique" UNIQUE ("recruta_id", "medalha_id");



ALTER TABLE ONLY "public"."medalhas_concessao_log"
    ADD CONSTRAINT "medalhas_concessao_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalhas_concessao_log"
    ADD CONSTRAINT "medalhas_concessao_log_run_recruta_medalha_uniq" UNIQUE ("run_id", "recruta_id", "medalha_id");



ALTER TABLE ONLY "public"."medalhas_eventos"
    ADD CONSTRAINT "medalhas_eventos_codigo_key" UNIQUE ("codigo");



ALTER TABLE ONLY "public"."medalhas_eventos"
    ADD CONSTRAINT "medalhas_eventos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalhas_obrigatorias_map"
    ADD CONSTRAINT "medalhas_obrigatorias_map_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."medalhas_slug_aliases"
    ADD CONSTRAINT "medalhas_slug_aliases_pkey" PRIMARY KEY ("slug_alias");



ALTER TABLE ONLY "public"."mensagens_chat"
    ADD CONSTRAINT "mensagens_chat_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."metrics_daily"
    ADD CONSTRAINT "metrics_daily_pkey" PRIMARY KEY ("date");



ALTER TABLE ONLY "public"."missoes"
    ADD CONSTRAINT "missoes_codigo_key" UNIQUE ("codigo");



ALTER TABLE ONLY "public"."missoes"
    ADD CONSTRAINT "missoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."modelos_precificacao_versionada"
    ADD CONSTRAINT "modelos_precificacao_versionada_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."modulos"
    ADD CONSTRAINT "modulos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."os_task_logs"
    ADD CONSTRAINT "os_task_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."os_tasks"
    ADD CONSTRAINT "os_tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."patente_regras"
    ADD CONSTRAINT "patente_regras_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."patentes_catalogo"
    ADD CONSTRAINT "patentes_catalogo_codigo_key" UNIQUE ("codigo");



ALTER TABLE ONLY "public"."patentes_catalogo"
    ADD CONSTRAINT "patentes_catalogo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."premiacoes"
    ADD CONSTRAINT "premiacoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."premiacoes"
    ADD CONSTRAINT "premiacoes_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."progresso_aulas"
    ADD CONSTRAINT "progresso_aulas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."progresso_aulas"
    ADD CONSTRAINT "progresso_aulas_user_id_aula_id_key" UNIQUE ("user_id", "aula_id");



ALTER TABLE ONLY "public"."progresso_missoes"
    ADD CONSTRAINT "progresso_missoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."progresso_missoes"
    ADD CONSTRAINT "progresso_missoes_recruta_id_missao_id_key" UNIQUE ("recruta_id", "missao_id");



ALTER TABLE ONLY "public"."progresso_recruta"
    ADD CONSTRAINT "progresso_recruta_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."qd_migration_rdm_lessons_20260503"
    ADD CONSTRAINT "qd_migration_rdm_lessons_20260503_pkey" PRIMARY KEY ("lesson_id");



ALTER TABLE ONLY "public"."ranking_periodos"
    ADD CONSTRAINT "ranking_periodos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ranking_resultados"
    ADD CONSTRAINT "ranking_resultados_pkey" PRIMARY KEY ("periodo_id", "user_id");



ALTER TABLE ONLY "public"."recruta_ciclo_status"
    ADD CONSTRAINT "recruta_ciclo_status_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_ciclo_status"
    ADD CONSTRAINT "recruta_ciclo_status_recruta_id_ciclo_id_key" UNIQUE ("recruta_id", "ciclo_id");



ALTER TABLE ONLY "public"."recruta_desempenho_revisoes"
    ADD CONSTRAINT "recruta_desempenho_revisoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_desempenho_revisoes"
    ADD CONSTRAINT "recruta_desempenho_revisoes_recruta_id_revisao_id_key" UNIQUE ("recruta_id", "revisao_id");



ALTER TABLE ONLY "public"."recruta_licoes"
    ADD CONSTRAINT "recruta_licoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_licoes"
    ADD CONSTRAINT "recruta_licoes_recruta_id_licao_id_key" UNIQUE ("recruta_id", "licao_id");



ALTER TABLE ONLY "public"."recruta_medalhas_eventos"
    ADD CONSTRAINT "recruta_medalhas_eventos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_medalhas_eventos"
    ADD CONSTRAINT "recruta_medalhas_eventos_recruta_id_medalha_evento_id_key" UNIQUE ("recruta_id", "medalha_evento_id");



ALTER TABLE ONLY "public"."recruta_modulos"
    ADD CONSTRAINT "recruta_modulos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_modulos"
    ADD CONSTRAINT "recruta_modulos_recruta_id_modulo_id_key" UNIQUE ("recruta_id", "modulo_id");



ALTER TABLE ONLY "public"."recruta_padrao_galeria"
    ADD CONSTRAINT "recruta_padrao_galeria_periodo_id_key" UNIQUE ("periodo_id");



ALTER TABLE ONLY "public"."recruta_padrao_galeria"
    ADD CONSTRAINT "recruta_padrao_galeria_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_patentes"
    ADD CONSTRAINT "recruta_patentes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_progresso"
    ADD CONSTRAINT "recruta_progresso_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_progresso"
    ADD CONSTRAINT "recruta_progresso_recruta_id_lesson_id_key" UNIQUE ("recruta_id", "lesson_id");



ALTER TABLE ONLY "public"."recruta_progressos_modulos"
    ADD CONSTRAINT "recruta_progressos_modulos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recruta_progressos_modulos"
    ADD CONSTRAINT "recruta_progressos_modulos_recruta_id_modulo_id_key" UNIQUE ("recruta_id", "modulo_id");



ALTER TABLE ONLY "public"."recruta_status"
    ADD CONSTRAINT "recruta_status_pkey" PRIMARY KEY ("recruta_id");



ALTER TABLE ONLY "public"."recrutas"
    ADD CONSTRAINT "recrutas_auth_id_unique" UNIQUE ("auth_id");



ALTER TABLE ONLY "public"."recrutas"
    ADD CONSTRAINT "recrutas_auth_unique" UNIQUE ("auth_id");



ALTER TABLE "public"."recrutas"
    ADD CONSTRAINT "recrutas_nome_guerra_formato_chk" CHECK ((("nome_guerra" IS NULL) OR ((("char_length"("nome_guerra") >= 3) AND ("char_length"("nome_guerra") <= 40)) AND ("nome_guerra" ~ '^[A-Za-zÀ-ÖØ-öø-ÿ0-9''.\- ]+$'::"text")))) NOT VALID;



ALTER TABLE "public"."recrutas"
    ADD CONSTRAINT "recrutas_onboarding_nome_guerra_chk" CHECK ((("onboarding_concluido" IS DISTINCT FROM true) OR ("nome_guerra" IS NOT NULL))) NOT VALID;



ALTER TABLE ONLY "public"."recrutas"
    ADD CONSTRAINT "recrutas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."revisoes"
    ADD CONSTRAINT "revisoes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."chat_logs"
    ADD CONSTRAINT "uq_chatlog_evento" UNIQUE ("evento_id");



ALTER TABLE ONLY "public"."modelos_precificacao_versionada"
    ADD CONSTRAINT "uq_modelo_versao" UNIQUE ("modelo", "versao");



ALTER TABLE ONLY "public"."aulas_concluidas"
    ADD CONSTRAINT "uq_user_aula" UNIQUE ("user_id", "aula_id");



ALTER TABLE ONLY "public"."usage_stats"
    ADD CONSTRAINT "usage_stats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_xp"
    ADD CONSTRAINT "user_xp_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."xp_eventos"
    ADD CONSTRAINT "xp_eventos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."xp_events"
    ADD CONSTRAINT "xp_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_analytics"
    ADD CONSTRAINT "buckets_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets"
    ADD CONSTRAINT "buckets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_vectors"
    ADD CONSTRAINT "buckets_vectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_pkey" PRIMARY KEY ("id");



CREATE INDEX "audit_logs_instance_id_idx" ON "auth"."audit_log_entries" USING "btree" ("instance_id");



CREATE UNIQUE INDEX "confirmation_token_idx" ON "auth"."users" USING "btree" ("confirmation_token") WHERE (("confirmation_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "custom_oauth_providers_created_at_idx" ON "auth"."custom_oauth_providers" USING "btree" ("created_at");



CREATE INDEX "custom_oauth_providers_enabled_idx" ON "auth"."custom_oauth_providers" USING "btree" ("enabled");



CREATE INDEX "custom_oauth_providers_identifier_idx" ON "auth"."custom_oauth_providers" USING "btree" ("identifier");



CREATE INDEX "custom_oauth_providers_provider_type_idx" ON "auth"."custom_oauth_providers" USING "btree" ("provider_type");



CREATE UNIQUE INDEX "email_change_token_current_idx" ON "auth"."users" USING "btree" ("email_change_token_current") WHERE (("email_change_token_current")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "email_change_token_new_idx" ON "auth"."users" USING "btree" ("email_change_token_new") WHERE (("email_change_token_new")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "factor_id_created_at_idx" ON "auth"."mfa_factors" USING "btree" ("user_id", "created_at");



CREATE INDEX "flow_state_created_at_idx" ON "auth"."flow_state" USING "btree" ("created_at" DESC);



CREATE INDEX "identities_email_idx" ON "auth"."identities" USING "btree" ("email" "text_pattern_ops");



COMMENT ON INDEX "auth"."identities_email_idx" IS 'Auth: Ensures indexed queries on the email column';



CREATE INDEX "identities_user_id_idx" ON "auth"."identities" USING "btree" ("user_id");



CREATE INDEX "idx_auth_code" ON "auth"."flow_state" USING "btree" ("auth_code");



CREATE INDEX "idx_oauth_client_states_created_at" ON "auth"."oauth_client_states" USING "btree" ("created_at");



CREATE INDEX "idx_user_id_auth_method" ON "auth"."flow_state" USING "btree" ("user_id", "authentication_method");



CREATE INDEX "mfa_challenge_created_at_idx" ON "auth"."mfa_challenges" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "mfa_factors_user_friendly_name_unique" ON "auth"."mfa_factors" USING "btree" ("friendly_name", "user_id") WHERE (TRIM(BOTH FROM "friendly_name") <> ''::"text");



CREATE INDEX "mfa_factors_user_id_idx" ON "auth"."mfa_factors" USING "btree" ("user_id");



CREATE INDEX "oauth_auth_pending_exp_idx" ON "auth"."oauth_authorizations" USING "btree" ("expires_at") WHERE ("status" = 'pending'::"auth"."oauth_authorization_status");



CREATE INDEX "oauth_clients_deleted_at_idx" ON "auth"."oauth_clients" USING "btree" ("deleted_at");



CREATE INDEX "oauth_consents_active_client_idx" ON "auth"."oauth_consents" USING "btree" ("client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_active_user_client_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_user_order_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "granted_at" DESC);



CREATE INDEX "one_time_tokens_relates_to_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("relates_to");



CREATE INDEX "one_time_tokens_token_hash_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("token_hash");



CREATE UNIQUE INDEX "one_time_tokens_user_id_token_type_key" ON "auth"."one_time_tokens" USING "btree" ("user_id", "token_type");



CREATE UNIQUE INDEX "reauthentication_token_idx" ON "auth"."users" USING "btree" ("reauthentication_token") WHERE (("reauthentication_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "recovery_token_idx" ON "auth"."users" USING "btree" ("recovery_token") WHERE (("recovery_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "refresh_tokens_instance_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id");



CREATE INDEX "refresh_tokens_instance_id_user_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id", "user_id");



CREATE INDEX "refresh_tokens_parent_idx" ON "auth"."refresh_tokens" USING "btree" ("parent");



CREATE INDEX "refresh_tokens_session_id_revoked_idx" ON "auth"."refresh_tokens" USING "btree" ("session_id", "revoked");



CREATE INDEX "refresh_tokens_updated_at_idx" ON "auth"."refresh_tokens" USING "btree" ("updated_at" DESC);



CREATE INDEX "saml_providers_sso_provider_id_idx" ON "auth"."saml_providers" USING "btree" ("sso_provider_id");



CREATE INDEX "saml_relay_states_created_at_idx" ON "auth"."saml_relay_states" USING "btree" ("created_at" DESC);



CREATE INDEX "saml_relay_states_for_email_idx" ON "auth"."saml_relay_states" USING "btree" ("for_email");



CREATE INDEX "saml_relay_states_sso_provider_id_idx" ON "auth"."saml_relay_states" USING "btree" ("sso_provider_id");



CREATE INDEX "sessions_not_after_idx" ON "auth"."sessions" USING "btree" ("not_after" DESC);



CREATE INDEX "sessions_oauth_client_id_idx" ON "auth"."sessions" USING "btree" ("oauth_client_id");



CREATE INDEX "sessions_user_id_idx" ON "auth"."sessions" USING "btree" ("user_id");



CREATE UNIQUE INDEX "sso_domains_domain_idx" ON "auth"."sso_domains" USING "btree" ("lower"("domain"));



CREATE INDEX "sso_domains_sso_provider_id_idx" ON "auth"."sso_domains" USING "btree" ("sso_provider_id");



CREATE UNIQUE INDEX "sso_providers_resource_id_idx" ON "auth"."sso_providers" USING "btree" ("lower"("resource_id"));



CREATE INDEX "sso_providers_resource_id_pattern_idx" ON "auth"."sso_providers" USING "btree" ("resource_id" "text_pattern_ops");



CREATE UNIQUE INDEX "unique_phone_factor_per_user" ON "auth"."mfa_factors" USING "btree" ("user_id", "phone");



CREATE INDEX "user_id_created_at_idx" ON "auth"."sessions" USING "btree" ("user_id", "created_at");



CREATE UNIQUE INDEX "users_email_partial_key" ON "auth"."users" USING "btree" ("email") WHERE ("is_sso_user" = false);



COMMENT ON INDEX "auth"."users_email_partial_key" IS 'Auth: A partial unique index that applies only when is_sso_user is false';



CREATE INDEX "users_instance_id_email_idx" ON "auth"."users" USING "btree" ("instance_id", "lower"(("email")::"text"));



CREATE INDEX "users_instance_id_idx" ON "auth"."users" USING "btree" ("instance_id");



CREATE INDEX "users_is_anonymous_idx" ON "auth"."users" USING "btree" ("is_anonymous");



CREATE INDEX "webauthn_challenges_expires_at_idx" ON "auth"."webauthn_challenges" USING "btree" ("expires_at");



CREATE INDEX "webauthn_challenges_user_id_idx" ON "auth"."webauthn_challenges" USING "btree" ("user_id");



CREATE UNIQUE INDEX "webauthn_credentials_credential_id_key" ON "auth"."webauthn_credentials" USING "btree" ("credential_id");



CREATE INDEX "webauthn_credentials_user_id_idx" ON "auth"."webauthn_credentials" USING "btree" ("user_id");



CREATE UNIQUE INDEX "billing_assinaturas_gateway_assinatura_unq" ON "public"."billing_assinaturas" USING "btree" ("gateway_assinatura_id") WHERE ("gateway_assinatura_id" IS NOT NULL);



CREATE INDEX "billing_assinaturas_status_idx" ON "public"."billing_assinaturas" USING "btree" ("status_assinatura");



CREATE INDEX "billing_notificacoes_log_recruta_idx" ON "public"."billing_notificacoes_log" USING "btree" ("recruta_id", "enviado_em" DESC);



CREATE INDEX "billing_notificacoes_log_tipo_idx" ON "public"."billing_notificacoes_log" USING "btree" ("tipo_evento", "status_envio", "enviado_em" DESC);



CREATE INDEX "billing_pagamentos_assinatura_idx" ON "public"."billing_pagamentos" USING "btree" ("assinatura_id");



CREATE UNIQUE INDEX "billing_pagamentos_gateway_event_unq" ON "public"."billing_pagamentos" USING "btree" ("gateway_nome", "gateway_event_id");



CREATE INDEX "billing_pagamentos_recruta_idx" ON "public"."billing_pagamentos" USING "btree" ("recruta_id", "created_at" DESC);



CREATE INDEX "billing_reconciliacao_gateway_idx" ON "public"."billing_reconciliacao" USING "btree" ("gateway_nome", "gateway_event_id", "executado_em" DESC);



CREATE INDEX "billing_reconciliacao_recruta_idx" ON "public"."billing_reconciliacao" USING "btree" ("recruta_id", "executado_em" DESC);



CREATE INDEX "billing_reconciliacao_status_idx" ON "public"."billing_reconciliacao" USING "btree" ("status_execucao", "executado_em" DESC);



CREATE INDEX "billing_reconciliation_issues_gateway_idx" ON "public"."billing_reconciliation_issues" USING "btree" ("gateway_event_id", "executado_em" DESC);



CREATE INDEX "billing_reconciliation_issues_recruta_idx" ON "public"."billing_reconciliation_issues" USING "btree" ("recruta_id", "status_execucao", "executado_em" DESC);



CREATE INDEX "c7_execucao_diaria_log_created_at_ix" ON "public"."c7_execucao_diaria_log" USING "btree" ("created_at" DESC);



CREATE INDEX "c9_aula_conteudos_aula_idx" ON "public"."c9_aula_conteudos" USING "btree" ("aula_id");



CREATE UNIQUE INDEX "c9_aula_conteudos_um_ativo_por_tipo" ON "public"."c9_aula_conteudos" USING "btree" ("aula_id", "tipo") WHERE (("ativo" = true) AND ("deleted_at" IS NULL));



CREATE UNIQUE INDEX "c9_aula_conteudos_unique_versao" ON "public"."c9_aula_conteudos" USING "btree" ("aula_id", "tipo", "versao") WHERE ("deleted_at" IS NULL);



CREATE INDEX "c9_aula_flashcards_aula_idx" ON "public"."c9_aula_flashcards" USING "btree" ("aula_id", "ordem");



CREATE INDEX "c9_aula_quiz_alternativas_pergunta_idx" ON "public"."c9_aula_quiz_alternativas" USING "btree" ("pergunta_id", "ordem");



CREATE UNIQUE INDEX "c9_aula_quiz_alternativas_uma_correta" ON "public"."c9_aula_quiz_alternativas" USING "btree" ("pergunta_id") WHERE (("correta" = true) AND ("deleted_at" IS NULL));



CREATE INDEX "c9_aula_quiz_perguntas_quiz_idx" ON "public"."c9_aula_quiz_perguntas" USING "btree" ("quiz_id", "ordem");



CREATE INDEX "c9_aula_quiz_tentativas_quiz_idx" ON "public"."c9_aula_quiz_tentativas" USING "btree" ("quiz_id", "created_at" DESC);



CREATE INDEX "c9_aula_quiz_tentativas_recruta_idx" ON "public"."c9_aula_quiz_tentativas" USING "btree" ("recruta_id", "created_at" DESC);



CREATE INDEX "c9_aula_quizzes_aula_idx" ON "public"."c9_aula_quizzes" USING "btree" ("aula_id");



CREATE INDEX "chat_conversas_recruta_ix" ON "public"."chat_conversas" USING "btree" ("recruta_id");



CREATE INDEX "chat_conversas_recruta_updated_ix" ON "public"."chat_conversas" USING "btree" ("recruta_id", "updated_at" DESC);



CREATE INDEX "chat_events_auth_created_desc_idx" ON "public"."chat_events" USING "btree" ("auth_id", "created_at" DESC);



CREATE INDEX "chat_events_auth_id_idx" ON "public"."chat_events" USING "btree" ("auth_id");



CREATE INDEX "chat_events_recruta_id_idx" ON "public"."chat_events" USING "btree" ("recruta_id");



CREATE INDEX "chat_events_status_idx" ON "public"."chat_events" USING "btree" ("status");



CREATE INDEX "chat_mensagens_conversa_created_ix" ON "public"."chat_mensagens" USING "btree" ("conversa_id", "created_at");



CREATE UNIQUE INDEX "chat_mensagens_idempotency_key_uk" ON "public"."chat_mensagens" USING "btree" ("idempotency_key");



CREATE INDEX "chat_mensagens_recruta_created_ix" ON "public"."chat_mensagens" USING "btree" ("recruta_id", "created_at" DESC);



CREATE INDEX "chat_reads_recruta_ix" ON "public"."chat_reads" USING "btree" ("recruta_id");



CREATE INDEX "chat_summaries_thread_id_idx" ON "public"."chat_summaries" USING "btree" ("thread_id");



CREATE INDEX "chat_summaries_updated_at_idx" ON "public"."chat_summaries" USING "btree" ("updated_at" DESC);



CREATE INDEX "idx_alteracoes_medalha" ON "public"."medalhas_alteracoes_pendentes" USING "btree" ("medalha_id");



CREATE INDEX "idx_alteracoes_status" ON "public"."medalhas_alteracoes_pendentes" USING "btree" ("status");



CREATE INDEX "idx_atividade_log_ciclo" ON "public"."atividade_academica_log" USING "btree" ("ciclo_id");



CREATE INDEX "idx_atividade_log_recruta_data" ON "public"."atividade_academica_log" USING "btree" ("recruta_id", "registrado_em" DESC);



CREATE INDEX "idx_automacoes_correlation_id" ON "public"."automacoes_execucoes" USING "btree" ("correlation_id");



CREATE INDEX "idx_automacoes_workflow_created_at" ON "public"."automacoes_execucoes" USING "btree" ("workflow", "created_at" DESC);



CREATE INDEX "idx_c5_alertas_operacionais_detectado_em" ON "public"."c5_alertas_operacionais" USING "btree" ("detectado_em" DESC);



CREATE INDEX "idx_c5_alertas_operacionais_dominio_detectado_em" ON "public"."c5_alertas_operacionais" USING "btree" ("dominio_analitico", "detectado_em" DESC);



CREATE INDEX "idx_c5_alertas_operacionais_tipo_detectado_em" ON "public"."c5_alertas_operacionais" USING "btree" ("tipo_alerta", "detectado_em" DESC);



CREATE INDEX "idx_c5_eventos_correlation_id" ON "public"."eventos_institucionais" USING "btree" ("correlation_id") WHERE ("correlation_id" IS NOT NULL);



CREATE INDEX "idx_c5_fatos_analytics_dominio_dia" ON "public"."c5_fatos_analytics" USING "btree" ("dominio_analitico", "dia");



CREATE INDEX "idx_c5_fatos_analytics_evento_dia" ON "public"."c5_fatos_analytics" USING "btree" ("evento_analitico", "dia");



CREATE INDEX "idx_c5_fatos_analytics_recruta_dia" ON "public"."c5_fatos_analytics" USING "btree" ("id_recruta", "dia");



CREATE INDEX "idx_c5_fatos_analytics_timestamp" ON "public"."c5_fatos_analytics" USING "btree" ("timestamp_evento");



CREATE INDEX "idx_c5_jobs_execucao_log_job_executado_em" ON "public"."c5_jobs_execucao_log" USING "btree" ("job", "executado_em" DESC);



CREATE INDEX "idx_c5_metricas_diarias_dia" ON "public"."c5_metricas_diarias" USING "btree" ("dia");



CREATE INDEX "idx_c5_metricas_diarias_dominio_dia" ON "public"."c5_metricas_diarias" USING "btree" ("dominio_analitico", "dia");



CREATE INDEX "idx_c5_metricas_diarias_evento_dia" ON "public"."c5_metricas_diarias" USING "btree" ("evento_analitico", "dia");



CREATE INDEX "idx_c5_metricas_recruta_dominio_dia" ON "public"."c5_metricas_recruta" USING "btree" ("dominio_analitico", "dia");



CREATE INDEX "idx_c5_metricas_recruta_evento_dia" ON "public"."c5_metricas_recruta" USING "btree" ("evento_analitico", "dia");



CREATE INDEX "idx_c5_metricas_recruta_recruta_dia" ON "public"."c5_metricas_recruta" USING "btree" ("id_recruta", "dia");



CREATE INDEX "idx_chat_audit_recruta" ON "public"."chat_audit_log" USING "btree" ("recruta_id");



CREATE INDEX "idx_chat_audit_timestamp" ON "public"."chat_audit_log" USING "btree" ("timestamp_utc");



CREATE INDEX "idx_chatlogs_correlation_id" ON "public"."chat_logs" USING "btree" ("correlation_id");



CREATE INDEX "idx_chatlogs_recruta_created_at" ON "public"."chat_logs" USING "btree" ("recruta_id", "created_at" DESC);



CREATE INDEX "idx_ciclos_formativos_forca_vigente" ON "public"."ciclos_formativos" USING "btree" ("forca", "vigente");



CREATE INDEX "idx_conversation_locks_expires_at" ON "public"."conversation_locks" USING "btree" ("expires_at");



CREATE INDEX "idx_cronograma_semanal_ciclo_semana" ON "public"."cronograma_semanal" USING "btree" ("ciclo_id", "semana_num");



CREATE INDEX "idx_eventos_correlation_id" ON "public"."eventos_institucionais" USING "btree" ("correlation_id");



CREATE INDEX "idx_eventos_recruta_created_at" ON "public"."eventos_institucionais" USING "btree" ("recruta_id", "created_at" DESC);



CREATE INDEX "idx_iea_marcos_emitidos_lookup" ON "public"."iea_marcos_emitidos" USING "btree" ("recruta_id", "ciclo_id", "marco");



CREATE INDEX "idx_iea_marcos_emitidos_recruta_ciclochave" ON "public"."iea_marcos_emitidos" USING "btree" ("recruta_id", "ciclo_chave", "marco");



CREATE INDEX "idx_iea_snapshots_recruta_ciclo_em" ON "public"."iea_snapshots" USING "btree" ("recruta_id", "ciclo_id", "calculado_em" DESC);



CREATE INDEX "idx_iea_snapshots_recruta_em" ON "public"."iea_snapshots" USING "btree" ("recruta_id", "calculado_em" DESC);



CREATE INDEX "idx_lesson_media_lesson_id" ON "public"."lesson_media" USING "btree" ("lesson_id");



CREATE INDEX "idx_lesson_media_type" ON "public"."lesson_media" USING "btree" ("type");



CREATE UNIQUE INDEX "idx_lesson_media_unique_order" ON "public"."lesson_media" USING "btree" ("lesson_id", "order");



CREATE INDEX "idx_medalha_versionamento_medalha" ON "public"."medalhas_catalogo_versionamento" USING "btree" ("medalha_id");



CREATE UNIQUE INDEX "idx_medalha_versionamento_unique" ON "public"."medalhas_catalogo_versionamento" USING "btree" ("medalha_id", "versao");



CREATE INDEX "idx_medalhas_concessao_log_created_at_desc" ON "public"."medalhas_concessao_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_medalhas_concessao_log_medalha_slug" ON "public"."medalhas_concessao_log" USING "btree" ("medalha_slug");



CREATE INDEX "idx_medalhas_concessao_log_motivo_bloqueio" ON "public"."medalhas_concessao_log" USING "btree" ("motivo_bloqueio");



CREATE INDEX "idx_medalhas_concessao_log_recruta_id" ON "public"."medalhas_concessao_log" USING "btree" ("recruta_id");



CREATE INDEX "idx_medalhas_slug_aliases_alias" ON "public"."medalhas_slug_aliases" USING "btree" ("slug_alias");



CREATE INDEX "idx_messages_user_created_at" ON "public"."messages" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_modelos_precificacao_modelo_effective" ON "public"."modelos_precificacao_versionada" USING "btree" ("modelo", "effective_from" DESC);



CREATE UNIQUE INDEX "idx_mv_campeao_mensal" ON "public"."mv_campeao_mensal" USING "btree" ("forca", "mes_referencia");



CREATE UNIQUE INDEX "idx_mv_ranking_mensal" ON "public"."mv_ranking_mensal" USING "btree" ("recruta_id", "forca", "mes_referencia");



CREATE UNIQUE INDEX "idx_mv_xp_mensal_recruta" ON "public"."mv_xp_mensal_recruta" USING "btree" ("recruta_id", "forca", "mes_referencia");



CREATE INDEX "idx_os_task_logs_correlation_id" ON "public"."os_task_logs" USING "btree" ("correlation_id");



CREATE INDEX "idx_os_task_logs_created_at" ON "public"."os_task_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_os_task_logs_event_type" ON "public"."os_task_logs" USING "btree" ("event_type");



CREATE INDEX "idx_os_task_logs_task_id" ON "public"."os_task_logs" USING "btree" ("task_id");



CREATE INDEX "idx_os_tasks_correlation_id" ON "public"."os_tasks" USING "btree" ("correlation_id");



CREATE INDEX "idx_os_tasks_dedupe_key" ON "public"."os_tasks" USING "btree" ("dedupe_key");



CREATE INDEX "idx_os_tasks_priority_created" ON "public"."os_tasks" USING "btree" ("priority", "created_at");



CREATE INDEX "idx_os_tasks_status" ON "public"."os_tasks" USING "btree" ("status");



CREATE INDEX "idx_pipeline_execucoes_aula_id" ON "public"."aula_pipeline_execucoes" USING "btree" ("aula_id");



CREATE INDEX "idx_pipeline_execucoes_status" ON "public"."aula_pipeline_execucoes" USING "btree" ("status");



CREATE INDEX "idx_pipeline_logs_agente" ON "public"."aula_pipeline_logs" USING "btree" ("agente");



CREATE INDEX "idx_pipeline_logs_execucao" ON "public"."aula_pipeline_logs" USING "btree" ("execucao_id", "etapa_ordem");



CREATE INDEX "idx_recruta_ciclo_status_recruta" ON "public"."recruta_ciclo_status" USING "btree" ("recruta_id", "ciclo_id");



CREATE INDEX "idx_recruta_status_recruta_id" ON "public"."recruta_status" USING "btree" ("recruta_id");



COMMENT ON INDEX "public"."idx_recruta_status_recruta_id" IS 'Benchmark readiness: lookup rápido por recruta_id em joins/exists de RLS.';



CREATE INDEX "idx_recruta_status_ultima_atividade_cursor" ON "public"."recruta_status" USING "btree" ("ultima_atividade" DESC, "recruta_id" DESC);



COMMENT ON INDEX "public"."idx_recruta_status_ultima_atividade_cursor" IS 'Benchmark readiness: suporta paginação por cursor em api.v_recrutas_status_v1 (ultima_atividade DESC, recruta_id DESC).';



CREATE INDEX "idx_recrutas_nome_guerra" ON "public"."recrutas" USING "btree" ("lower"("nome_guerra"));



CREATE INDEX "idx_usage_stats_user_created_at" ON "public"."usage_stats" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_users_role_id" ON "public"."users" USING "btree" ("role_id");



CREATE INDEX "ix_c7_regras_ativas_por_ciclo" ON "public"."c7_regras_bloqueio_por_ciclo" USING "btree" ("ciclo_id", "medalha_slug") WHERE ("active" = true);



CREATE INDEX "ix_cronograma_semanal_ciclo_semana" ON "public"."cronograma_semanal" USING "btree" ("ciclo_id", "semana_num");



CREATE INDEX "ix_medalhas_concedidas_medalha_recruta" ON "public"."medalhas_concedidas" USING "btree" ("medalha_id", "recruta_id");



CREATE INDEX "ix_recruta_ciclo_status_recruta_ciclo" ON "public"."recruta_ciclo_status" USING "btree" ("recruta_id", "ciclo_id");



CREATE INDEX "ix_recrutas_auth_id" ON "public"."recrutas" USING "btree" ("auth_id");



CREATE INDEX "medalha_regras_medalha_id_ix" ON "public"."medalha_regras" USING "btree" ("medalha_id");



CREATE INDEX "medalha_regras_metrica_ix" ON "public"."medalha_regras" USING "btree" ("metrica");



CREATE INDEX "medalha_regras_tipo_regra_ix" ON "public"."medalha_regras" USING "btree" ("tipo_regra");



CREATE UNIQUE INDEX "medalha_regras_uk_c7" ON "public"."medalha_regras" USING "btree" ("medalha_id", "metrica", "valor", "operador");



CREATE UNIQUE INDEX "medalha_regras_uk_idempotencia" ON "public"."medalha_regras" USING "btree" ("medalha_id", "tipo_regra", "parametro", "comparador");



CREATE INDEX "medalhas_concedidas_recruta_medalha_ix" ON "public"."medalhas_concedidas" USING "btree" ("recruta_id", "medalha_id");



CREATE INDEX "medalhas_concessao_log_recruta_created_at_ix" ON "public"."medalhas_concessao_log" USING "btree" ("recruta_id", "created_at" DESC);



CREATE INDEX "medalhas_concessao_log_run_id_ix" ON "public"."medalhas_concessao_log" USING "btree" ("run_id");



CREATE INDEX "medalhas_concessao_log_slug_created_at_ix" ON "public"."medalhas_concessao_log" USING "btree" ("medalha_slug", "created_at" DESC);



CREATE UNIQUE INDEX "medalhas_obrigatorias_map_uk" ON "public"."medalhas_obrigatorias_map" USING "btree" ("forca", "medalha_slug");



CREATE INDEX "mv_c7_metricas_problema_resumo_metrica" ON "public"."mv_c7_metricas_problema_resumo" USING "btree" ("metrica");



CREATE UNIQUE INDEX "mv_c7_metricas_problema_resumo_pk" ON "public"."mv_c7_metricas_problema_resumo" USING "btree" ("metrica", "tipo_problema");



CREATE INDEX "mv_c7_metricas_problema_resumo_tipo" ON "public"."mv_c7_metricas_problema_resumo" USING "btree" ("tipo_problema");



CREATE INDEX "mv_c7_metricas_problema_resumo_total_desc" ON "public"."mv_c7_metricas_problema_resumo" USING "btree" ("total_ocorrencias" DESC);



CREATE INDEX "mv_c7_status_recruta_atual_bloqueadas_desc" ON "public"."mv_c7_status_recruta_atual" USING "btree" ("total_bloqueadas" DESC);



CREATE UNIQUE INDEX "mv_c7_status_recruta_atual_pk" ON "public"."mv_c7_status_recruta_atual" USING "btree" ("recruta_id");



CREATE INDEX "mv_c7_status_recruta_atual_status" ON "public"."mv_c7_status_recruta_atual" USING "btree" ("status");



CREATE INDEX "recruta_ciclo_status_data_inicio_ix" ON "public"."recruta_ciclo_status" USING "btree" ("data_inicio_individual");



COMMENT ON INDEX "public"."recrutas_auth_unique" IS 'Hardening C5 (PARTE 2): garante unicidade e performance de lookup auth.uid() -> recruta_id (usado por public.c5_recruta_id_for_auth). Índice pré-existente, formalizado por comentário.';



CREATE UNIQUE INDEX "unique_progresso" ON "public"."progresso_recruta" USING "btree" ("recruta_id", "licao_id");



CREATE UNIQUE INDEX "uq_c5_eventos_idempotency_key_notnull" ON "public"."eventos_institucionais" USING "btree" ("idempotency_key") WHERE ("idempotency_key" IS NOT NULL);



CREATE UNIQUE INDEX "uq_c7_ciclos_single_active" ON "public"."c7_ciclos" USING "btree" ("active") WHERE ("active" IS TRUE);



CREATE UNIQUE INDEX "uq_c7_regras_por_ciclo" ON "public"."c7_regras_bloqueio_por_ciclo" USING "btree" ("ciclo_id", "medalha_slug", "tipo_regra");



CREATE UNIQUE INDEX "uq_medalhas_slug_aliases_alias" ON "public"."medalhas_slug_aliases" USING "btree" ("slug_alias");



CREATE UNIQUE INDEX "uq_os_tasks_dedupe_active" ON "public"."os_tasks" USING "btree" ("dedupe_key") WHERE (("dedupe_key" IS NOT NULL) AND ("status" = ANY (ARRAY['pending'::"text", 'running'::"text"])));



CREATE UNIQUE INDEX "uq_pipeline_logs_execucao_agente" ON "public"."aula_pipeline_logs" USING "btree" ("execucao_id", "agente");



CREATE UNIQUE INDEX "uq_pipeline_logs_execucao_ordem" ON "public"."aula_pipeline_logs" USING "btree" ("execucao_id", "etapa_ordem");



CREATE UNIQUE INDEX "ux_c7_ciclos_single_active" ON "public"."c7_ciclos" USING "btree" ("active") WHERE ("active" = true);



CREATE UNIQUE INDEX "ux_c7_regras_unq" ON "public"."c7_regras_bloqueio_por_ciclo" USING "btree" ("ciclo_id", "medalha_slug", "tipo_regra");



CREATE UNIQUE INDEX "ux_eventos_institucionais_auth_ref" ON "public"."eventos_institucionais" USING "btree" ("tipo", "referencia_id") WHERE (("tipo" = 'auth'::"text") AND ("referencia_id" IS NOT NULL));



CREATE UNIQUE INDEX "ux_medalhas_catalogo_slug" ON "public"."medalhas_catalogo" USING "btree" ("slug");



CREATE UNIQUE INDEX "ux_medalhas_concedidas_recruta_medalha" ON "public"."medalhas_concedidas" USING "btree" ("recruta_id", "medalha_id");



CREATE UNIQUE INDEX "ux_xp_eventos_lesson_unique" ON "public"."xp_eventos" USING "btree" ("recruta_id", "referencia_id") WHERE ("origem" = 'lesson_complete'::"text");



CREATE INDEX "xp_eventos_recruta_ix" ON "public"."xp_eventos" USING "btree" ("recruta_id");



CREATE UNIQUE INDEX "bname" ON "storage"."buckets" USING "btree" ("name");



CREATE UNIQUE INDEX "bucketid_objname" ON "storage"."objects" USING "btree" ("bucket_id", "name");



CREATE UNIQUE INDEX "buckets_analytics_unique_name_idx" ON "storage"."buckets_analytics" USING "btree" ("name") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_multipart_uploads_list" ON "storage"."s3_multipart_uploads" USING "btree" ("bucket_id", "key", "created_at");



CREATE INDEX "idx_objects_bucket_id_name" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C");



CREATE INDEX "idx_objects_bucket_id_name_lower" ON "storage"."objects" USING "btree" ("bucket_id", "lower"("name") COLLATE "C");



CREATE INDEX "name_prefix_search" ON "storage"."objects" USING "btree" ("name" "text_pattern_ops");



CREATE UNIQUE INDEX "vector_indexes_name_bucket_id_idx" ON "storage"."vector_indexes" USING "btree" ("name", "bucket_id");



CREATE OR REPLACE VIEW "public"."v_c9_quiz_execucao" WITH ("security_invoker"='true') AS
 SELECT "q"."id" AS "quiz_id",
    "q"."aula_id",
    "q"."titulo",
    "q"."descricao",
    "q"."metadata",
    COALESCE("jsonb_agg"("jsonb_build_object"('pergunta_id', "p"."id", 'codigo', ("p"."metadata" ->> 'codigo'::"text"), 'peso', ("p"."metadata" ->> 'peso'::"text"), 'tempo', ("p"."metadata" ->> 'tempo'::"text"), 'enunciado', "p"."enunciado", 'explicacao', "p"."explicacao", 'ordem', "p"."ordem", 'alternativas', ( SELECT COALESCE("jsonb_agg"("jsonb_build_object"('alternativa_id', "a"."id", 'texto', "a"."texto", 'ordem', "a"."ordem") ORDER BY "a"."ordem"), '[]'::"jsonb") AS "coalesce"
           FROM "public"."c9_aula_quiz_alternativas" "a"
          WHERE (("a"."pergunta_id" = "p"."id") AND ("a"."ativo" = true) AND ("a"."deleted_at" IS NULL)))) ORDER BY "p"."ordem") FILTER (WHERE ("p"."id" IS NOT NULL)), '[]'::"jsonb") AS "perguntas",
    ("count"("p"."id"))::integer AS "total_perguntas"
   FROM ("public"."c9_aula_quizzes" "q"
     LEFT JOIN "public"."c9_aula_quiz_perguntas" "p" ON ((("p"."quiz_id" = "q"."id") AND ("p"."ativo" = true) AND ("p"."deleted_at" IS NULL))))
  WHERE (("q"."ativo" = true) AND ("q"."deleted_at" IS NULL))
  GROUP BY "q"."id";



CREATE OR REPLACE TRIGGER "on_auth_user_created" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_user"();



CREATE OR REPLACE TRIGGER "trg_auth_single_session" AFTER INSERT ON "auth"."sessions" FOR EACH ROW EXECUTE FUNCTION "public"."_auth_enforce_single_session"();



CREATE OR REPLACE TRIGGER "c9_aula_conteudos_updated_at" BEFORE UPDATE ON "public"."c9_aula_conteudos" FOR EACH ROW EXECUTE FUNCTION "public"."c9_set_updated_at"();



CREATE OR REPLACE TRIGGER "c9_aula_flashcards_updated_at" BEFORE UPDATE ON "public"."c9_aula_flashcards" FOR EACH ROW EXECUTE FUNCTION "public"."c9_set_updated_at"();



CREATE OR REPLACE TRIGGER "c9_aula_quiz_alternativas_updated_at" BEFORE UPDATE ON "public"."c9_aula_quiz_alternativas" FOR EACH ROW EXECUTE FUNCTION "public"."c9_set_updated_at"();



CREATE OR REPLACE TRIGGER "c9_aula_quiz_perguntas_updated_at" BEFORE UPDATE ON "public"."c9_aula_quiz_perguntas" FOR EACH ROW EXECUTE FUNCTION "public"."c9_set_updated_at"();



CREATE OR REPLACE TRIGGER "c9_aula_quizzes_updated_at" BEFORE UPDATE ON "public"."c9_aula_quizzes" FOR EACH ROW EXECUTE FUNCTION "public"."c9_set_updated_at"();



CREATE OR REPLACE TRIGGER "set_data_inicio_individual" BEFORE INSERT OR UPDATE OF "ciclo_id", "semana_atual", "data_inicio_individual" ON "public"."recruta_ciclo_status" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_data_inicio_individual"();



CREATE OR REPLACE TRIGGER "trg_after_insert_desempenho" AFTER INSERT ON "public"."recruta_desempenho_revisoes" FOR EACH ROW EXECUTE FUNCTION "public"."trg_verificar_medalhas_desempenho"();



CREATE OR REPLACE TRIGGER "trg_after_insert_recruta_progressos_modulos" AFTER INSERT ON "public"."recruta_progressos_modulos" FOR EACH ROW EXECUTE FUNCTION "public"."trg_verificar_medalhas_conclusao"();



CREATE OR REPLACE TRIGGER "trg_after_update_desempenho" AFTER UPDATE ON "public"."recruta_desempenho_revisoes" FOR EACH ROW EXECUTE FUNCTION "public"."trg_verificar_medalhas_desempenho"();



CREATE OR REPLACE TRIGGER "trg_after_update_recruta_progressos_modulos" AFTER UPDATE ON "public"."recruta_progressos_modulos" FOR EACH ROW EXECUTE FUNCTION "public"."trg_verificar_medalhas_conclusao"();



CREATE OR REPLACE TRIGGER "trg_billing_assinaturas_touch_updated_at" BEFORE UPDATE ON "public"."billing_assinaturas" FOR EACH ROW EXECUTE FUNCTION "public"."fn_touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_c5_auditar_evento" AFTER INSERT OR DELETE OR UPDATE ON "public"."eventos_institucionais" FOR EACH ROW EXECUTE FUNCTION "public"."c5_auditar_evento_institucional"();



CREATE OR REPLACE TRIGGER "trg_c5_guard_eventos_institucionais" BEFORE INSERT ON "public"."eventos_institucionais" FOR EACH ROW EXECUTE FUNCTION "public"."c5_guard_eventos_institucionais"();



CREATE OR REPLACE TRIGGER "trg_c5_normalizar_evento" BEFORE INSERT ON "public"."eventos_institucionais" FOR EACH ROW EXECUTE FUNCTION "public"."c5_normalizar_evento_institucional"();



CREATE OR REPLACE TRIGGER "trg_c6_set_updated_at" BEFORE UPDATE ON "public"."recruta_ciclo_status" FOR EACH ROW EXECUTE FUNCTION "public"."c6_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_chat_events_set_updated_at" BEFORE UPDATE ON "public"."chat_events" FOR EACH ROW EXECUTE FUNCTION "public"."_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_chat_summaries_touch_updated_at" BEFORE UPDATE ON "public"."chat_summaries" FOR EACH ROW EXECUTE FUNCTION "public"."fn_touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_emitir_evento_promocao" AFTER INSERT ON "public"."recruta_patentes" FOR EACH ROW EXECUTE FUNCTION "public"."emitir_evento_promocao"();



CREATE OR REPLACE TRIGGER "trg_os_tasks_updated_at" BEFORE UPDATE ON "public"."os_tasks" FOR EACH ROW EXECUTE FUNCTION "public"."fn_os_set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_pipeline_execucoes_set_updated_at" BEFORE UPDATE ON "public"."aula_pipeline_execucoes" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_recrutas_normalizar_nome_guerra" BEFORE INSERT OR UPDATE OF "nome_guerra" ON "public"."recrutas" FOR EACH ROW EXECUTE FUNCTION "public"."trg_recrutas_normalizar_nome_guerra"();



CREATE OR REPLACE TRIGGER "trg_set_nome_default" BEFORE INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_nome_default"();



CREATE OR REPLACE TRIGGER "trg_update_metrics_daily" BEFORE UPDATE ON "public"."metrics_daily" FOR EACH ROW EXECUTE FUNCTION "public"."update_metrics_daily_updated_at"();



CREATE OR REPLACE TRIGGER "trg_xp_aula" AFTER INSERT ON "public"."aulas_concluidas" FOR EACH ROW EXECUTE FUNCTION "public"."fn_conceder_xp_aula"();



CREATE OR REPLACE TRIGGER "trigger_set_updated_at" BEFORE UPDATE ON "public"."recrutas" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "enforce_bucket_name_length_trigger" BEFORE INSERT OR UPDATE OF "name" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_name_length"();



CREATE OR REPLACE TRIGGER "protect_buckets_delete" BEFORE DELETE ON "storage"."buckets" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "protect_objects_delete" BEFORE DELETE ON "storage"."objects" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "update_objects_updated_at" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."update_updated_at_column"();



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_auth_factor_id_fkey" FOREIGN KEY ("factor_id") REFERENCES "auth"."mfa_factors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_flow_state_id_fkey" FOREIGN KEY ("flow_state_id") REFERENCES "auth"."flow_state"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_oauth_client_id_fkey" FOREIGN KEY ("oauth_client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."webauthn_challenges"
    ADD CONSTRAINT "webauthn_challenges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."webauthn_credentials"
    ADD CONSTRAINT "webauthn_credentials_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."atividade_academica_log"
    ADD CONSTRAINT "atividade_academica_log_ciclo_id_fkey" FOREIGN KEY ("ciclo_id") REFERENCES "public"."ciclos_formativos"("id");



ALTER TABLE ONLY "public"."atividade_academica_log"
    ADD CONSTRAINT "atividade_academica_log_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."aula_pipeline_execucoes"
    ADD CONSTRAINT "aula_pipeline_execucoes_aula_id_fkey" FOREIGN KEY ("aula_id") REFERENCES "public"."aulas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."aula_pipeline_logs"
    ADD CONSTRAINT "aula_pipeline_logs_execucao_id_fkey" FOREIGN KEY ("execucao_id") REFERENCES "public"."aula_pipeline_execucoes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_assinaturas"
    ADD CONSTRAINT "billing_assinaturas_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_notificacoes_log"
    ADD CONSTRAINT "billing_notificacoes_log_assinatura_id_fkey" FOREIGN KEY ("assinatura_id") REFERENCES "public"."billing_assinaturas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_notificacoes_log"
    ADD CONSTRAINT "billing_notificacoes_log_pagamento_id_fkey" FOREIGN KEY ("pagamento_id") REFERENCES "public"."billing_pagamentos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_notificacoes_log"
    ADD CONSTRAINT "billing_notificacoes_log_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_pagamentos"
    ADD CONSTRAINT "billing_pagamentos_assinatura_id_fkey" FOREIGN KEY ("assinatura_id") REFERENCES "public"."billing_assinaturas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_pagamentos"
    ADD CONSTRAINT "billing_pagamentos_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_reconciliacao"
    ADD CONSTRAINT "billing_reconciliacao_assinatura_id_fkey" FOREIGN KEY ("assinatura_id") REFERENCES "public"."billing_assinaturas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_reconciliacao"
    ADD CONSTRAINT "billing_reconciliacao_pagamento_id_fkey" FOREIGN KEY ("pagamento_id") REFERENCES "public"."billing_pagamentos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_reconciliacao"
    ADD CONSTRAINT "billing_reconciliacao_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_reconciliation_issues"
    ADD CONSTRAINT "billing_reconciliation_issues_assinatura_id_fkey" FOREIGN KEY ("assinatura_id") REFERENCES "public"."billing_assinaturas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_reconciliation_issues"
    ADD CONSTRAINT "billing_reconciliation_issues_pagamento_id_fkey" FOREIGN KEY ("pagamento_id") REFERENCES "public"."billing_pagamentos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_reconciliation_issues"
    ADD CONSTRAINT "billing_reconciliation_issues_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."c5_alertas_operacionais"
    ADD CONSTRAINT "c5_alertas_operacionais_regra_fk" FOREIGN KEY ("regra_origem") REFERENCES "public"."c5_regras_alerta"("tipo_alerta");



ALTER TABLE ONLY "public"."c7_regras_bloqueio_por_ciclo"
    ADD CONSTRAINT "c7_regras_bloqueio_por_ciclo_ciclo_id_fkey" FOREIGN KEY ("ciclo_id") REFERENCES "public"."c7_ciclos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."c9_aula_conteudos"
    ADD CONSTRAINT "c9_aula_conteudos_aula_fk" FOREIGN KEY ("aula_id") REFERENCES "public"."aulas"("id");



ALTER TABLE ONLY "public"."c9_aula_flashcards"
    ADD CONSTRAINT "c9_aula_flashcards_aula_fk" FOREIGN KEY ("aula_id") REFERENCES "public"."aulas"("id");



ALTER TABLE ONLY "public"."c9_aula_quiz_alternativas"
    ADD CONSTRAINT "c9_aula_quiz_alternativas_pergunta_id_fkey" FOREIGN KEY ("pergunta_id") REFERENCES "public"."c9_aula_quiz_perguntas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."c9_aula_quiz_perguntas"
    ADD CONSTRAINT "c9_aula_quiz_perguntas_quiz_id_fkey" FOREIGN KEY ("quiz_id") REFERENCES "public"."c9_aula_quizzes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."c9_aula_quiz_tentativas"
    ADD CONSTRAINT "c9_aula_quiz_tentativas_quiz_id_fkey" FOREIGN KEY ("quiz_id") REFERENCES "public"."c9_aula_quizzes"("id");



ALTER TABLE ONLY "public"."c9_aula_quiz_tentativas"
    ADD CONSTRAINT "c9_aula_quiz_tentativas_recruta_fk" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."c9_aula_quizzes"
    ADD CONSTRAINT "c9_aula_quizzes_aula_fk" FOREIGN KEY ("aula_id") REFERENCES "public"."aulas"("id");



ALTER TABLE ONLY "public"."chat_conversas"
    ADD CONSTRAINT "chat_conversas_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_events"
    ADD CONSTRAINT "chat_events_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON UPDATE RESTRICT ON DELETE SET NULL;



ALTER TABLE ONLY "public"."chat_mensagens"
    ADD CONSTRAINT "chat_mensagens_conversa_id_fkey" FOREIGN KEY ("conversa_id") REFERENCES "public"."chat_conversas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_mensagens"
    ADD CONSTRAINT "chat_mensagens_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_reads"
    ADD CONSTRAINT "chat_reads_conversa_id_fkey" FOREIGN KEY ("conversa_id") REFERENCES "public"."chat_conversas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_reads"
    ADD CONSTRAINT "chat_reads_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_summaries"
    ADD CONSTRAINT "chat_summaries_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."cronograma_semanal"
    ADD CONSTRAINT "cronograma_semanal_ciclo_id_fkey" FOREIGN KEY ("ciclo_id") REFERENCES "public"."ciclos_formativos"("id");



ALTER TABLE ONLY "public"."eventos_ciclos"
    ADD CONSTRAINT "eventos_ciclos_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."eventos_consumidos"
    ADD CONSTRAINT "eventos_consumidos_evento_id_fkey" FOREIGN KEY ("evento_id") REFERENCES "public"."eventos_institucionais"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."eventos_consumidos"
    ADD CONSTRAINT "eventos_consumidos_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."eventos_institucionais"
    ADD CONSTRAINT "eventos_institucionais_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."aulas_concluidas"
    ADD CONSTRAINT "fk_ac_aula" FOREIGN KEY ("aula_id") REFERENCES "public"."aulas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."aulas_concluidas"
    ADD CONSTRAINT "fk_ac_user" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."aulas"
    ADD CONSTRAINT "fk_aula_modulo" FOREIGN KEY ("modulo_id") REFERENCES "public"."modulos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."automacoes_execucoes"
    ADD CONSTRAINT "fk_automacao_evento" FOREIGN KEY ("evento_id") REFERENCES "public"."eventos_institucionais"("id");



ALTER TABLE ONLY "public"."c7_regras_bloqueio_por_ciclo"
    ADD CONSTRAINT "fk_c7_regras_medalha_slug" FOREIGN KEY ("medalha_slug") REFERENCES "public"."medalhas_catalogo"("slug") ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE;



ALTER TABLE ONLY "public"."chat_logs"
    ADD CONSTRAINT "fk_chatlog_evento" FOREIGN KEY ("evento_id") REFERENCES "public"."eventos_institucionais"("id");



ALTER TABLE ONLY "public"."chat_logs"
    ADD CONSTRAINT "fk_chatlog_recruta" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."eventos_institucionais"
    ADD CONSTRAINT "fk_eventos_recruta" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."lesson_media"
    ADD CONSTRAINT "fk_lesson_media_lesson" FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversation_locks"
    ADD CONSTRAINT "fk_lock_recruta" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."medalhas_alteracoes_pendentes"
    ADD CONSTRAINT "fk_medalha_alteracao" FOREIGN KEY ("medalha_id") REFERENCES "public"."medalhas_catalogo"("id");



ALTER TABLE ONLY "public"."medalhas_catalogo_versionamento"
    ADD CONSTRAINT "fk_medalha_versionamento" FOREIGN KEY ("medalha_id") REFERENCES "public"."medalhas_catalogo"("id");



ALTER TABLE ONLY "public"."recruta_licoes"
    ADD CONSTRAINT "fk_recruta_licao_licao" FOREIGN KEY ("licao_id") REFERENCES "public"."licoes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_licoes"
    ADD CONSTRAINT "fk_recruta_licao_recruta" FOREIGN KEY ("recruta_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."iea_marcos_emitidos"
    ADD CONSTRAINT "iea_marcos_emitidos_ciclo_id_fkey" FOREIGN KEY ("ciclo_id") REFERENCES "public"."ciclos_formativos"("id");



ALTER TABLE ONLY "public"."iea_marcos_emitidos"
    ADD CONSTRAINT "iea_marcos_emitidos_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."iea_marcos_emitidos"
    ADD CONSTRAINT "iea_marcos_emitidos_snapshot_id_fkey" FOREIGN KEY ("snapshot_id") REFERENCES "public"."iea_snapshots"("id");



ALTER TABLE ONLY "public"."iea_snapshots"
    ADD CONSTRAINT "iea_snapshots_ciclo_id_fkey" FOREIGN KEY ("ciclo_id") REFERENCES "public"."ciclos_formativos"("id");



ALTER TABLE ONLY "public"."iea_snapshots"
    ADD CONSTRAINT "iea_snapshots_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."institutional_notice_reads"
    ADD CONSTRAINT "institutional_notice_reads_notice_id_fkey" FOREIGN KEY ("notice_id") REFERENCES "public"."institutional_notices"("id");



ALTER TABLE ONLY "public"."institutional_notice_reads"
    ADD CONSTRAINT "institutional_notice_reads_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."instructor_message_reads"
    ADD CONSTRAINT "instructor_message_reads_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."instructor_messages"("id");



ALTER TABLE ONLY "public"."instructor_message_reads"
    ADD CONSTRAINT "instructor_message_reads_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."instructor_messages"
    ADD CONSTRAINT "instructor_messages_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."instrutor_threads"
    ADD CONSTRAINT "instrutor_threads_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lesson_progress"
    ADD CONSTRAINT "lesson_progress_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lesson_progress"
    ADD CONSTRAINT "lesson_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."licoes"
    ADD CONSTRAINT "licoes_modulo_id_fkey" FOREIGN KEY ("modulo_id") REFERENCES "public"."modulos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."log_emissao_eventos"
    ADD CONSTRAINT "log_emissao_eventos_evento_id_fkey" FOREIGN KEY ("evento_id") REFERENCES "public"."eventos_institucionais"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medalha_regras"
    ADD CONSTRAINT "medalha_regras_medalha_id_fkey" FOREIGN KEY ("medalha_id") REFERENCES "public"."medalhas_catalogo"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medalhas_concedidas"
    ADD CONSTRAINT "medalhas_concedidas_medalha_id_fkey" FOREIGN KEY ("medalha_id") REFERENCES "public"."medalhas_catalogo"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medalhas_concedidas"
    ADD CONSTRAINT "medalhas_concedidas_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."medalhas_concessao_log"
    ADD CONSTRAINT "medalhas_concessao_log_medalha_fk" FOREIGN KEY ("medalha_id") REFERENCES "public"."medalhas_catalogo"("id");



ALTER TABLE ONLY "public"."medalhas_concessao_log"
    ADD CONSTRAINT "medalhas_concessao_log_recruta_fk" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."medalhas_obrigatorias_map"
    ADD CONSTRAINT "medalhas_obrigatorias_map_medalha_slug_fkey" FOREIGN KEY ("medalha_slug") REFERENCES "public"."medalhas_catalogo"("slug") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."medalhas_slug_aliases"
    ADD CONSTRAINT "medalhas_slug_aliases_slug_canonico_fkey" FOREIGN KEY ("slug_canonico") REFERENCES "public"."medalhas_catalogo"("slug") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."mensagens_chat"
    ADD CONSTRAINT "mensagens_chat_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."usuarios"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."missoes"
    ADD CONSTRAINT "missoes_modulo_id_fkey" FOREIGN KEY ("modulo_id") REFERENCES "public"."modulos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."os_task_logs"
    ADD CONSTRAINT "os_task_logs_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "public"."os_tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."patente_regras"
    ADD CONSTRAINT "patente_regras_patente_id_fkey" FOREIGN KEY ("patente_id") REFERENCES "public"."patentes_catalogo"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."premiacoes"
    ADD CONSTRAINT "premiacoes_periodo_id_fkey" FOREIGN KEY ("periodo_id") REFERENCES "public"."ranking_periodos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."premiacoes"
    ADD CONSTRAINT "premiacoes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_auth_fk" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."progresso_aulas"
    ADD CONSTRAINT "progresso_aulas_aula_id_fkey" FOREIGN KEY ("aula_id") REFERENCES "public"."aulas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."progresso_aulas"
    ADD CONSTRAINT "progresso_aulas_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."progresso_missoes"
    ADD CONSTRAINT "progresso_missoes_missao_id_fkey" FOREIGN KEY ("missao_id") REFERENCES "public"."missoes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."progresso_missoes"
    ADD CONSTRAINT "progresso_missoes_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."progresso_recruta"
    ADD CONSTRAINT "progresso_recruta_licao_id_fkey" FOREIGN KEY ("licao_id") REFERENCES "public"."licoes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."progresso_recruta"
    ADD CONSTRAINT "progresso_recruta_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ranking_resultados"
    ADD CONSTRAINT "ranking_resultados_periodo_id_fkey" FOREIGN KEY ("periodo_id") REFERENCES "public"."ranking_periodos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ranking_resultados"
    ADD CONSTRAINT "ranking_resultados_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_ciclo_status"
    ADD CONSTRAINT "recruta_ciclo_status_ciclo_id_fkey" FOREIGN KEY ("ciclo_id") REFERENCES "public"."ciclos_formativos"("id");



ALTER TABLE ONLY "public"."recruta_ciclo_status"
    ADD CONSTRAINT "recruta_ciclo_status_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id");



ALTER TABLE ONLY "public"."recruta_desempenho_revisoes"
    ADD CONSTRAINT "recruta_desempenho_revisoes_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_medalhas_eventos"
    ADD CONSTRAINT "recruta_medalhas_eventos_medalha_evento_id_fkey" FOREIGN KEY ("medalha_evento_id") REFERENCES "public"."medalhas_eventos"("id");



ALTER TABLE ONLY "public"."recruta_medalhas_eventos"
    ADD CONSTRAINT "recruta_medalhas_eventos_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_padrao_galeria"
    ADD CONSTRAINT "recruta_padrao_galeria_periodo_id_fkey" FOREIGN KEY ("periodo_id") REFERENCES "public"."ranking_periodos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_padrao_galeria"
    ADD CONSTRAINT "recruta_padrao_galeria_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_patentes"
    ADD CONSTRAINT "recruta_patentes_patente_id_fkey" FOREIGN KEY ("patente_id") REFERENCES "public"."patentes_catalogo"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_patentes"
    ADD CONSTRAINT "recruta_patentes_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_progresso"
    ADD CONSTRAINT "recruta_progresso_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "public"."aulas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_progresso"
    ADD CONSTRAINT "recruta_progresso_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_progressos_modulos"
    ADD CONSTRAINT "recruta_progressos_modulos_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recruta_status"
    ADD CONSTRAINT "recruta_status_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recrutas"
    ADD CONSTRAINT "recrutas_auth_id_fkey" FOREIGN KEY ("auth_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."revisoes"
    ADD CONSTRAINT "revisoes_missao_id_fkey" FOREIGN KEY ("missao_id") REFERENCES "public"."missoes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."revisoes"
    ADD CONSTRAINT "revisoes_recruta_id_fkey" FOREIGN KEY ("recruta_id") REFERENCES "public"."recrutas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."usage_stats"
    ADD CONSTRAINT "usage_stats_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."user_xp"
    ADD CONSTRAINT "user_xp_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."xp_events"
    ADD CONSTRAINT "xp_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "storage"."s3_multipart_uploads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets_vectors"("id");



ALTER TABLE "auth"."audit_log_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."flow_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."identities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."instances" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_amr_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_challenges" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_factors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."one_time_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."refresh_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_relay_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."schema_migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_domains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Leitura publica de forcas" ON "public"."forcas" FOR SELECT TO "authenticated" USING (("ativo" = true));



CREATE POLICY "Leitura pública de medalhas" ON "public"."medalhas_catalogo" FOR SELECT USING (true);



CREATE POLICY "Permitir leitura de aulas para usuarios autenticados" ON "public"."aulas" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir leitura de modulos para usuarios autenticados" ON "public"."modulos" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir progresso próprio" ON "public"."progresso_aulas" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Public read medalha regras" ON "public"."medalha_regras" FOR SELECT USING (true);



CREATE POLICY "Public read medalhas" ON "public"."medalhas_catalogo" FOR SELECT USING (true);



CREATE POLICY "Public read patentes" ON "public"."patentes_catalogo" FOR SELECT USING (true);



CREATE POLICY "Public read regras patente" ON "public"."patente_regras" FOR SELECT USING (true);



CREATE POLICY "Read carreira via views" ON "public"."recruta_patentes" FOR SELECT USING (true);



CREATE POLICY "Service Role Full Access" ON "public"."chat_audit_log" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "User can access own threads" ON "public"."chat_threads" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "User can update own instructor" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Usuário cria XP events" ON "public"."xp_events" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Usuário vê seu XP" ON "public"."user_xp" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "admin_full_access" ON "public"."recruta_patentes" USING (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."atividade_academica_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."aula_pipeline_execucoes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."aula_pipeline_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."aulas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."aulas_concluidas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "aulas_concluidas_delete" ON "public"."aulas_concluidas" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "aulas_concluidas_insert" ON "public"."aulas_concluidas" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "aulas_concluidas_select" ON "public"."aulas_concluidas" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "aulas_concluidas_service" ON "public"."aulas_concluidas" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "aulas_concluidas_update" ON "public"."aulas_concluidas" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "aulas_read_authenticated" ON "public"."aulas" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."auth_client_revocations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."auth_client_singleton" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."auth_session_revocations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."auth_session_singleton" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."automacoes_execucoes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "automacoes_execucoes_service_role_insert" ON "public"."automacoes_execucoes" FOR INSERT TO "service_role" WITH CHECK (true);



CREATE POLICY "automacoes_execucoes_service_role_select" ON "public"."automacoes_execucoes" FOR SELECT TO "service_role" USING (true);



CREATE POLICY "automacoes_execucoes_service_role_update" ON "public"."automacoes_execucoes" FOR UPDATE TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."billing_assinaturas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "billing_assinaturas_service_role_all" ON "public"."billing_assinaturas" TO "service_role" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."billing_notificacoes_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "billing_notificacoes_log_service_role_all" ON "public"."billing_notificacoes_log" TO "service_role" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."billing_pagamentos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "billing_pagamentos_service_role_all" ON "public"."billing_pagamentos" TO "service_role" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."billing_reconciliacao" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "billing_reconciliacao_service_role_all" ON "public"."billing_reconciliacao" TO "service_role" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."billing_reconciliation_issues" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "billing_reconciliation_issues_service_role_all" ON "public"."billing_reconciliation_issues" TO "service_role" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."c5_audit_eventos_institucionais" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "c5_audit_no_delete" ON "public"."c5_audit_eventos_institucionais" FOR DELETE TO "authenticated", "anon" USING (false);



CREATE POLICY "c5_audit_no_insert" ON "public"."c5_audit_eventos_institucionais" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c5_audit_no_update" ON "public"."c5_audit_eventos_institucionais" FOR UPDATE TO "authenticated", "anon" USING (false) WITH CHECK (false);



ALTER TABLE "public"."c5_jobs_execucao_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "c5_jobs_execucao_log_service_all" ON "public"."c5_jobs_execucao_log" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "c6_atividade_log_select_self" ON "public"."atividade_academica_log" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "atividade_academica_log"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



CREATE POLICY "c6_atividade_no_delete" ON "public"."atividade_academica_log" FOR DELETE TO "authenticated", "anon" USING (false);



CREATE POLICY "c6_atividade_no_insert" ON "public"."atividade_academica_log" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c6_atividade_no_update" ON "public"."atividade_academica_log" FOR UPDATE TO "authenticated", "anon" USING (false);



CREATE POLICY "c6_atividade_no_write" ON "public"."atividade_academica_log" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c6_atividade_select_self" ON "public"."atividade_academica_log" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "atividade_academica_log"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



CREATE POLICY "c6_ciclos_no_delete" ON "public"."ciclos_formativos" FOR DELETE TO "authenticated", "anon" USING (false);



CREATE POLICY "c6_ciclos_no_insert" ON "public"."ciclos_formativos" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c6_ciclos_no_update" ON "public"."ciclos_formativos" FOR UPDATE TO "authenticated", "anon" USING (false);



CREATE POLICY "c6_ciclos_no_write" ON "public"."ciclos_formativos" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c6_ciclos_select_all" ON "public"."ciclos_formativos" FOR SELECT TO "authenticated", "anon" USING (true);



ALTER TABLE "public"."c6_contract_registry" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "c6_cronograma_no_delete" ON "public"."cronograma_semanal" FOR DELETE TO "authenticated", "anon" USING (false);



CREATE POLICY "c6_cronograma_no_insert" ON "public"."cronograma_semanal" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c6_cronograma_no_update" ON "public"."cronograma_semanal" FOR UPDATE TO "authenticated", "anon" USING (false);



CREATE POLICY "c6_cronograma_no_write" ON "public"."cronograma_semanal" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c6_cronograma_select_all" ON "public"."cronograma_semanal" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "c6_recruta_ciclo_status_select_self" ON "public"."recruta_ciclo_status" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "recruta_ciclo_status"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



CREATE POLICY "c6_status_no_delete" ON "public"."recruta_ciclo_status" FOR DELETE TO "authenticated", "anon" USING (false);



CREATE POLICY "c6_status_no_insert" ON "public"."recruta_ciclo_status" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c6_status_no_update" ON "public"."recruta_ciclo_status" FOR UPDATE TO "authenticated", "anon" USING (false);



CREATE POLICY "c6_status_no_write" ON "public"."recruta_ciclo_status" FOR INSERT TO "authenticated", "anon" WITH CHECK (false);



CREATE POLICY "c6_status_select_self" ON "public"."recruta_ciclo_status" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "recruta_ciclo_status"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



ALTER TABLE "public"."c7_execucao_diaria_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."c9_aula_conteudos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."c9_aula_flashcards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."c9_aula_quiz_alternativas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."c9_aula_quiz_perguntas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."c9_aula_quiz_tentativas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."c9_aula_quizzes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "c9_insert_tentativa_propria" ON "public"."c9_aula_quiz_tentativas" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "c9_aula_quiz_tentativas"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



CREATE POLICY "c9_select_alternativas_ativas" ON "public"."c9_aula_quiz_alternativas" FOR SELECT TO "authenticated" USING ((("ativo" = true) AND ("deleted_at" IS NULL)));



CREATE POLICY "c9_select_conteudos_ativos" ON "public"."c9_aula_conteudos" FOR SELECT TO "authenticated" USING ((("ativo" = true) AND ("deleted_at" IS NULL)));



CREATE POLICY "c9_select_flashcards_ativos" ON "public"."c9_aula_flashcards" FOR SELECT TO "authenticated" USING ((("ativo" = true) AND ("deleted_at" IS NULL)));



CREATE POLICY "c9_select_perguntas_ativas" ON "public"."c9_aula_quiz_perguntas" FOR SELECT TO "authenticated" USING ((("ativo" = true) AND ("deleted_at" IS NULL)));



CREATE POLICY "c9_select_quizzes_ativos" ON "public"."c9_aula_quizzes" FOR SELECT TO "authenticated" USING ((("ativo" = true) AND ("deleted_at" IS NULL)));



CREATE POLICY "c9_select_tentativas_proprias" ON "public"."c9_aula_quiz_tentativas" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "c9_aula_quiz_tentativas"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



ALTER TABLE "public"."chat_audit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_conversas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_conversas_no_direct_delete" ON "public"."chat_conversas" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "chat_conversas_no_direct_insert" ON "public"."chat_conversas" FOR INSERT TO "authenticated" WITH CHECK (false);



CREATE POLICY "chat_conversas_no_direct_update" ON "public"."chat_conversas" FOR UPDATE TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "chat_conversas_select_own" ON "public"."chat_conversas" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "chat_conversas"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



ALTER TABLE "public"."chat_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_events_self_insert" ON "public"."chat_events" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "auth_id"));



CREATE POLICY "chat_events_self_select" ON "public"."chat_events" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "auth_id"));



CREATE POLICY "chat_events_self_update" ON "public"."chat_events" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "auth_id") AND ("status" = 'processing'::"text"))) WITH CHECK (("auth"."uid"() = "auth_id"));



CREATE POLICY "chat_events_service_role_all" ON "public"."chat_events" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."chat_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_logs_service_role_insert" ON "public"."chat_logs" FOR INSERT TO "service_role" WITH CHECK (true);



CREATE POLICY "chat_logs_service_role_select" ON "public"."chat_logs" FOR SELECT TO "service_role" USING (true);



CREATE POLICY "chat_logs_service_role_update" ON "public"."chat_logs" FOR UPDATE TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."chat_mensagens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_mensagens_no_direct_delete" ON "public"."chat_mensagens" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "chat_mensagens_no_direct_insert" ON "public"."chat_mensagens" FOR INSERT TO "authenticated" WITH CHECK (false);



CREATE POLICY "chat_mensagens_no_direct_update" ON "public"."chat_mensagens" FOR UPDATE TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "chat_mensagens_select_own" ON "public"."chat_mensagens" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."chat_conversas" "c"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "c"."recruta_id")))
  WHERE (("c"."id" = "chat_mensagens"."conversa_id") AND ("r"."auth_id" = "auth"."uid"())))));



ALTER TABLE "public"."chat_reads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_reads_no_direct_delete" ON "public"."chat_reads" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "chat_reads_no_direct_insert" ON "public"."chat_reads" FOR INSERT TO "authenticated" WITH CHECK (false);



CREATE POLICY "chat_reads_no_direct_update" ON "public"."chat_reads" FOR UPDATE TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "chat_reads_select_own" ON "public"."chat_reads" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "chat_reads"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



ALTER TABLE "public"."chat_summaries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_summaries_select_own" ON "public"."chat_summaries" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "chat_summaries"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



CREATE POLICY "chat_summaries_service_role_all" ON "public"."chat_summaries" TO "service_role" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."chat_threads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ciclos_formativos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."conversation_locks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cronograma_semanal" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."eventos_consumidos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "eventos_consumidos_delete" ON "public"."eventos_consumidos" FOR DELETE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "eventos_consumidos_insert" ON "public"."eventos_consumidos" FOR INSERT WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "eventos_consumidos_select" ON "public"."eventos_consumidos" FOR SELECT USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "eventos_consumidos_service" ON "public"."eventos_consumidos" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "eventos_consumidos_update" ON "public"."eventos_consumidos" FOR UPDATE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"())))) WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



ALTER TABLE "public"."eventos_institucionais" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "eventos_institucionais_insert_block" ON "public"."eventos_institucionais" FOR INSERT WITH CHECK (false);



CREATE POLICY "eventos_institucionais_no_delete" ON "public"."eventos_institucionais" FOR DELETE TO "authenticated", "anon" USING (false);



CREATE POLICY "eventos_institucionais_no_update" ON "public"."eventos_institucionais" FOR UPDATE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "eventos_institucionais_select_block" ON "public"."eventos_institucionais" FOR SELECT USING (false);



CREATE POLICY "eventos_institucionais_select_c5_authenticated" ON "public"."eventos_institucionais" FOR SELECT TO "authenticated" USING ((("idempotency_key" IS NOT NULL) AND ("recruta_id" = "public"."c5_recruta_id_for_auth"())));



ALTER TABLE "public"."forcas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."iea_marcos_emitidos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."iea_snapshots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "insert_own_log" ON "public"."logs_acesso" FOR INSERT WITH CHECK (("auth"."uid"() = "recruta_id"));



CREATE POLICY "insert_own_progress" ON "public"."progresso_recruta" FOR INSERT WITH CHECK (("auth"."uid"() = "recruta_id"));



ALTER TABLE "public"."institutional_assets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "institutional_assets_select_active" ON "public"."institutional_assets" FOR SELECT TO "authenticated" USING (("ativo" = true));



ALTER TABLE "public"."institutional_notice_reads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."institutional_notices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."instructor_message_reads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."instructor_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."instrutor_threads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "instrutor_threads_delete" ON "public"."instrutor_threads" FOR DELETE USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "instrutor_threads_insert" ON "public"."instrutor_threads" FOR INSERT WITH CHECK (("recruta_id" = "auth"."uid"()));



CREATE POLICY "instrutor_threads_select" ON "public"."instrutor_threads" FOR SELECT USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "instrutor_threads_service" ON "public"."instrutor_threads" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "instrutor_threads_update" ON "public"."instrutor_threads" FOR UPDATE USING (("recruta_id" = "auth"."uid"())) WITH CHECK (("recruta_id" = "auth"."uid"()));



ALTER TABLE "public"."instrutores" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "instrutores_no_direct_delete" ON "public"."instrutores" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "instrutores_no_direct_insert" ON "public"."instrutores" FOR INSERT TO "authenticated" WITH CHECK (false);



CREATE POLICY "instrutores_no_direct_update" ON "public"."instrutores" FOR UPDATE TO "authenticated" USING (false) WITH CHECK (false);



CREATE POLICY "instrutores_select_authenticated" ON "public"."instrutores" FOR SELECT TO "authenticated" USING (("ativo" = true));



ALTER TABLE "public"."lesson_progress" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lesson_progress_rw" ON "public"."lesson_progress" TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "lesson_progress_self_access" ON "public"."lesson_progress" FOR SELECT USING (("user_id" IN ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



ALTER TABLE "public"."lessons" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lessons_read" ON "public"."lessons" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."licoes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."logs_acesso" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medalha_regras" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "medalha_regras_read_auth" ON "public"."medalha_regras" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "medalha_regras_write_service" ON "public"."medalha_regras" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."medalhas_catalogo" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."medalhas_concedidas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "medalhas_concedidas_insert_block" ON "public"."medalhas_concedidas" FOR INSERT WITH CHECK (false);



CREATE POLICY "medalhas_concedidas_no_delete" ON "public"."medalhas_concedidas" FOR DELETE TO "authenticated", "anon" USING (false);



CREATE POLICY "medalhas_concedidas_no_update" ON "public"."medalhas_concedidas" FOR UPDATE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "medalhas_concedidas_select_block" ON "public"."medalhas_concedidas" FOR SELECT USING (false);



ALTER TABLE "public"."medalhas_concessao_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "medalhas_concessao_log_service_role_all" ON "public"."medalhas_concessao_log" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."medalhas_obrigatorias_map" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "medalhas_obrigatorias_map_read_auth" ON "public"."medalhas_obrigatorias_map" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "medalhas_obrigatorias_map_write_service" ON "public"."medalhas_obrigatorias_map" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."modulos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."os_task_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "os_task_logs_service_all" ON "public"."os_task_logs" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."os_tasks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "os_tasks_service_all" ON "public"."os_tasks" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "p_auth_client_revocations_read" ON "public"."auth_client_revocations" FOR SELECT TO "authenticated" USING (("auth_id" = "auth"."uid"()));



CREATE POLICY "p_auth_client_singleton_read" ON "public"."auth_client_singleton" FOR SELECT TO "authenticated" USING (("auth_id" = "auth"."uid"()));



CREATE POLICY "p_auth_session_revocations_read" ON "public"."auth_session_revocations" FOR SELECT TO "authenticated" USING (("auth_id" = "auth"."uid"()));



CREATE POLICY "p_auth_session_singleton_read" ON "public"."auth_session_singleton" FOR SELECT TO "authenticated" USING (("auth_id" = "auth"."uid"()));



ALTER TABLE "public"."patente_regras" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."patentes_catalogo" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_own" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "profiles_update_own" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



ALTER TABLE "public"."progresso_aulas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."progresso_missoes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "progresso_missoes_delete" ON "public"."progresso_missoes" FOR DELETE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "progresso_missoes_insert" ON "public"."progresso_missoes" FOR INSERT WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "progresso_missoes_select" ON "public"."progresso_missoes" FOR SELECT USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "progresso_missoes_service" ON "public"."progresso_missoes" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "progresso_missoes_update" ON "public"."progresso_missoes" FOR UPDATE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"())))) WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



ALTER TABLE "public"."progresso_recruta" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "progresso_recruta_delete" ON "public"."progresso_recruta" FOR DELETE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "progresso_recruta_insert" ON "public"."progresso_recruta" FOR INSERT WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "progresso_recruta_select" ON "public"."progresso_recruta" FOR SELECT USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "progresso_recruta_service" ON "public"."progresso_recruta" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "progresso_recruta_update" ON "public"."progresso_recruta" FOR UPDATE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"())))) WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



ALTER TABLE "public"."qd_migration_rdm_lessons_20260503" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."recruta_ciclo_status" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."recruta_desempenho_revisoes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recruta_desempenho_revisoes_delete" ON "public"."recruta_desempenho_revisoes" FOR DELETE USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_desempenho_revisoes_insert" ON "public"."recruta_desempenho_revisoes" FOR INSERT WITH CHECK (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_desempenho_revisoes_select" ON "public"."recruta_desempenho_revisoes" FOR SELECT USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_desempenho_revisoes_service" ON "public"."recruta_desempenho_revisoes" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "recruta_desempenho_revisoes_update" ON "public"."recruta_desempenho_revisoes" FOR UPDATE USING (("recruta_id" = "auth"."uid"())) WITH CHECK (("recruta_id" = "auth"."uid"()));



ALTER TABLE "public"."recruta_licoes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recruta_licoes_delete" ON "public"."recruta_licoes" FOR DELETE USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_licoes_insert" ON "public"."recruta_licoes" FOR INSERT WITH CHECK (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_licoes_select" ON "public"."recruta_licoes" FOR SELECT USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_licoes_service" ON "public"."recruta_licoes" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "recruta_licoes_update" ON "public"."recruta_licoes" FOR UPDATE USING (("recruta_id" = "auth"."uid"())) WITH CHECK (("recruta_id" = "auth"."uid"()));



ALTER TABLE "public"."recruta_medalhas_eventos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recruta_medalhas_eventos_delete" ON "public"."recruta_medalhas_eventos" FOR DELETE USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_medalhas_eventos_insert" ON "public"."recruta_medalhas_eventos" FOR INSERT WITH CHECK (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_medalhas_eventos_select" ON "public"."recruta_medalhas_eventos" FOR SELECT USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_medalhas_eventos_service" ON "public"."recruta_medalhas_eventos" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "recruta_medalhas_eventos_update" ON "public"."recruta_medalhas_eventos" FOR UPDATE USING (("recruta_id" = "auth"."uid"())) WITH CHECK (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_own_data" ON "public"."recruta_patentes" FOR SELECT USING (("recruta_id" = "auth"."uid"()));



ALTER TABLE "public"."recruta_padrao_galeria" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."recruta_patentes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recruta_patentes_delete" ON "public"."recruta_patentes" FOR DELETE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "recruta_patentes_insert" ON "public"."recruta_patentes" FOR INSERT WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "recruta_patentes_select" ON "public"."recruta_patentes" FOR SELECT USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "recruta_patentes_self_access" ON "public"."recruta_patentes" FOR SELECT USING (("recruta_id" IN ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "recruta_patentes_service" ON "public"."recruta_patentes" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "recruta_patentes_update" ON "public"."recruta_patentes" FOR UPDATE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"())))) WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



ALTER TABLE "public"."recruta_progresso" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recruta_progresso_delete" ON "public"."recruta_progresso" FOR DELETE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "recruta_progresso_insert" ON "public"."recruta_progresso" FOR INSERT WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "recruta_progresso_select" ON "public"."recruta_progresso" FOR SELECT USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



CREATE POLICY "recruta_progresso_service" ON "public"."recruta_progresso" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "recruta_progresso_update" ON "public"."recruta_progresso" FOR UPDATE USING (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"())))) WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
   FROM "public"."recrutas"
  WHERE ("recrutas"."auth_id" = "auth"."uid"()))));



ALTER TABLE "public"."recruta_progressos_modulos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recruta_progressos_modulos_delete" ON "public"."recruta_progressos_modulos" FOR DELETE USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_progressos_modulos_insert" ON "public"."recruta_progressos_modulos" FOR INSERT WITH CHECK (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_progressos_modulos_select" ON "public"."recruta_progressos_modulos" FOR SELECT USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_progressos_modulos_service" ON "public"."recruta_progressos_modulos" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "recruta_progressos_modulos_update" ON "public"."recruta_progressos_modulos" FOR UPDATE USING (("recruta_id" = "auth"."uid"())) WITH CHECK (("recruta_id" = "auth"."uid"()));



ALTER TABLE "public"."recruta_status" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recruta_status_delete" ON "public"."recruta_status" FOR DELETE USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_status_insert" ON "public"."recruta_status" FOR INSERT WITH CHECK (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_status_select" ON "public"."recruta_status" FOR SELECT USING (("recruta_id" = "auth"."uid"()));



CREATE POLICY "recruta_status_select_authenticated" ON "public"."recruta_status" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "recruta_status"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



COMMENT ON POLICY "recruta_status_select_authenticated" ON "public"."recruta_status" IS 'Hardening (benchmark/observabilidade): permite SELECT do próprio recruta via vínculo recrutas.auth_id = auth.uid(). Não altera policies legadas existentes.';



CREATE POLICY "recruta_status_service" ON "public"."recruta_status" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "recruta_status_update" ON "public"."recruta_status" FOR UPDATE USING (("recruta_id" = "auth"."uid"())) WITH CHECK (("recruta_id" = "auth"."uid"()));



ALTER TABLE "public"."recrutas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recrutas_insert_own" ON "public"."recrutas" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "auth_id"));



CREATE POLICY "recrutas_select_own" ON "public"."recrutas" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "auth_id"));



CREATE POLICY "recrutas_service_role_all" ON "public"."recrutas" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "recrutas_update_own" ON "public"."recrutas" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "auth_id")) WITH CHECK (("auth"."uid"() = "auth_id"));



CREATE POLICY "select_licoes_disponiveis" ON "public"."licoes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."modulos" "m"
     JOIN "public"."recrutas" "r" ON (("r"."id" = "auth"."uid"())))
  WHERE (("m"."id" = "licoes"."modulo_id") AND ("m"."forca" = "r"."forca") AND (("licoes"."premium" = false) OR ("r"."plano" = 'premium'::"text"))))));



CREATE POLICY "select_modulos_by_forca" ON "public"."modulos" FOR SELECT USING ((("forca" = ( SELECT "recrutas"."forca"
   FROM "public"."recrutas"
  WHERE ("recrutas"."id" = "auth"."uid"()))) AND ("ativo" = true)));



CREATE POLICY "select_own_iea_marcos_emitidos" ON "public"."iea_marcos_emitidos" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "iea_marcos_emitidos"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



CREATE POLICY "select_own_iea_snapshots" ON "public"."iea_snapshots" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."recrutas" "r"
  WHERE (("r"."id" = "iea_snapshots"."recruta_id") AND ("r"."auth_id" = "auth"."uid"())))));



CREATE POLICY "select_own_progress" ON "public"."progresso_recruta" FOR SELECT USING (("auth"."uid"() = "recruta_id"));



CREATE POLICY "service_role_all_execucoes" ON "public"."aula_pipeline_execucoes" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "service_role_all_logs" ON "public"."aula_pipeline_logs" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "update_own_progress" ON "public"."progresso_recruta" FOR UPDATE USING (("auth"."uid"() = "recruta_id"));



ALTER TABLE "public"."user_xp" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."xp_eventos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "xp_eventos_insert_block" ON "public"."xp_eventos" FOR INSERT WITH CHECK (false);



CREATE POLICY "xp_eventos_no_delete" ON "public"."xp_eventos" FOR DELETE TO "authenticated", "anon" USING (false);



CREATE POLICY "xp_eventos_no_update" ON "public"."xp_eventos" FOR UPDATE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "xp_eventos_select_block" ON "public"."xp_eventos" FOR SELECT USING (false);



ALTER TABLE "public"."xp_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_vectors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads_parts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."vector_indexes" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "auth" TO "anon";
GRANT USAGE ON SCHEMA "auth" TO "authenticated";
GRANT USAGE ON SCHEMA "auth" TO "service_role";
GRANT ALL ON SCHEMA "auth" TO "supabase_auth_admin";
GRANT ALL ON SCHEMA "auth" TO "dashboard_user";
GRANT USAGE ON SCHEMA "auth" TO "postgres";



REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage" TO "postgres" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA "storage" TO "anon";
GRANT USAGE ON SCHEMA "storage" TO "authenticated";
GRANT USAGE ON SCHEMA "storage" TO "service_role";
GRANT ALL ON SCHEMA "storage" TO "supabase_storage_admin";
GRANT ALL ON SCHEMA "storage" TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."email"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."jwt"() TO "postgres";
GRANT ALL ON FUNCTION "auth"."jwt"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."role"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."uid"() TO "dashboard_user";



REVOKE ALL ON FUNCTION "public"."_dash_columns"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_columns"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_columns"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."_dash_json"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_json"("p_recruta_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_json"("p_recruta_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_dash_json_v2"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_json_v2"("p_recruta_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_json_v2"("p_recruta_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_dash_key_column"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_key_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_key_column"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."_dash_key_column_v2"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_key_column_v2"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_key_column_v2"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."_dash_num"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_num"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_num"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."_dash_num_v2"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_num_v2"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_num_v2"("p_recruta_id" "uuid", "p_keys" "text"[], "p_default" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."_dash_text"("p_recruta_id" "uuid", "p_keys" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_text"("p_recruta_id" "uuid", "p_keys" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_text"("p_recruta_id" "uuid", "p_keys" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."_dash_text_v2"("p_recruta_id" "uuid", "p_keys" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_dash_text_v2"("p_recruta_id" "uuid", "p_keys" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_dash_text_v2"("p_recruta_id" "uuid", "p_keys" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."_emitir_evento_c5_iea_marco"("p_recruta_id" "uuid", "p_ciclo_id" "uuid", "p_snapshot_id" "uuid", "p_marco" integer, "p_iea_score" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_emitir_evento_c5_iea_marco"("p_recruta_id" "uuid", "p_ciclo_id" "uuid", "p_snapshot_id" "uuid", "p_marco" integer, "p_iea_score" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."_is_service_role"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_is_service_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_service_role"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."atribuir_missao_inicial"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."atribuir_missao_inicial"("p_recruta_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."billing_emitir_evento_c5"("p_tipo" "text", "p_payload" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."buscar_revisoes_whatsapp"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."buscar_revisoes_whatsapp"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."c5_auditar_evento_institucional"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."c5_auditar_evento_institucional"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."c5_guard_eventos_institucionais"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."c5_guard_eventos_institucionais"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."c5_normalizar_evento_institucional"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."c5_normalizar_evento_institucional"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."c5_recruta_id_for_auth"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."c5_recruta_id_for_auth"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."c5_recruta_id_for_auth"() TO "service_role";



GRANT ALL ON FUNCTION "public"."c6_get_iea_score"("p_recruta_id" "uuid", "p_ciclo_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."c6_get_simulado_final_score"("p_recruta_id" "uuid", "p_ciclo_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."calc_nivel_por_xp"("p_xp" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."calc_nivel_por_xp"("p_xp" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_lesson"("p_recruta_id" "uuid", "p_lesson_id" "uuid", "p_xp" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_lesson"("p_recruta_id" "uuid", "p_lesson_id" "uuid", "p_xp" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_lenda_viva"("p_recruta" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_lenda_viva"("p_recruta" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_medalha"("p_recruta_id" "uuid", "p_medalha_slug" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_medalha_v2"("p_recruta_id" "uuid", "p_medalha_slug" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_medalha_v2"("p_recruta_id" "uuid", "p_medalha_slug" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_xp_modulo"("p_user_id" "uuid", "p_modulo_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_xp_modulo"("p_user_id" "uuid", "p_modulo_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_xp_revisao_recomendada"("p_user_id" "uuid", "p_revisao_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_xp_revisao_recomendada"("p_user_id" "uuid", "p_revisao_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_xp_revisao_voluntaria"("p_user_id" "uuid", "p_revisao_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_xp_revisao_voluntaria"("p_user_id" "uuid", "p_revisao_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_xp_simulado"("p_user_id" "uuid", "p_simulado_id" "text", "p_percentual_acerto" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_xp_simulado"("p_user_id" "uuid", "p_simulado_id" "text", "p_percentual_acerto" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_xp_streak_5_dias"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_xp_streak_5_dias"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_xp_uso_diario"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_xp_uso_diario"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."conceder_xp_whatsapp"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conceder_xp_whatsapp"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."concluir_missao"("p_recruta_id" "uuid", "p_missao_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."concluir_missao"("p_recruta_id" "uuid", "p_missao_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."concluir_missao_inicial"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."concluir_missao_inicial"("p_recruta_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."concluir_revisao"("p_revisao_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."concluir_revisao"("p_revisao_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."concluir_revisao_com_xp"("p_revisao_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."concluir_revisao_com_xp"("p_revisao_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."consumir_evento_c5"("p_evento_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."consumir_evento_c5"("p_evento_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."definir_campeoes_mes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."definir_campeoes_mes"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo" "text", "p_referencia_id" "uuid", "p_titulo" "text", "p_descricao" "text", "p_prioridade" integer, "p_cycle_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."emitir_evento_c5"("p_recruta_id" "uuid", "p_tipo" "text", "p_referencia_id" "uuid", "p_titulo" "text", "p_descricao" "text", "p_prioridade" integer, "p_cycle_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."emitir_evento_promocao"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."emitir_evento_promocao"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."fechar_ranking_mensal"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fechar_ranking_mensal"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."fn_acquire_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text", "p_ttl_seconds" integer, "p_owner" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_acquire_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text", "p_ttl_seconds" integer, "p_owner" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_acquire_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text", "p_ttl_seconds" integer, "p_owner" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."fn_calcular_custo_modelo_tokens"("p_modelo" "text", "p_tokens_input" integer, "p_tokens_output" integer, "p_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_calcular_custo_modelo_tokens"("p_modelo" "text", "p_tokens_input" integer, "p_tokens_output" integer, "p_at" timestamp with time zone) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."fn_conceder_xp_aula"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_conceder_xp_aula"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."fn_registrar_evento"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_registrar_evento"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_registrar_evento"("p_recruta_id" "uuid", "p_tipo_evento" "text", "p_idempotency_key" "text", "p_correlation_id" "text", "p_origem" "text", "p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."fn_registrar_preco_modelo"("p_modelo" "text", "p_preco_input_token" numeric, "p_preco_output_token" numeric, "p_criado_por" "text", "p_effective_from" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_registrar_preco_modelo"("p_modelo" "text", "p_preco_input_token" numeric, "p_preco_output_token" numeric, "p_criado_por" "text", "p_effective_from" timestamp with time zone) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."fn_release_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fn_release_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_release_conversation_lock"("p_recruta_id" "uuid", "p_correlation_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."garantir_recruta_ciclo_status_me"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."garantir_recruta_ciclo_status_me"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."gerar_revisao_whatsapp"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."gerar_revisao_whatsapp"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."gerar_revisoes_espacadas"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."gerar_revisoes_espacadas"() TO "service_role";



GRANT ALL ON TABLE "public"."lesson_media" TO "service_role";



GRANT ALL ON TABLE "public"."lesson_progress" TO "service_role";



GRANT ALL ON TABLE "public"."v_lesson_review_availability" TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_lesson_review_availability"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_lesson_review_availability"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."liberar_modulos_iniciais"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."liberar_modulos_iniciais"("p_recruta_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."liberar_todos_modulos_apos_7_dias"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."liberar_todos_modulos_apos_7_dias"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."module_progress"("p_recruta_id" "uuid", "p_modulo_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."module_progress"("p_recruta_id" "uuid", "p_modulo_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."os_tasks" TO "service_role";



REVOKE ALL ON FUNCTION "public"."pode_progredir"("p_recruta" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."pode_progredir"("p_recruta" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."promover_recruta"("p_recruta_id" "uuid", "p_patente_codigo" "text", "p_motivo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."promover_recruta"("p_recruta_id" "uuid", "p_patente_codigo" "text", "p_motivo" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."recalcular_iea"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."recalcular_iea"("p_recruta_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."recalcular_iea"("p_recruta_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."recalcular_regularidade"("p_recruta_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."recruta_progresso_geral"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."recruta_progresso_geral"("p_recruta_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."registrar_atividade_academica"("p_recruta_id" "uuid", "p_tipo" "text", "p_ref_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."resolver_slug_medalha"("p_slug" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."resolver_slug_medalha"("p_slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolver_slug_medalha"("p_slug" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rpc_auth_claim_active_client_session"("p_client_instance_id" "text") TO "authenticated";



GRANT ALL ON FUNCTION "public"."rpc_auth_resolve_session_state"("p_client_instance_id" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."rpc_auth_revoke_client_session"("p_client_instance_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_auth_revoke_client_session"("p_client_instance_id" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."rpc_billing_corrigir_divergencias"("p_recruta_id" "uuid", "p_gateway_event_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_billing_corrigir_divergencias"("p_recruta_id" "uuid", "p_gateway_event_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_billing_processar_evento_pagamento"("p_recruta_id" "uuid", "p_gateway_event_id" "text", "p_gateway_nome" "text", "p_gateway_pagamento_id" "text", "p_valor_centavos" bigint, "p_moeda" "text", "p_status_pagamento" "text", "p_plano" "text", "p_periodo_inicio" timestamp with time zone, "p_periodo_fim" timestamp with time zone, "p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_billing_processar_evento_pagamento"("p_recruta_id" "uuid", "p_gateway_event_id" "text", "p_gateway_nome" "text", "p_gateway_pagamento_id" "text", "p_valor_centavos" bigint, "p_moeda" "text", "p_status_pagamento" "text", "p_plano" "text", "p_periodo_inicio" timestamp with time zone, "p_periodo_fim" timestamp with time zone, "p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_billing_reconciliar_pagamentos"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_billing_reconciliar_pagamentos"("p_recruta_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_billing_status_recruta"("p_recruta_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_billing_status_recruta"("p_recruta_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rpc_billing_status_recruta"("p_recruta_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_billing_verificar_idempotencia"("p_gateway_nome" "text", "p_gateway_event_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_billing_verificar_idempotencia"("p_gateway_nome" "text", "p_gateway_event_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_billing_verificar_trial_expirando"("p_dias" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_billing_verificar_trial_expirando"("p_dias" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_c5_atualizar_fatos_analytics"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_c5_atualizar_fatos_analytics"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_c5_detectar_alertas_operacionais"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_c5_detectar_alertas_operacionais"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_c5_refresh_metricas_diarias"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_c5_refresh_metricas_diarias"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."rpc_c5_refresh_metricas_recruta"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_c5_refresh_metricas_recruta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rpc_chat_mark_read"("p_conversa_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."rpc_chat_open_conversation"("p_instrutor_slug" "text") TO "authenticated";



GRANT ALL ON FUNCTION "public"."rpc_chat_send_message"("p_instrutor_slug" "text", "p_client_message_id" "text", "p_user_text" "text", "p_assistant_text" "text", "p_correlation_id" "text", "p_metadata" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."rpc_chat_summary_upsert"("p_recruta_id" "uuid", "p_thread_id" "text", "p_summary" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rpc_chat_summary_upsert"("p_recruta_id" "uuid", "p_thread_id" "text", "p_summary" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rpc_chat_summary_upsert"("p_recruta_id" "uuid", "p_thread_id" "text", "p_summary" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rpc_complete_onboarding"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."rpc_set_instructor_profile"("p_instructor_profile_id" "text") TO "authenticated";



GRANT ALL ON FUNCTION "public"."rpc_set_recruta_forca"("p_forca" "text") TO "authenticated";



GRANT ALL ON FUNCTION "public"."rpc_update_instructor_profile"("p_instructor_profile_id" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_nome_default"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_nome_default"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_updated_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_verificar_honra_maxima"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_verificar_honra_maxima"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_verificar_medalhas_conclusao"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_verificar_medalhas_conclusao"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_verificar_medalhas_desempenho"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_verificar_medalhas_desempenho"() TO "service_role";



GRANT ALL ON FUNCTION "public"."verificar_elegibilidade_grau6"("p_recruta_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."verificar_honra_maxima"("p_recruta" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verificar_honra_maxima"("p_recruta" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."verificar_medalha_dominio"("p_recruta" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verificar_medalha_dominio"("p_recruta" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."verificar_medalha_instrucao_completa"("p_recruta" "uuid", "p_modulo" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verificar_medalha_instrucao_completa"("p_recruta" "uuid", "p_modulo" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."verificar_medalha_missao_cumprida"("p_recruta" "uuid", "p_modulo" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verificar_medalha_missao_cumprida"("p_recruta" "uuid", "p_modulo" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."verificar_medalha_precisao"("p_recruta" "uuid", "p_revisao" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verificar_medalha_precisao"("p_recruta" "uuid", "p_revisao" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."verificar_medalha_revisao_cumprida"("p_recruta" "uuid", "p_modulo" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verificar_medalha_revisao_cumprida"("p_recruta" "uuid", "p_modulo" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."verificar_medalha_sentinela"("p_recruta" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verificar_medalha_sentinela"("p_recruta" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."verificar_medalhas_obrigatorias"("p_recruta_id" "uuid") TO "authenticated";



GRANT SELECT ON TABLE "public"."ciclos_formativos" TO "anon";
GRANT SELECT ON TABLE "public"."ciclos_formativos" TO "authenticated";



GRANT SELECT ON TABLE "public"."iea_snapshots" TO "authenticated";



GRANT ALL ON TABLE "public"."recruta_status" TO "service_role";



GRANT ALL ON TABLE "public"."recrutas" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."recrutas" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_recruta_ciclo_atual" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_iea_atual" TO "authenticated";



GRANT ALL ON TABLE "auth"."audit_log_entries" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."audit_log_entries" TO "postgres";
GRANT SELECT ON TABLE "auth"."audit_log_entries" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "auth"."custom_oauth_providers" TO "postgres";
GRANT ALL ON TABLE "auth"."custom_oauth_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."flow_state" TO "postgres";
GRANT SELECT ON TABLE "auth"."flow_state" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."flow_state" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."identities" TO "postgres";
GRANT SELECT ON TABLE "auth"."identities" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."identities" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."instances" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."instances" TO "postgres";
GRANT SELECT ON TABLE "auth"."instances" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_amr_claims" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_amr_claims" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_amr_claims" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_challenges" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_challenges" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_challenges" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_factors" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_factors" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_factors" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_client_states" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_client_states" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_clients" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_clients" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_consents" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_consents" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."one_time_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."one_time_tokens" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."one_time_tokens" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."refresh_tokens" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."refresh_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."refresh_tokens" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "dashboard_user";
GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "postgres";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_relay_states" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_relay_states" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_relay_states" TO "dashboard_user";



GRANT SELECT ON TABLE "auth"."schema_migrations" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sessions" TO "postgres";
GRANT SELECT ON TABLE "auth"."sessions" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sessions" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_domains" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_domains" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_domains" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_providers" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."users" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."users" TO "postgres";
GRANT SELECT ON TABLE "auth"."users" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "auth"."webauthn_challenges" TO "postgres";
GRANT ALL ON TABLE "auth"."webauthn_challenges" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."webauthn_credentials" TO "postgres";
GRANT ALL ON TABLE "auth"."webauthn_credentials" TO "dashboard_user";



GRANT SELECT ON TABLE "public"."atividade_academica_log" TO "authenticated";



GRANT ALL ON TABLE "public"."aulas" TO "service_role";



GRANT ALL ON TABLE "public"."aulas_concluidas" TO "service_role";



GRANT SELECT ON TABLE "public"."auth_client_revocations" TO "authenticated";



GRANT SELECT ON TABLE "public"."auth_client_singleton" TO "authenticated";



GRANT SELECT ON TABLE "public"."auth_session_revocations" TO "authenticated";



GRANT SELECT ON TABLE "public"."auth_session_singleton" TO "authenticated";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."automacoes_execucoes" TO "service_role";



GRANT SELECT ON TABLE "public"."c5_audit_eventos_institucionais" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."eventos_institucionais" TO "service_role";
GRANT SELECT ON TABLE "public"."eventos_institucionais" TO "authenticated";



GRANT SELECT ON TABLE "public"."c5_eventos_view" TO "service_role";
GRANT SELECT ON TABLE "public"."c5_eventos_view" TO "authenticated";



GRANT SELECT,INSERT ON TABLE "public"."c5_jobs_execucao_log" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_conteudos" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_flashcards" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_quiz_alternativas" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_quiz_perguntas" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_quizzes" TO "service_role";



GRANT ALL ON TABLE "public"."campeoes_mensais" TO "service_role";



GRANT ALL ON TABLE "public"."chat_audit_log" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."chat_events" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."chat_events" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."chat_logs" TO "service_role";



GRANT SELECT ON TABLE "public"."chat_summaries" TO "authenticated";
GRANT SELECT ON TABLE "public"."chat_summaries" TO "service_role";



GRANT ALL ON TABLE "public"."chat_threads" TO "service_role";



GRANT SELECT ON TABLE "public"."cronograma_semanal" TO "anon";
GRANT SELECT ON TABLE "public"."cronograma_semanal" TO "authenticated";



GRANT ALL ON TABLE "public"."eventos_ciclos" TO "service_role";



GRANT ALL ON TABLE "public"."eventos_consumidos" TO "service_role";



GRANT ALL ON TABLE "public"."forcas" TO "service_role";



GRANT SELECT ON TABLE "public"."iea_marcos_emitidos" TO "authenticated";



GRANT SELECT ON TABLE "public"."institutional_assets" TO "authenticated";
GRANT SELECT ON TABLE "public"."institutional_assets" TO "anon";



GRANT ALL ON TABLE "public"."instrutor_threads" TO "service_role";



GRANT SELECT ON TABLE "public"."instrutores" TO "authenticated";
GRANT SELECT ON TABLE "public"."instrutores" TO "anon";



GRANT ALL ON TABLE "public"."lessons" TO "service_role";



GRANT ALL ON TABLE "public"."licoes" TO "service_role";



GRANT ALL ON TABLE "public"."log_emissao_eventos" TO "service_role";



GRANT ALL ON TABLE "public"."logs_acesso" TO "service_role";



GRANT ALL ON TABLE "public"."medalha_regras" TO "service_role";



GRANT ALL ON TABLE "public"."medalhas_catalogo" TO "service_role";



GRANT ALL ON TABLE "public"."medalhas_categorias" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."medalhas_concedidas" TO "service_role";



GRANT ALL ON TABLE "public"."medalhas_eventos" TO "service_role";



GRANT SELECT ON TABLE "public"."medalhas_slug_aliases" TO "anon";
GRANT SELECT ON TABLE "public"."medalhas_slug_aliases" TO "authenticated";
GRANT SELECT ON TABLE "public"."medalhas_slug_aliases" TO "service_role";



GRANT ALL ON TABLE "public"."mensagens_chat" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."missoes" TO "service_role";



GRANT ALL ON TABLE "public"."modulos" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."xp_eventos" TO "service_role";



GRANT ALL ON TABLE "public"."mv_xp_mensal_recruta" TO "service_role";



GRANT ALL ON TABLE "public"."mv_ranking_mensal" TO "service_role";



GRANT ALL ON TABLE "public"."mv_campeao_mensal" TO "service_role";



GRANT ALL ON TABLE "public"."os_task_logs" TO "service_role";



GRANT ALL ON TABLE "public"."patente_regras" TO "service_role";



GRANT ALL ON TABLE "public"."patentes_catalogo" TO "service_role";



GRANT ALL ON TABLE "public"."premiacoes" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."progresso_aulas" TO "service_role";



GRANT ALL ON TABLE "public"."progresso_missoes" TO "service_role";



GRANT ALL ON TABLE "public"."progresso_recruta" TO "service_role";



GRANT ALL ON TABLE "public"."recruta_padrao_galeria" TO "service_role";



GRANT ALL ON TABLE "public"."public_recrutas_padrao" TO "service_role";



GRANT ALL ON TABLE "public"."ranking_periodos" TO "service_role";



GRANT ALL ON TABLE "public"."ranking_resultados" TO "service_role";



GRANT SELECT ON TABLE "public"."recruta_ciclo_status" TO "authenticated";



GRANT ALL ON TABLE "public"."recruta_desempenho_revisoes" TO "service_role";



GRANT ALL ON TABLE "public"."recruta_licoes" TO "service_role";



GRANT ALL ON TABLE "public"."recruta_medalhas_eventos" TO "service_role";



GRANT ALL ON TABLE "public"."recruta_modulos" TO "service_role";



GRANT ALL ON TABLE "public"."recruta_patentes" TO "service_role";



GRANT ALL ON TABLE "public"."recruta_progresso" TO "service_role";



GRANT ALL ON TABLE "public"."recruta_progressos_modulos" TO "service_role";



GRANT ALL ON TABLE "public"."revisoes" TO "service_role";



GRANT ALL ON TABLE "public"."roles" TO "service_role";



GRANT ALL ON SEQUENCE "public"."roles_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."roles_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."roles_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."sessions" TO "service_role";



GRANT ALL ON TABLE "public"."usage_stats" TO "service_role";



GRANT ALL ON SEQUENCE "public"."usage_stats_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."usage_stats_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."usage_stats_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_xp" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."usuarios" TO "service_role";



GRANT SELECT ON TABLE "public"."v_identidade_recruta" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_app_bootstrap_institucional" TO "service_role";
GRANT SELECT ON TABLE "public"."v_app_bootstrap_institucional" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_app_bootstrap_institucional_rcc" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_execucao_diaria_dashboard" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_execucao_diaria_dashboard_expandido" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_assiduidade_ouro_status" TO "authenticated";



GRANT ALL ON TABLE "public"."v_audit_eventos" TO "service_role";



GRANT ALL ON TABLE "public"."v_audit_medalhas" TO "service_role";



GRANT ALL ON TABLE "public"."v_audit_xp" TO "service_role";



GRANT SELECT ON TABLE "public"."v_auth_active_sessions" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_auth_app_config" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_auth_login_methods" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_auth_mfa_status" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_auth_session" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_billing_status_recruta" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_billing_status_recruta" TO "service_role";



GRANT SELECT ON TABLE "public"."v_billing_status_recruta_v2" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_billing_trial_monitoramento" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_billing_trial_monitoramento" TO "service_role";



GRANT SELECT ON TABLE "public"."v_c7_bloqueio_oficial" TO "anon";
GRANT SELECT ON TABLE "public"."v_c7_bloqueio_oficial" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_c7_bloqueio_oficial_admin" TO "service_role";



GRANT SELECT ON TABLE "public"."v_c7_bloqueio_oficial_legado" TO "anon";
GRANT SELECT ON TABLE "public"."v_c7_bloqueio_oficial_legado" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_c9_aula_execucao" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_c9_quiz_execucao" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_c9_quiz_resultado" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_campeoes_mensais_rcc" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_chat_conversas_recruta" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_chat_mensagens_recruta" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_chat_unread_status" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_classificacao_final_ciclo" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_medalhas_obrigatorias_status" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_elegibilidade_elite" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_eventos_pendentes" TO "anon";
GRANT SELECT ON TABLE "public"."v_eventos_pendentes" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_eventos_pendentes" TO "service_role";



GRANT SELECT ON TABLE "public"."v_eventos_pendentes_padronizados" TO "anon";
GRANT SELECT ON TABLE "public"."v_eventos_pendentes_padronizados" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_eventos_pendentes_padronizados" TO "service_role";



GRANT SELECT ON TABLE "public"."v_execucao_diaria_dashboard_c6" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_forcas_theme" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_historico_atividade_recruta_v3" TO "authenticated";



GRANT ALL ON TABLE "public"."v_historico_progresso_recruta" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_historico_progresso_recruta" TO "authenticated";
GRANT ALL ON TABLE "public"."v_historico_progresso_recruta" TO "service_role";



GRANT SELECT ON TABLE "public"."v_identidade_recruta_legacy_20260503" TO "service_role";



GRANT SELECT ON TABLE "public"."v_iea_atual_v2" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_iea_audit" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_iea_eventos_audit" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_institutional_assets" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_institutional_assets" TO "anon";



GRANT SELECT ON TABLE "public"."v_instrutores_app" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_instrutores_app" TO "anon";



GRANT ALL ON TABLE "public"."v_lesson_completeness" TO "service_role";



GRANT ALL ON TABLE "public"."v_lesson_detail_panel" TO "service_role";



GRANT ALL ON TABLE "public"."v_lesson_media_panel" TO "service_role";



GRANT ALL ON TABLE "public"."v_lesson_progress_panel" TO "service_role";
GRANT SELECT ON TABLE "public"."v_lesson_progress_panel" TO "authenticated";



GRANT ALL ON TABLE "public"."v_lesson_review_overdue" TO "service_role";



GRANT ALL ON TABLE "public"."v_lesson_status_by_user" TO "service_role";



GRANT ALL ON TABLE "public"."v_lessons_panel" TO "service_role";
GRANT SELECT ON TABLE "public"."v_lessons_panel" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_medalha_elegibilidade_status" TO "anon";
GRANT SELECT ON TABLE "public"."v_medalha_elegibilidade_status" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_medalha_elegibilidade_status" TO "service_role";



GRANT SELECT ON TABLE "public"."v_medalhas_painel" TO "anon";
GRANT SELECT ON TABLE "public"."v_medalhas_painel" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_medalhas_painel" TO "service_role";



GRANT SELECT ON TABLE "public"."v_medals_status_v3" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_onboarding_pendente_recruta" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_onboarding_pendente_recruta" TO "service_role";



GRANT SELECT ON TABLE "public"."v_onboarding_status" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_posicao_recruta_mes_rcc" TO "authenticated";



GRANT ALL ON TABLE "public"."v_ranking_force" TO "service_role";
GRANT SELECT ON TABLE "public"."v_ranking_force" TO "anon";
GRANT SELECT ON TABLE "public"."v_ranking_force" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_recruta_xp_total" TO "authenticated";



GRANT ALL ON TABLE "public"."v_ranking_global" TO "service_role";
GRANT SELECT ON TABLE "public"."v_ranking_global" TO "anon";
GRANT SELECT ON TABLE "public"."v_ranking_global" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_ranking_mensal_rcc" TO "authenticated";



GRANT SELECT ON TABLE "public"."v_recruta_medalhas" TO "anon";
GRANT SELECT ON TABLE "public"."v_recruta_medalhas" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_recruta_medalhas" TO "service_role";



GRANT SELECT ON TABLE "public"."v_recruta_patente_atual" TO "anon";
GRANT SELECT ON TABLE "public"."v_recruta_patente_atual" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_recruta_patente_atual" TO "service_role";



GRANT SELECT ON TABLE "public"."v_reengajamento_recruta" TO "authenticated";
GRANT SELECT ON TABLE "public"."v_reengajamento_recruta" TO "service_role";



GRANT SELECT ON TABLE "public"."v_regularidade_status_recruta" TO "authenticated";



GRANT ALL ON TABLE "public"."v_review_panel" TO "service_role";



GRANT SELECT ON TABLE "public"."v_semana_atual_recruta" TO "authenticated";



GRANT ALL ON TABLE "public"."vw_xp_mensal_recruta" TO "service_role";



GRANT ALL ON TABLE "public"."vw_ranking_mensal_derivado" TO "service_role";



GRANT ALL ON TABLE "public"."vw_campeao_mensal_oficial" TO "service_role";



GRANT ALL ON TABLE "public"."vw_campeao_mensal_detalhado" TO "service_role";
GRANT SELECT ON TABLE "public"."vw_campeao_mensal_detalhado" TO "anon";
GRANT SELECT ON TABLE "public"."vw_campeao_mensal_detalhado" TO "authenticated";



GRANT ALL ON TABLE "public"."vw_campeao_mensal_aeronautica" TO "service_role";



GRANT ALL ON TABLE "public"."vw_campeao_mensal_exercito" TO "service_role";



GRANT ALL ON TABLE "public"."vw_campeao_mensal_marinha" TO "service_role";



GRANT ALL ON TABLE "public"."vw_campeoes_mensais_derivado" TO "service_role";



GRANT ALL ON TABLE "public"."vw_campeoes_pendentes" TO "service_role";



GRANT ALL ON TABLE "public"."vw_lesson_progress_status" TO "service_role";



GRANT ALL ON TABLE "public"."vw_lessons_with_media" TO "service_role";



GRANT ALL ON TABLE "public"."vw_lesson_media_availability" TO "service_role";



GRANT ALL ON TABLE "public"."vw_lesson_media_for_user" TO "service_role";



GRANT ALL ON TABLE "public"."vw_lesson_media_aeronautica" TO "service_role";



GRANT ALL ON TABLE "public"."vw_lesson_media_exercito" TO "service_role";



GRANT ALL ON TABLE "public"."vw_lesson_media_marinha" TO "service_role";



GRANT ALL ON TABLE "public"."vw_medalhas_obrigatorias" TO "service_role";
GRANT SELECT ON TABLE "public"."vw_medalhas_obrigatorias" TO "authenticated";



GRANT ALL ON TABLE "public"."vw_medalhas_obrigatorias_ativas" TO "service_role";
GRANT SELECT ON TABLE "public"."vw_medalhas_obrigatorias_ativas" TO "authenticated";



GRANT ALL ON TABLE "public"."vw_module_totals" TO "service_role";



GRANT ALL ON TABLE "public"."vw_ranking_mensal" TO "service_role";
GRANT SELECT ON TABLE "public"."vw_ranking_mensal" TO "authenticated";



GRANT ALL ON TABLE "public"."vw_posicao_recruta_mes" TO "service_role";
GRANT SELECT ON TABLE "public"."vw_posicao_recruta_mes" TO "authenticated";



GRANT ALL ON TABLE "public"."vw_ranking_mensal_aeronautica" TO "service_role";



GRANT ALL ON TABLE "public"."vw_ranking_mensal_exercito" TO "service_role";



GRANT ALL ON TABLE "public"."vw_ranking_mensal_marinha" TO "service_role";



GRANT ALL ON TABLE "public"."vw_rdm_lessons" TO "service_role";



GRANT ALL ON TABLE "public"."vw_rdm_aeronautica" TO "service_role";



GRANT ALL ON TABLE "public"."vw_rdm_exercito" TO "service_role";



GRANT ALL ON TABLE "public"."vw_rdm_marinha" TO "service_role";



GRANT ALL ON TABLE "public"."vw_recruta_lesson_status" TO "service_role";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."vw_recruta_module_progress_legacy_20260503" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vw_recruta_module_progress_legacy_20260503" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_recruta_module_progress_legacy_20260503" TO "service_role";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."vw_recruta_module_status" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vw_recruta_module_status" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_recruta_module_status" TO "service_role";



GRANT SELECT ON TABLE "public"."vw_recruta_module_status_rcc" TO "authenticated";



GRANT ALL ON TABLE "public"."vw_status_recruta" TO "service_role";
GRANT SELECT ON TABLE "public"."vw_status_recruta" TO "authenticated";



GRANT ALL ON TABLE "public"."vw_xp_lessons" TO "service_role";



GRANT ALL ON TABLE "public"."vw_xp_reviews" TO "service_role";



GRANT ALL ON TABLE "public"."vw_xp_module" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vw_xp_module" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_xp_module" TO "service_role";



GRANT ALL ON TABLE "public"."xp_events" TO "service_role";



REVOKE ALL ON TABLE "storage"."buckets" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."buckets" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."buckets" TO "anon";
GRANT ALL ON TABLE "storage"."buckets" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."buckets_analytics" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "anon";



GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "service_role";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "authenticated";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "anon";



REVOKE ALL ON TABLE "storage"."objects" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."objects" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."objects" TO "anon";
GRANT ALL ON TABLE "storage"."objects" TO "authenticated";
GRANT ALL ON TABLE "storage"."objects" TO "service_role";
GRANT ALL ON TABLE "storage"."objects" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."s3_multipart_uploads" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads_parts" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "anon";



GRANT SELECT ON TABLE "storage"."vector_indexes" TO "service_role";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "authenticated";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "anon";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "service_role";




