# Baseline Modular — Quartel Digital Supabase

**Gerado em:** 2026-05-16
**Fonte:** `supabase/remote/supabase_remote_schema.sql` (dump real do banco remoto)
**Baseline completo:** `supabase/baseline/00000000000000_remote_baseline.sql`

## Propósito

Este diretório contém o estado real do banco remoto organizado por domínio institucional.
Os arquivos aqui são **somente leitura** — servem para auditoria, planejamento de migrations e documentação.
**Nenhum arquivo aqui deve ser executado diretamente sem revisão e aprovação institucional.**

## Módulos

| Arquivo | Domínio | Objetos Cobertos |
|---------|---------|-----------------|
| `00_extensions_schemas.sql` | Infraestrutura | Schemas, tipos ENUM auth/storage |
| `01_core_tables.sql` | Tabelas Core | recrutas, profiles, modulos, aulas, xp_eventos, forcas |
| `02_auth_identity_onboarding.sql` | Auth/Identidade | auth_client_sessions, v_identidade_recruta, rpc_complete_onboarding, v_onboarding_status |
| `03_chat_rcc_05_wave1.sql` | Chat RCC-0.5 | chat_conversas, chat_mensagens, rpc_chat_*, v_chat_* |
| `04_c5_eventos_medalhas_patentes.sql` | Gamificação C5 | eventos_institucionais, medalhas_*, patentes_*, c5_*, c7_* |
| `05_learning_modules_lessons_progress.sql` | Aprendizagem | recruta_progresso, recruta_modulos, vw_rdm_*, complete_lesson |
| `06_billing.sql` | Billing | billing_assinaturas, billing_pagamentos, v_billing_status_recruta_v2 |
| `07_ranking_iea_elite.sql` | Ranking/IEA/Elite | xp_eventos, mv_ranking_mensal, v_elegibilidade_elite, v_iea_atual_v2 |
| `08_storage_assets.sql` | Storage/Assets | storage.buckets, institutional_assets, instrutores, v_instrutores_app |
| `09_rls_policies_grants.sql` | Segurança | Todas as RLS policies e grants do schema public |
| `10_functions_rpcs.sql` | Funções/RPCs | Todas as funções públicas com metadados de segurança |
| `11_views_contracts.sql` | Views/Contratos | Todas as views canônicas de leitura |
| `12_triggers_indexes_constraints.sql` | Infra | Triggers, índices, constraints PK/FK/UNIQUE |

## Convenções

- `v_*` = views read-only para o frontend (contratos canônicos de leitura)
- `vw_*` = views derivadas (legadas ou especializadas por força)
- `mv_*` = materialized views (requerem REFRESH periódico)
- `rpc_*` = RPCs canônicas do frontend (contratos de escrita)
- `fn_*` = funções internas (chamadas por triggers ou outras funções)
- `_*` = funções de utilidade interna (sem exposição direta)
- `c5_*` / `c7_*` / `c9_*` = domínios técnicos (Eventos C5, Auditoria C7, Didática C9)

## Riscos Conhecidos

Veja:
- `../SECURITY_DEFINER_AUDIT.md` — funções SECURITY DEFINER sem search_path
- `../RLS_POLICY_AUDIT.md` — tabelas sem RLS ou com policies permissivas
- `../DRIFT_REPORT.md` — divergências entre dump remoto, migrations locais e frontend
- `../NEXT_SAFE_MIGRATIONS.md` — plano de remediação prioritizado

## Processo de Atualização

Este baseline reflete o dump de **2026-05-16**. Para atualizar:
1. Gerar novo dump: `supabase db dump --local > supabase/remote/supabase_remote_schema.sql`
   *(ou dump do remoto com credenciais appropriadas)*
2. Verificar drift com `DRIFT_REPORT.md`
3. Criar migration com prefixo timestamp sequencial
4. Nunca usar `db push` em produção sem aprovação institucional
