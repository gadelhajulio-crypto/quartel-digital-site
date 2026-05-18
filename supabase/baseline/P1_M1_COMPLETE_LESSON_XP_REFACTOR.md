# P1-M1 Architectural Spec — complete_lesson XP Refactor
**Status:** RASCUNHO — AGUARDANDO APROVACAO INSTITUCIONAL
**Data:** 2026-05-17
**Classificacao:** P1 — Seguranca / Arquitetura
**Sprint alvo:** Sprint 2
**Predecessor:** P0-M6 (auth guard aplicado)
**Decisao apontada em:** PRE_DEPLOY_GATE.md §RR-01 — "Option C (nova RPC sem p_xp)"

---

## Sumario Executivo

Apos P0-M6, o unico risco residual de `complete_lesson` e que `p_xp` ainda e um parametro
externo na assinatura — mesmo que o frontend atual nao o envie (usa DEFAULT 50), a interface
continua permitindo que um caller arbitrario especifique o valor de XP concedido.

Esta especificacao projeta a remocao completa desse risco via criacao de uma nova RPC
`rpc_complete_lesson(p_lesson_id uuid)` que calcula XP exclusivamente a partir de
`aulas.xp_valor` (coluna institucional ja existente no banco).

---

## 1. Auditoria do Estado Atual

### 1.1 Assinatura atual (pos P0-M6)

```sql
public.complete_lesson(
    p_recruta_id uuid,        -- validado contra auth.uid() pela guarda P0-M6
    p_lesson_id  uuid,
    p_xp         integer DEFAULT 50  -- ← RISCO RESIDUAL
)
RETURNS json
SECURITY DEFINER
SET search_path TO 'public'
```

### 1.2 Origem real do XP hoje

**Resposta: p_xp = DEFAULT 50, sempre.**

| Fato | Evidencia |
|------|-----------|
| Frontend NAO envia `p_xp` | `progressService.ts:50` — apenas `p_recruta_id` e `p_lesson_id` |
| Valor efetivo em producao | `50` para todas as conclusoes (DEFAULT) |
| Valor em `aulas.xp_valor` | Ignorado por `complete_lesson` — nao lido pela funcao |
| Valor em `aulas.xp_valor` padrao | `integer DEFAULT 0 NOT NULL` (dump ln 9080) |

**Conclusao:** Hoje todo registro em `xp_eventos` com `origem = 'lesson_complete'` tem
`quantidade = 50` independentemente da aula. XP e uma constante, nao um merito por aula.

### 1.3 A coluna institucional existe e esta populada pelo sistema legado

```sql
-- aulas (dump ln 9075–9084)
CREATE TABLE IF NOT EXISTS "public"."aulas" (
    "id"        "uuid"     DEFAULT gen_random_uuid() NOT NULL,
    "modulo_id" "uuid"     NOT NULL,
    "titulo"    "text"     NOT NULL,
    "ordem"     integer    NOT NULL,
    "xp_valor"  integer    DEFAULT 0 NOT NULL,  -- ← FONTE INSTITUCIONAL
    "video_url" "text",
    "pdf_url"   "text"
);
```

**Evidencia do padrao arquitetural correto:** O trigger legado `fn_conceder_xp_aula`
(dump ln 2854–2878) ja usa `aulas.xp_valor` exatamente como deve ser feito:

```sql
-- fn_conceder_xp_aula — trigger em aulas_concluidas (sistema legado)
SELECT xp_valor INTO v_xp FROM aulas WHERE id = new.aula_id;
IF v_xp IS NULL OR v_xp <= 0 THEN RETURN new; END IF;
UPDATE profiles SET xp = xp + v_xp WHERE id = new.user_id;
```

O padrao correto — SELECT FROM aulas — ja existe no banco. O problema e que
`complete_lesson` (sistema canonico RCC) nunca foi atualizada para usa-lo.

