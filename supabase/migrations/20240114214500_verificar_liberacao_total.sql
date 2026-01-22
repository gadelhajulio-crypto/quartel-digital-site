-- Função para verificar liberação total e inserir módulos
-- Deve ser chamada via Cron ou Edge Function diariamente
create or replace function verificar_liberacao_total()
returns void
language plpgsql
security definer
as $$
begin
  -- Inserir registros na tabela 'recruta_modulos' para usuários que já completaram 7 dias
  -- Lógica: Se o recruta tem > 7 dias, garantimos que ele tenha acesso a módulos específicos (simulado aqui como modulo_id 1, 2, 3)
  
  -- Exemplo: Liberar Módulo 2 (Intermediário) e 3 (Avançado) para quem tem > 7 dias
  -- E que AINDA NÃO tenha esses módulos liberados.

  insert into recruta_modulos (recruta_id, modulo_id, status, data_liberacao)
  select r.id, m.id, 'liberado', now()
  from recrutas r
  cross join modulos m
  where r.created_at < (now() - interval '7 days')
  and m.id in ('modulo_2_id', 'modulo_3_id') -- IDs de exemplo, substituir pelos reais
  and not exists (
    select 1 from recruta_modulos rm 
    where rm.recruta_id = r.id 
    and rm.modulo_id = m.id
  );
  
end;
$$;
