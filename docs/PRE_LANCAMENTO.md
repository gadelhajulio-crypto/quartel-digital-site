# Checklist de Pré-Lançamento — quartel-digital-mobile

> ⚠️ **REVISAR ESTE DOCUMENTO POR COMPLETO ANTES DE QUALQUER LANÇAMENTO OU DIVULGAÇÃO PÚBLICA.**
> Cada item abaixo **não é crítico hoje** (não há usuários reais em produção), mas **passa a ser bloqueador no momento em que o produto for divulgado**. Nenhum deve ir a público sem resolução.
>
> **Regra de manutenção:** todo novo achado com perfil de pré-lançamento deve ser **adicionado aqui**, não deixado solto apenas no `AUDITORIA_INICIAL.md`. O diagnóstico detalhado de cada item permanece no `AUDITORIA_INICIAL.md` (referenciado pelo código A-NN); este documento é o **índice consolidado de go-live**.

Origem dos itens: achados rotulados "pré-lançamento" no `docs/AUDITORIA_INICIAL.md` (revisão em 2026-07-05).

---

## Bloqueadores de pré-lançamento

| Código | Item | Tipo | Status |
|---|---|---|---|
| A-17 | Conteúdo de QA visível em produção | Higiene de dados | ⛔ aberto |
| A-21 | Ranking (MVs) sem REFRESH agendado | Infra | ⛔ aberto |
| A-25 | E-mail padrão do Supabase com rate limit baixo | Infra | ⛔ aberto |

---

### A-17 — Conteúdo de QA visível em produção
**Descrição.** O módulo `[Placeholder] / [QA] Módulo Teste rpc_complete_lesson` (força Marinha, conteúdo de teste) existe em produção e aparece no catálogo para recrutas reais. *(Nota: com o schema de placeholder do A-16, também há módulos/lições/quizzes `is_placeholder=true` de Exército/Aeronáutica — decidir se saem ou ficam no go-live.)*

**Por que é bloqueador.** Sem usuários reais, é inofensivo. No lançamento, um recruta real veria conteúdo de teste/placeholder como se fosse curso real — quebra de confiança e higiene.

**Ação recomendada.** Despublicar/remover do banco (marcar `ativo=false` — `v_modulos_catalogo` filtra por `ativo=true`), OU garantir que o app esconda `is_placeholder=true`. A coluna `is_placeholder` (A-16) permite a query "o que ainda é placeholder"; usá-la para varrer tudo antes do go-live. Não é bug de código — é higiene de dados.

---

### A-21 — Materialized views de ranking sem REFRESH agendado
**Descrição.** `mv_xp_mensal_recruta`, `mv_ranking_mensal` e `mv_campeao_mensal` são materialized views **sem REFRESH agendado** (sem `pg_cron`; nem constam na função de refresh das `mv_c7_*`). XP gravado em `xp_eventos` (lição, e futuramente quiz/simulado) **só aparece no ranking após `REFRESH MATERIALIZED VIEW` manual**.

**Por que é bloqueador.** Sem usuários, ninguém percebe. No lançamento, o primeiro recruta ganha XP e **o ranking não mexe** → parece quebrado/estático.

**Ação recomendada.** Configurar refresh automático — `pg_cron` agendado ou Edge Function agendada chamando `REFRESH MATERIALIZED VIEW CONCURRENTLY` nas três MVs, em cadência definida. Tratar como **tarefa de infra própria** (não de passagem), com diagnóstico antes de escolher a cadência.

---

### A-25 — Serviço de e-mail padrão do Supabase com rate limit baixo
**Descrição.** Confirmado ao vivo em testes: **`email rate limit exceeded`**. O serviço de e-mail padrão do Supabase (signup, confirmação, reset de senha) tem rate limit baixo, adequado só a desenvolvimento.

**Por que é bloqueador.** Em desenvolvimento passa. Sob volume real de signups/confirmações/resets, os e-mails **começam a falhar** — usuários não conseguem confirmar conta nem resetar senha.

**Ação recomendada.** Configurar **SMTP customizado** (ex.: Resend / SendGrid / SES) no projeto Supabase antes da divulgação. Config de infra do projeto, não bug de código.

---

## Ver também (pré-requisitos de lançamento fora do escopo desta auditoria técnica)
- **Disclaimers legais/institucionais** exigidos em toda landing/onboarding público — ver `FABLE5_RECRUTA_PADRAO_MASTER_SPEC.md` Seção 14 (projeto educacional independente; não substitui orientações oficiais; sem promessas de resultado). Não são achados de código, mas são obrigatórios antes de ir a público.