### 1.4 Cadeias de XP Total (o que o refactor afeta downstream)

```
aulas.xp_valor
  └─ complete_lesson (RPC)
       └─ INSERT INTO xp_eventos (quantidade = ?)
            └─ v_recruta_xp_total  (SUM(quantidade) GROUP BY recruta_id)
                 ├─ v_ranking_mensal_rcc
                 ├─ v_posicao_recruta_mes_rcc
                 ├─ v_campeoes_mensais_rcc
                 ├─ mv_xp_mensal_recruta (MATERIALIZED)
                 └─ mv_ranking_mensal    (MATERIALIZED)
```

**Conclusao:** Corrigir `complete_lesson` para usar `aulas.xp_valor` afeta
automaticamente ranking, historico e todas as views derivadas de `xp_eventos`.
Isso e exatamente o comportamento desejado — o XP vai refletir o merito real por aula.

### 1.5 Callers do complete_lesson em producao

| Local | Arquivo | Parametros enviados | Resultado de retorno usado? |
|-------|---------|---------------------|-----------------------------|
| progressService | `src/services/progressService.ts:50` | `{ p_recruta_id, p_lesson_id }` — SEM p_xp | NÃO — sem tratamento de retorno |
| LessonScreen | `app/(stack)/lesson/[id].tsx:101` | via `completeLesson(id, userId)` | Apenas erro/sucesso — router.back() |
| Edge Functions | `supabase/functions/` | 0 callers encontrados | N/A |
| Migrations de producao | | 0 callers encontrados | N/A |

**Total de callers em producao: 1 unico caminho** (LessonScreen → progressService).

---

## 2. Analise de Opcoes

### Opcao A — Remover p_xp da assinatura de complete_lesson

```sql
-- Nova assinatura (breaking change de PostgreSQL — exige DROP + CREATE)
complete_lesson(p_recruta_id uuid, p_lesson_id uuid)
-- Internamente: SELECT xp_valor FROM aulas WHERE id = p_lesson_id
```

| Dimensao | Avaliacao |
|----------|-----------|
| Breaking change no banco | **SIM** — `CREATE OR REPLACE` nao pode mudar assinatura. Requer DROP + CREATE |
| Breaking change no frontend | **SIM** — PostgREST resolve funcoes por nome+assinatura. DROP da funcao com 3 params + CREATE com 2 params: qualquer caller com 3 params explora "function not found" |
| Frontend atual | Funciona (nao envia p_xp) mas requer teste cuidadoso |
| Risco de rollback | **ALTO** — rollback exige DROP da nova + recriar antiga |
| Compatibilidade com service_role | OK se service_role nao envia p_xp |
| Janela de manutenção | Necessaria para deploy atomico |

**Veredicto:** Viavel, mas requer coordenacao de deploy e cria janela de risco.
Nao recomendada como primeira acao.

---

### Opcao B — Manter assinatura, ignorar p_xp, calcular internamente

```sql
-- Mesma assinatura (CREATE OR REPLACE — zero downtime)
complete_lesson(p_recruta_id uuid, p_lesson_id uuid, p_xp integer DEFAULT 50)
-- Internamente: IGNORA p_xp; lê aulas.xp_valor
```

| Dimensao | Avaliacao |
|----------|-----------|
| Breaking change no banco | **NAO** — CREATE OR REPLACE com mesma assinatura |
| Breaking change no frontend | **NAO** — parametros identicos |
| p_xp no corpo | Parametro morto — recebido mas ignorado |
| Risco | **BAIXO** — menos de 5 linhas mudadas no corpo |
| Concessao de XP | Passa a refletir aulas.xp_valor imediatamente |
| Rollback | Trivial — CREATE OR REPLACE com corpo anterior |
| Desvantagem | Parametro `p_xp` permanece na interface criando confusao |

**Veredicto:** Caminho mais seguro e imediato. Corrige o vetor de XP mas nao limpa
a interface. Adequado como **passo intermediario** antes de Option C.

