-- ==============================================================================
-- BLINDAGEM DE SEGURANÇA (RLS - ROW LEVEL SECURITY)
-- ==============================================================================
-- Este script habilita a segurança em nível de linha para garantir que apenas
-- usuários autenticados possam ler dados e apenas donos possam editar seus perfis.
-- DATA: 15/01/2026
---------------------------------------------------------------------------------

-- 1. MÓDULOS E AULAS (LEITURA PÚBLICA PARA RECRUTAS)
-- O conteúdo é o mesmo para todos, mas apenas usuários logados podem ver.

ALTER TABLE public.modulos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Módulos visíveis para todos os recrutas" 
ON public.modulos 
FOR SELECT 
USING (auth.role() = 'authenticated');

ALTER TABLE public.aulas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Aulas visíveis para todos os recrutas" 
ON public.aulas 
FOR SELECT 
USING (auth.role() = 'authenticated');

-- 2. RECRUTAS / PERFIL (RANKING E EDICAO)
-- Todos podem ver o ranking (ler dados básicos uns dos outros), 
-- mas apenas o dono pode editar seu próprio perfil.

ALTER TABLE public.recrutas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Recrutas podem ver ranking" 
ON public.recrutas 
FOR SELECT 
USING (auth.role() = 'authenticated');

CREATE POLICY "Recrutas podem editar apenas seu perfil" 
ON public.recrutas 
FOR UPDATE 
USING (auth.uid() = id);

-- 3. XP EVENTOS (HISTÓRICO PESSOAL)
-- Recrutas só veem seu próprio histórico. Ninguém insere direto (apenas via RPC).

ALTER TABLE public.xp_eventos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Recruta vê apenas seus eventos" 
ON public.xp_eventos 
FOR SELECT 
USING (auth.uid() = user_id);

-- (Opcional) Permitir Insert apenas se o user_id for o próprio
-- Embora a gente use RPC (Security Definer), é uma boa prática.
CREATE POLICY "Recruta pode inserir eventos para si mesmo" 
ON public.xp_eventos 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);
