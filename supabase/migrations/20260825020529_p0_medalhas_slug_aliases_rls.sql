-- P0.1 — hardening de RLS para public.medalhas_slug_aliases
--
-- Tabela de referência (mapeamento slug_alias -> slug_canonico de medalhas),
-- sem colunas de identidade de usuário e sem PII. Hoje é lida via GRANT direto
-- (sem RLS), o que o Security Advisor do Supabase sinaliza como "RLS Disabled
-- in Public". Esta migration habilita RLS e formaliza explicitamente o mesmo
-- acesso de leitura que já existia, via policy, sem alterar comportamento
-- observável pelo cliente.

ALTER TABLE public.medalhas_slug_aliases
ENABLE ROW LEVEL SECURITY;

-- Torna explícito o modelo de privilégios dos clientes: somente SELECT.
-- Nenhuma escrita (INSERT/UPDATE/DELETE/TRUNCATE) é concedida a anon/authenticated.
REVOKE ALL ON TABLE public.medalhas_slug_aliases
FROM anon, authenticated;

GRANT SELECT ON TABLE public.medalhas_slug_aliases
TO anon, authenticated;

-- Policy pública de leitura: preserva o comportamento anterior (tabela de
-- catálogo/referência, sem PII), agora com RLS ativo e a regra explícita
-- em vez de depender da ausência de RLS.
CREATE POLICY "medalhas_slug_aliases_public_read"
ON public.medalhas_slug_aliases
FOR SELECT
TO anon, authenticated
USING (true);