---

### Opcao C — Nova RPC rpc_complete_lesson(p_lesson_id uuid) ← RECOMENDADA

```sql
-- Nova funcao com interface limpa
rpc_complete_lesson(p_lesson_id uuid)
-- Usa auth.uid() internamente — sem p_recruta_id
-- Lê aulas.xp_valor — sem p_xp
-- GRANT EXECUTE TO authenticated
-- Coexiste com complete_lesson durante transição
```

| Dimensao | Avaliacao |
|----------|-----------|
| Breaking change no banco | **NAO** — CREATE nova funcao, nao altera a existente |
| Breaking change no frontend | **SIM** — mudanca em progressService.ts (1 linha) |
| Risco de downtime | **ZERO** — ambas as funcoes coexistem durante rollout |
| Rollback | **TRIVIAL** — reverter progressService.ts para complete_lesson |
| Interface | Limpa: sem p_recruta_id, sem p_xp |
| Seguranca | Maxima: auth.uid() e unica fonte do recruta, xp_valor e unica fonte de XP |
| Alinhamento com convencao | Segue prefixo `rpc_` das outras RPCs canonicas |
| Deprecacao gradual | complete_lesson pode ser removida em Sprint 3 |

**Veredicto: RECOMENDADA para Sprint 2.**
Confirmado por PRE_DEPLOY_GATE.md §RR-01: "Option C (nova RPC sem p_xp)".

---

### Opcao D — Tabela de regras de XP (xp_config)

```sql
-- Nova tabela configuravel
xp_config(objeto_tipo text, objeto_id uuid, xp_base integer, multiplicador numeric, ativo boolean)
-- complete_lesson ou rpc_complete_lesson leria xp_config para calcular XP
```

| Dimensao | Avaliacao |
|----------|-----------|
| Flexibilidade | **ALTA** — permite XP por tipo de aula, booster, etc. |
| Complexidade | **ALTA** — nova tabela, nova logica, possivel conflito com aulas.xp_valor |
| Necessidade atual | **BAIXA** — aulas.xp_valor ja existe e ja modela XP por aula |
| Quando considerar | Sprint 3+ se houver necessidade de boosters ou XP dinâmico |

**Veredicto:** Nao necessaria agora. `aulas.xp_valor` ja e a "tabela de config" institucional
de XP por aula. Option D seria sobrearquitetura para o problema atual.

---

## 3. Arquitetura Selecionada — Opcao C

### 3.1 Especificacao tecnica da nova funcao

```sql
-- Nome convencional: rpc_ prefix + descricao sem parametros externos expostos
-- Assinatura minima: apenas o necessario para o contrato
public.rpc_complete_lesson(p_lesson_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
```

**Logica interna (pseudocodigo — NAO executar):**

```
1. GUARDA de autenticacao:
   IF auth.uid() IS NULL THEN
       RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501'
   END IF;
   -- (diferente de complete_lesson que permite service_role via IS NOT NULL check)
   -- Para rpc_complete_lesson: authenticated OBRIGATORIO

2. Derivar recruta_id:
   v_recruta_id := auth.uid();

3. Ler XP institucional da aula:
   SELECT xp_valor INTO v_xp_valor
   FROM aulas
   WHERE id = p_lesson_id;
   -- Se aula nao encontrada: RAISE EXCEPTION 'lesson not found' (ERRCODE '22023')
   -- Se xp_valor = 0: conceder 0 XP (valido — aula informacional pode ter xp=0)

4. Verificar idempotencia (mesma logica de complete_lesson):
   SELECT EXISTS(...recruta_progresso WHERE recruta_id = v_recruta_id AND lesson_id = p_lesson_id)
   INTO v_ja_concluida;
   IF v_ja_concluida THEN RETURN json_build_object('status','ok','xp_granted',false,...); END IF;

5. Registrar conclusao:
   INSERT INTO recruta_progresso (recruta_id, lesson_id, status, completed_at, xp_granted, source)
   VALUES (v_recruta_id, p_lesson_id, 'completed', now(), v_xp_valor, 'rpc_complete_lesson')
   ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

6. Conceder XP:
   INSERT INTO xp_eventos (recruta_id, forca, quantidade, origem, referencia_id)
   SELECT r.id, r.forca, v_xp_valor, 'lesson_complete', p_lesson_id
   FROM recrutas r WHERE r.id = v_recruta_id
   ON CONFLICT DO NOTHING;  -- protegido por ux_xp_eventos_lesson_unique

7. RETURN json_build_object(
       'status', 'ok',
       'xp_granted', true,
       'xp_added', v_xp_valor
   );
```

