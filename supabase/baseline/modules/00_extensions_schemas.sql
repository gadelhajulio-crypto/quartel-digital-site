-- =============================================================================
-- MÓDULO 00: Extensions, Schemas e Tipos Base
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql (linhas 1-203)
-- Domínio: Infraestrutura base do banco (schemas, ENUMs, funções auth primitivas)
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

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

-- -----------------------------------------------------------------------------
-- SCHEMAS
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS "auth";
ALTER SCHEMA "auth" OWNER TO "supabase_admin";

CREATE SCHEMA IF NOT EXISTS "public";
ALTER SCHEMA "public" OWNER TO "pg_database_owner";
COMMENT ON SCHEMA "public" IS 'standard public schema';

CREATE SCHEMA IF NOT EXISTS "storage";
ALTER SCHEMA "storage" OWNER TO "supabase_admin";

-- -----------------------------------------------------------------------------
-- TIPOS ENUM — auth
-- -----------------------------------------------------------------------------

CREATE TYPE "auth"."aal_level" AS ENUM ('aal1', 'aal2', 'aal3');
ALTER TYPE "auth"."aal_level" OWNER TO "supabase_auth_admin";

CREATE TYPE "auth"."code_challenge_method" AS ENUM ('s256', 'plain');
ALTER TYPE "auth"."code_challenge_method" OWNER TO "supabase_auth_admin";

CREATE TYPE "auth"."factor_status" AS ENUM ('unverified', 'verified');
ALTER TYPE "auth"."factor_status" OWNER TO "supabase_auth_admin";

CREATE TYPE "auth"."factor_type" AS ENUM ('totp', 'webauthn', 'phone');
ALTER TYPE "auth"."factor_type" OWNER TO "supabase_auth_admin";

CREATE TYPE "auth"."oauth_authorization_status" AS ENUM (
    'pending', 'approved', 'denied', 'expired'
);
ALTER TYPE "auth"."oauth_authorization_status" OWNER TO "supabase_auth_admin";

CREATE TYPE "auth"."oauth_client_type" AS ENUM ('public', 'confidential');
ALTER TYPE "auth"."oauth_client_type" OWNER TO "supabase_auth_admin";

CREATE TYPE "auth"."oauth_registration_type" AS ENUM ('dynamic', 'manual');
ALTER TYPE "auth"."oauth_registration_type" OWNER TO "supabase_auth_admin";

CREATE TYPE "auth"."oauth_response_type" AS ENUM ('code');
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

-- -----------------------------------------------------------------------------
-- TIPOS ENUM — storage
-- -----------------------------------------------------------------------------

CREATE TYPE "storage"."buckettype" AS ENUM ('STANDARD', 'ANALYTICS', 'VECTOR');
ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";

-- -----------------------------------------------------------------------------
-- FUNÇÕES PRIMITIVAS auth (helpers internos do Supabase)
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- GRANTS DE SCHEMA
-- -----------------------------------------------------------------------------

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