**Grants necessarios:**

```sql
REVOKE ALL ON FUNCTION public.rpc_complete_lesson(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_complete_lesson(uuid) TO authenticated;
-- service_role: acesso via owner (postgres) ou GRANT ALL adicional se necessario
```

### 3.2 Mudancas de comportamento em relacao a complete_lesson

| Aspecto | complete_lesson (P0-M6) | rpc_complete_lesson (P1-M1) |
|---------|------------------------|------------------------------|
| Assinatura | `(recruta_id, lesson_id, xp=50)` | `(lesson_id)` |
| Fonte do recruta | Parametro externo + auth guard | `auth.uid()` direto |
| Fonte do XP | Parametro externo DEFAULT 50 | `aulas.xp_valor` (institucional) |
| service_role sem JWT | Permitido (guarda IS NOT NULL) | **Bloqueado** — requer auth.uid() |
| service_role com JWT | Permitido | Permitido |
| Callers frontend | 1 (progressService) | 1 (progressService apos migracao) |
| Campo `source` em recruta_progresso | `'lesson_complete'` | `'rpc_complete_lesson'` |

**Nota sobre service_role:** `rpc_complete_lesson` bloqueia chamadas sem JWT porque usa
`auth.uid()` como unica fonte de recruta. Se Edge Functions ou seeds precisarem completar
aulas programaticamente, devem continuar usando `complete_lesson` (com auth guard) ate que
uma variante `rpc_complete_lesson_admin(p_recruta_id, p_lesson_id)` seja criada (Sprint 3+).

### 3.3 Idempotencia preservada

A idempotencia e preservada pelos mesmos mecanismos de `complete_lesson`:

| Mecanismo | Tabela | Constraint |
|-----------|--------|------------|
| ON CONFLICT DO NOTHING | `recruta_progresso` | UNIQUE (recruta_id, lesson_id) |
| ON CONFLICT DO NOTHING | `xp_eventos` | UNIQUE INDEX `ux_xp_eventos_lesson_unique` ON (recruta_id, referencia_id) WHERE origem = 'lesson_complete' |

Segunda chamada com mesmo `(auth.uid(), p_lesson_id)` retorna `{"xp_granted":false}` sem duplicar dados.

---

## 4. Impacto Downstream

### 4.1 Ranking (impacto: POSITIVO)

Apos P1-M1, as aulas com `xp_valor > 50` passam a gerar mais XP no ranking.
Aulas com `xp_valor < 50` geram menos. O ranking passa a refletir merito diferenciado por aula.

| View | Impacto |
|------|---------|
| `v_recruta_xp_total` | Automatico — SUM(quantidade) FROM xp_eventos |
| `v_ranking_mensal_rcc` | Automatico — derivado de v_recruta_xp_total |
| `mv_xp_mensal_recruta` | Requer REFRESH apos apply (vide RR-05 — Sprint 2) |
| `mv_ranking_mensal` | Requer REFRESH apos apply |

**Alerta:** Se `aulas.xp_valor = 0` para todas as aulas (nao populado), todos os novos
registros em `xp_eventos` terao `quantidade = 0` e o ranking congelara.
**Pre-condicao obrigatoria:** Verificar que `aulas.xp_valor > 0` para as aulas ativas.

### 4.2 Historico (impacto: NEUTRO)

`v_historico_atividade_recruta_v3` e `v_historico_progresso_recruta` nao consomem
`xp_eventos.quantidade` diretamente — exibem eventos, nao valores numericos de XP.
Nenhuma mudanca de comportamento nas telas de historico.

### 4.3 Medalhas (impacto: NEUTRO a POSITIVO)

Medalhas baseadas em numero de aulas concluidas: sem impacto.
Medalhas baseadas em XP acumulado: podem ser atingidas mais rapido ou mais devagar
dependendo da distribuicao de `xp_valor` nas aulas. Comportamento correto por design.

### 4.4 recruta_progresso.xp_granted (impacto: MUDANCA)

O campo `xp_granted` em `recruta_progresso` passara a ter o valor real de `aulas.xp_valor`
ao inves de 50. Aulas concluidas ANTES da migracao continuam com xp_granted = 50.

Nao ha view ou tela que exibe `recruta_progresso.xp_granted` para o usuario final.
O impacto e somente em auditorias internas de dados.

---

## 5. Verificacoes de Seguranca

### 5.1 Vetores eliminados por P1-M1

| Vetor | Situacao em P0-M6 | Situacao em P1-M1 |
|-------|-------------------|-------------------|
| p_recruta_id forjado | Bloqueado pela guarda auth.uid() | Eliminado — parametro inexistente |
| p_xp arbitrario | **Ainda presente (risco residual RR-01)** | **ELIMINADO** — XP lido de aulas.xp_valor |
| Conclusao de aula com XP = 0 | Possivel via p_xp=0 | Controlado por aulas.xp_valor |
| Conclusao com XP inflado | Possivel via p_xp=99999 | **IMPOSSIVEL** — XP e institucional |

### 5.2 Vetores novos introduzidos por P1-M1

| Vetor | Severidade | Mitigacao |
|-------|-----------|-----------|
| aulas.xp_valor=0 causa XP zero em novas conclusoes | OPERACIONAL | Pre-condicao: auditar aulas.xp_valor antes do apply |
| aulas.xp_valor pode ser alterado por admin malicioso | BAIXO | Requer acesso a service_role ou postgres — controles de acesso existentes |
| rpc_complete_lesson nao funciona para service_role sem JWT | OPERACIONAL | Documentado. complete_lesson permanece disponivel para service_role durante transicao |

### 5.3 Nivel de confiança por parametro

| Funcao | Fonte do recruta | Confianca | Fonte do XP | Confianca |
|--------|------------------|-----------|-------------|-----------|
| `complete_lesson` (pre P0-M6) | Parametro externo | Baixa | Parametro externo DEFAULT 50 | Baixa |
| `complete_lesson` (pos P0-M6) | Parametro validado vs auth.uid() | Media | Parametro externo DEFAULT 50 | **Baixa** |
| `rpc_complete_lesson` (P1-M1) | `auth.uid()` direto | **Alta** | `aulas.xp_valor` | **Alta** |

---

## 6. Analise de aulas.xp_valor — Pre-condicao Critica

### 6.1 Estado esperado dos dados

Antes de ativar `rpc_complete_lesson`, verificar:

```sql
-- Query de verificacao (executar como service_role)
SELECT
    COUNT(*)                                    AS total_aulas,
    COUNT(*) FILTER (WHERE xp_valor = 0)        AS aulas_xp_zero,
    COUNT(*) FILTER (WHERE xp_valor > 0)        AS aulas_com_xp,
    MIN(xp_valor) FILTER (WHERE xp_valor > 0)   AS xp_minimo,
    MAX(xp_valor)                               AS xp_maximo,
    ROUND(AVG(xp_valor) FILTER (WHERE xp_valor > 0), 1) AS xp_medio
FROM public.aulas;
```

**Criterio de aprovacao:** pelo menos 80% das aulas com `xp_valor > 0`.

```sql
-- Listar aulas com xp_valor = 0 (candidatas a atualizacao)
SELECT a.id, a.titulo, a.xp_valor, m.titulo AS modulo
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
WHERE a.xp_valor = 0
ORDER BY m.titulo, a.ordem;
```

### 6.2 Estrategia de fallback

Se `aulas.xp_valor = 0`, `rpc_complete_lesson` deve conceder 0 XP (comportamento explicito).
Nao e recomendado usar COALESCE com um valor padrao pois isso reintroduziria uma constante
hardcoded — exatamente o que estamos removendo.

**Opcao alternativa aprovada institucionalmente:** Criar uma coluna `xp_padrao` em `modulos`
e usar `COALESCE(aulas.xp_valor, modulos.xp_padrao, 0)`. Mas isso e complexidade desnecessaria
se os dados de `xp_valor` estiverem populados.

---

## 7. Contrato de Retorno da Nova Funcao

A nova funcao retorna o mesmo schema JSON que `complete_lesson`:

```json
// Sucesso (primeira conclusao):
{"status": "ok", "xp_granted": true, "xp_added": <valor_de_aulas.xp_valor>}

// Idempotente (ja concluida):
{"status": "ok", "xp_granted": false, "message": "Aula já concluída anteriormente"}

// Erro de autenticacao:
// ERROR 42501 — "authentication required"

// Aula inexistente:
// ERROR 22023 — "lesson not found: <uuid>"
```

**Compatibilidade com frontend:** O frontend atual ignora o valor de retorno (nenhuma
tela exibe `xp_added`). A mudanca no valor de `xp_added` e invisivel para o usuario.

Se no futuro a tela de conclusao de aula exibir "+50 XP", devera ler `xp_added` do retorno —
exatamente o campo correto ja exposto pelo contrato.

---

## 8. Requisitos de Teste Institucional

### 8.1 Testes de seguranca

| Teste | Metodo | Esperado |
|-------|--------|----------|
| Cliente nao pode alterar XP | Verificar que nenhum parametro de XP existe na assinatura publica | Assinatura sem `p_xp` |
| Spoofing de recruta impossivel | Chamar rpc_complete_lesson com outro JWT | 42501 se JWT de outro user |
| XP inflado impossivel | Verificar que `xp_eventos.quantidade` = `aulas.xp_valor` | Igualdade confirmada |
| XP zero para aula xp_valor=0 | Chamar com aula de xp_valor=0 | xp_added=0, mas lesson marcada complete |

### 8.2 Testes de idempotencia

| Teste | Metodo | Esperado |
|-------|--------|----------|
| Segunda chamada nao duplica progresso | Chamar 2x com mesmo lesson_id | 1 linha em recruta_progresso |
| Segunda chamada nao duplica XP | Chamar 2x com mesmo lesson_id | 1 linha em xp_eventos (UNIQUE INDEX) |
| Retorno correto na 2a chamada | Verificar JSON | {"xp_granted":false,"message":"Aula já concluída anteriormente"} |

### 8.3 Testes de consistencia downstream

| Teste | Metodo | Esperado |
|-------|--------|----------|
| v_recruta_xp_total atualizado | SELECT apos conclusao | SUM inclui nova quantidade |
| Ranking reflete novo XP | SELECT v_ranking_mensal_rcc | Posicao correta |
| MVs atualizadas apos REFRESH | REFRESH + SELECT mv_ranking_mensal | Dados corretos |

---

## 9. Questoes Abertas

| ID | Questao | Impacto | Decisao esperada |
|----|---------|---------|-----------------|
| Q-01 | Qual o valor padrao de `xp_valor` para novas aulas? Deve ser 0 ou um valor institucional? | MEDIO — aulas criadas sem XP explicitamente teriam XP=0 | Equipe de produto / admin |
| Q-02 | `rpc_complete_lesson` deve bloquear conclusao se a aula nao pertencer ao modulo do recruta? | BAIXO — nao ha restricao hoje em `complete_lesson` | Institucional |
| Q-03 | Concluir aula com `xp_valor=0` deve retornar sucesso ou erro? | BAIXO — comportamento atual (fn_conceder_xp_aula) e silencioso | Tecnico |
| Q-04 | `rpc_complete_lesson` deve ser registrada em `c6_contract_registry` antes ou apos a migration? | BAIXO — P1-M2 pode registrar | Arquitetura |
| Q-05 | `complete_lesson` deve ser mantida para service_role mesmo apos deprecacao do frontend? | MEDIO — Edge Functions e crons futuros | Roadmap |

---

## 10. Risco Residual Apos P1-M1

| ID | Risco | Severidade | Proxima acao |
|----|-------|-----------|--------------|
| RR-01-RESOLVIDO | p_xp externo | RESOLVIDO | P1-M1 |
| RR-02 | p_lesson_id sem validacao de existencia | BAIXO | P1-M1 pode adicionar validacao |
| RR-03 | ~20 outras funcoes SECURITY DEFINER sem search_path | MEDIO | Sprint 2 — ALTER FUNCTION em lote |
| RR-04 | emitir_evento_c5 exposta a authenticated | MEDIO | Sprint 2 |
| RR-05 | MVs sem REFRESH agendado | OPERACIONAL | Sprint 2 — pg_cron |
| RR-06 | rpc_complete_onboarding duas sobrecargas | BAIXO | Sprint 3 |
| RR-07 | v_available_reviews / v_review_content ausentes no dump | P0 PRODUTO | Investigacao urgente separada |

---

## 11. Referencias

| Documento | Localizacao |
|-----------|-------------|
| complete_lesson (funcao atual) | `supabase/remote/supabase_remote_schema.sql` ln 1182–1249 |
| aulas.xp_valor | `supabase/remote/supabase_remote_schema.sql` ln 9075–9084 |
| fn_conceder_xp_aula (padrao de referencia) | `supabase/remote/supabase_remote_schema.sql` ln 2854–2878 |
| ux_xp_eventos_lesson_unique | `supabase/remote/supabase_remote_schema.sql` ln 16464 |
| v_recruta_xp_total | `supabase/remote/supabase_remote_schema.sql` ln 13511–13517 |
| Caller principal | `src/services/progressService.ts:50` |
| Tela caller | `app/(stack)/lesson/[id].tsx:101` |
| P0-M6 Handoff (predecessor) | `supabase/baseline/P0_M6_HANDOFF.md` |
| P0-M6 Pre-Audit | `supabase/baseline/P0_M6_PRE_AUDIT.md` |
| Pre-Deploy Gate (RR-01) | `supabase/baseline/PRE_DEPLOY_GATE.md §RR-01` |
| Plano de transicao | `supabase/baseline/P1_M1_TRANSITION_PLAN.md` |

---

## 12. Decisao Institucional Necessaria

```
[ ] Opcao selecionada: C — nova RPC rpc_complete_lesson(p_lesson_id uuid)
    (conforme apontado em PRE_DEPLOY_GATE.md §RR-01)

[ ] Confirmacao de que aulas.xp_valor esta populado antes do apply

[ ] Confirmacao sobre comportamento para xp_valor = 0:
    [ ] Conceder 0 XP (recomendado — explicito)
    [ ] Usar fallback configuravel (maior complexidade)

[ ] Confirmacao de que complete_lesson continuara disponivel para service_role
    durante a transicao (Sprint 2) e sera removida em Sprint 3

[ ] Aprovado por: ___________________________
[ ] Data: ___________________________________
```

---

**Status:** RASCUNHO — AGUARDANDO APROVACAO
