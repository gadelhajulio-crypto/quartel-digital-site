# RELATÓRIO DE EXECUÇÃO TÉCNICA
## DECI-02 — Arquitetura do Fluxo Inicial do Aplicativo

**Sistema:** Quartel Digital
**Plataforma:** React Native + Expo Router
**Data de execução:** 2026-03-13
**Status:** Concluído
**Executor:** Agente Claude Code (claude-sonnet-4-6)

---

## 1. CONTEXTO DA MISSÃO

A deliberação **DECI-02**, aprovada pelo Cérebro Institucional, definiu a arquitetura oficial do fluxo inicial do aplicativo Quartel Digital. A missão deste agente foi traduzir integralmente essa deliberação em código frontend, sem rediscutir decisões arquiteturais, sem criar lógica de negócio fora do banco e sem introduzir atalhos que violassem a governança banco-first.

O princípio central que guiou toda a execução:

> **Banco decide. Frontend renderiza.**

---

## 2. DIAGNÓSTICO DO ESTADO ANTERIOR

### 2.1 O que já existia e estava conforme

| Componente | Estado | Observação |
|---|---|---|
| `AuthContext` | ✅ Conforme | Expunha `session`, `profile`, `loading`, `profileLoading`, `signOut`, `refetchProfile`. Carregava identidade via `v_identidade_recruta`. |
| `BootstrapGate` (parcial) | ⚠️ Parcial | Verificava auth + identity + bootstrap. Faltava billing e redirect para paywall. |
| `bootstrapService.ts` | ⚠️ Parcial | Consultava `v_app_bootstrap_institucional`. Não havia serviço de billing. |
| Estrutura de tabs | ✅ Conforme | `(tabs)/` com Home, Módulos, Histórico, Mensagens, Ranking, Perfil, Chat e outros. |
| Telas de auth | ✅ Conforme | Login, MFA, bloqueado, inativo, senha expirada, esqueci senha. |

### 2.2 O que estava ausente ou incorreto

| Componente | Estado | Problema |
|---|---|---|
| Billing check no gate | ⛔ Ausente | O gate redirecionava para `/(tabs)` sem consultar `v_billing_status_recruta`. |
| Tela de paywall | ⛔ Ausente | Não existia. |
| Fluxo de onboarding | ⛔ Incompleto | `welcome.tsx` era um placeholder de 9 linhas sem funcionalidade. |
| `billingService.ts` | ⛔ Ausente | Nenhuma camada de leitura de billing existia. |
| `BootstrapGateContext` | ⛔ Ausente | Nenhum mecanismo de reentrada no gate existia. |
| `onboardingService.ts` | ⛔ Ausente | Nenhum serviço para persistir dados de onboarding existia. |
| Layout do grupo onboarding | ⛔ Ausente | `(onboarding)/` não tinha `_layout.tsx`, impossibilitando navegação em stack. |

---

## 3. ARQUITETURA IMPLEMENTADA

### 3.1 Fluxo oficial de resolução (DECI-02)

```
App Start
    ↓
AuthContext resolve session
    ↓
BootstrapGate aguarda authLoading + profileLoading
    ↓
[sem sessão] → /(auth)/login
    ↓
[sessão existe]
BootstrapGate resolve v_identidade_recruta (via AuthContext.profile)
    ↓
[falha] → Erro institucional
    ↓
BootstrapGate consulta v_app_bootstrap_institucional
    ↓
[falha] → Erro institucional
    ↓
[onboarding_concluido = false] → /(onboarding)/welcome
    ↓
BootstrapGate consulta v_billing_status_recruta
    ↓
[acesso_liberado = false] → /(auth)/paywall
    ↓
[acesso_liberado = true] → /(tabs)
```

### 3.2 Mecanismo de reentrada no gate

Após onboarding ou pagamento, o gate é reiniciado via `retriggerGate()`, exposto pelo `BootstrapGateContext`. O mecanismo usa um contador (`retriggerKey`) no array de dependências do `useEffect` central. Ao ser incrementado, força nova resolução completa da cadeia de estados sem duplicar lógica de negócio.

```
Onboarding concluído
    → saveOnboardingData() [DB]
    → refetchProfile() [AuthContext]
    → retriggerGate() [BootstrapGateContext]
    → Gate reexecuta: billing → tabs ou paywall

Pagamento confirmado
    → retriggerGate() [BootstrapGateContext]
    → Gate reexecuta: billing → tabs
```

---

## 4. ARQUIVOS CRIADOS

### 4.1 `src/services/billingService.ts`

**Responsabilidade:** Leitura canônica de `v_billing_status_recruta`.
**Contrato de saída:**

```typescript
interface BillingStatus {
  acesso_liberado: boolean;
  plano_atual: string | null;
  status_assinatura: string | null;
  validade: string | null;
  trial_restante: number | null;
}
```

**Regra:** Lança erro em caso de falha. Não retorna fallback. O gate trata o erro como erro institucional.

---

### 4.2 `src/context/BootstrapGateContext.tsx`

**Responsabilidade:** Expor `retriggerGate()` para qualquer tela filha do gate.
**Consumidores:** `paywall.tsx`, `confirmacao.tsx`.
**Comportamento:** Lança erro se chamado fora da hierarquia do BootstrapGate.

---

### 4.3 `src/services/onboardingService.ts`

**Responsabilidade:** Persistir dados de onboarding na tabela `profiles`.
**Campos gravados:** `forca`, `nome_guerra`, `onboarding_concluido = true`.
**Regra:** Lança erro em caso de falha. Não tem fallback. A tela exibe mensagem de erro ao usuário.

---

### 4.4 `app/(auth)/paywall.tsx`

**Responsabilidade:** Tela de acesso restrito.
**Fonte de dados:** `v_billing_status_recruta` via `getBillingStatus()`.
**Campos exibidos:** `plano_atual`, `status_assinatura`, `validade`, `trial_restante`.
**Ações disponíveis:**
- **Verificar Acesso** — chama `retriggerGate()`, reexecutando o gate.
- **Sair** — chama `signOut()` do AuthContext.

**Regra crítica:** O frontend não calcula nem infere acesso. Apenas renderiza o estado retornado pelo banco.

---

### 4.5 `app/(onboarding)/_layout.tsx`

**Responsabilidade:** Define Stack Navigator para o grupo `(onboarding)`.
**Telas registradas:** `welcome`, `nome-guerra`, `confirmacao`.
**Configuração:** `headerShown: false`, animação `slide_from_right`.

---

### 4.6 `app/(onboarding)/nome-guerra.tsx`

**Responsabilidade:** Step 2 do onboarding — coleta nome de guerra.
**Entrada recebida:** `forca` via params de URL.
**Saída:** navega para `confirmacao` com `forca` e `nome_guerra` via params.
**Validação:** campo obrigatório — botão desabilitado enquanto vazio.

---

### 4.7 `app/(onboarding)/confirmacao.tsx`

**Responsabilidade:** Step 3 do onboarding — revisão e persistência.
**Entrada recebida:** `forca` e `nome_guerra` via params de URL.
**Sequência de confirmação:**
1. `saveOnboardingData(profile.id, forca, nome_guerra)` — persiste no banco
2. `refetchProfile()` — atualiza identidade no AuthContext
3. `retriggerGate()` — reinicia o gate, que decide tabs ou paywall

---

## 5. ARQUIVOS MODIFICADOS

### 5.1 `src/components/navigation/BootstrapGate.tsx`

**Mudanças aplicadas:**

| Aspecto | Antes | Depois |
|---|---|---|
| Billing | Ausente | Consulta `v_billing_status_recruta` após bootstrap |
| Destino após billing | `/(tabs)` direto | `/(tabs)` ou `/(auth)/paywall` conforme `acesso_liberado` |
| Mecanismo de retrigger | Ausente | `retriggerKey` + `BootstrapGateContext` |
| Separação de destino | Estado misto | `GateDestination` tipado, mapa de rotas explícito |
| Timeout | Só no bootstrap | Bootstrap e billing — 10s cada |
| Contexto exposto | Nenhum | `BootstrapGateContext.Provider` no estado `ready` |

**Tipo `GateDestination` introduzido:**
```typescript
type GateDestination =
  | 'login' | 'mfa' | 'locked' | 'inactive' | 'password_expired'
  | 'onboarding' | 'paywall' | 'tabs'
  | null;
```

**Invariantes mantidos:**
- `bootstrapState` fora do array de dependências do `useEffect` — evita loop infinito
- Token de cancelamento (`cancelled`) em todas as operações assíncronas
- `lastAuthStatus.current` previne reexecução desnecessária em re-renders

### 5.2 `app/(onboarding)/welcome.tsx`

**Antes:** Placeholder estático de 9 linhas sem funcionalidade.
**Depois:** Step 1 do onboarding — seleção de Força (Exército, Marinha, Aeronáutica).
Navega para `nome-guerra` passando a força selecionada via params.

---

## 6. ARQUIVOS NÃO ALTERADOS

Os seguintes arquivos foram intencionalmente preservados sem modificação:

| Arquivo | Motivo |
|---|---|
| `app/_layout.tsx` | BootstrapGate já estava montado corretamente. Nenhum ajuste necessário. |
| `src/context/AuthContext.tsx` | Totalmente conforme a DECI-02. Carrega `v_identidade_recruta`, expõe interface completa. |
| `src/services/bootstrapService.ts` | Correto e suficiente. Billing separado em serviço próprio conforme responsabilidade única. |
| `app/(tabs)/_layout.tsx` | Estrutura de tabs aprovada — preservada integralmente. |
| `src/lib/supabase.ts` | Cliente canônico — sem alteração. |

---

## 7. CONTRATOS CANÔNICOS CONSUMIDOS

| View / RPC | Consumidor | Campo decisório |
|---|---|---|
| `v_identidade_recruta` | `AuthContext` (loadProfile) | `onboarding_concluido` |
| `v_app_bootstrap_institucional` | `bootstrapService.checkAppBootstrap()` | sucesso da query |
| `v_billing_status_recruta` | `billingService.getBillingStatus()` | `acesso_liberado` |
| `profiles` (tabela) | `onboardingService.saveOnboardingData()` | escrita: forca, nome_guerra, onboarding_concluido |

---

## 8. RESTRIÇÕES RESPEITADAS

Conforme a DECI-02, as seguintes restrições foram observadas integralmente:

- ✅ Nenhuma lógica de acesso criada no frontend
- ✅ Nenhum cálculo de trial ou assinatura no frontend
- ✅ Nenhum atalho direto de onboarding para tabs
- ✅ Nenhum atalho direto de login para tabs
- ✅ Nenhum dado não canônico usado para liberar acesso
- ✅ Nenhuma decisão de rota inicial fora do BootstrapGate
- ✅ Nenhuma duplicação de regra entre layout, screen e hook
- ✅ Nenhum mock em fluxo real
- ✅ Nenhum contrato SQL alterado
- ✅ Nenhuma view criada ou substituída

---

## 9. PONTOS DE VALIDAÇÃO OBRIGATÓRIA

Os itens abaixo requerem validação manual antes de deploy em produção:

### 9.1 Nome da tabela de onboarding
O `onboardingService.ts` atualiza `profiles.id`. Confirmar que:
- A tabela se chama `profiles`
- A chave de busca é `id` (e não `auth_id`)

Ajuste necessário se diferente:
```typescript
.eq('id', profileId)  // alterar conforme schema real
```

### 9.2 Colunas de `v_billing_status_recruta`
Confirmar que a view expõe exatamente:
- `acesso_liberado` (boolean)
- `plano_atual` (text)
- `status_assinatura` (text)
- `validade` (text ou timestamp)
- `trial_restante` (integer)

### 9.3 RLS de `v_billing_status_recruta`
Confirmar que a view retorna exatamente **uma linha** por usuário autenticado (via RLS). A query usa `.single()` — se retornar zero ou múltiplas linhas, o gate lançará erro institucional.

### 9.4 Hierarquia de contexto no paywall
`paywall.tsx` e `confirmacao.tsx` consomem `useBootstrapGate()`. Isso funciona porque ambas são filhas do BootstrapGate no root layout. Qualquer tela fora dessa hierarquia que tente consumir o contexto lançará erro explícito.

---

## 10. SUMÁRIO DE ARQUIVOS

| Arquivo | Operação |
|---|---|
| `src/services/billingService.ts` | Criado |
| `src/context/BootstrapGateContext.tsx` | Criado |
| `src/services/onboardingService.ts` | Criado |
| `app/(auth)/paywall.tsx` | Criado |
| `app/(onboarding)/_layout.tsx` | Criado |
| `app/(onboarding)/nome-guerra.tsx` | Criado |
| `app/(onboarding)/confirmacao.tsx` | Criado |
| `src/components/navigation/BootstrapGate.tsx` | Modificado |
| `app/(onboarding)/welcome.tsx` | Modificado |

**Total:** 7 arquivos criados, 2 modificados.

---

## 11. CONFORMIDADE FINAL

```
Session         ✅  AuthContext.session via Supabase Auth
Identity        ✅  AuthContext.profile via v_identidade_recruta
Bootstrap       ✅  bootstrapService via v_app_bootstrap_institucional
Billing         ✅  billingService via v_billing_status_recruta
Destino         ✅  BootstrapGate — único decisor de rota inicial

/login          ✅  authStatus !== 'authenticated'
/onboarding     ✅  onboarding_concluido = false
/paywall        ✅  acesso_liberado = false
/(tabs)         ✅  acesso_liberado = true

Loading         ✅  "Quartel Digital / Inicializando ambiente institucional..."
Erro            ✅  Tentar novamente + Sair
Retrigger       ✅  retriggerGate() via BootstrapGateContext
```

---

*Documento gerado pelo Agente Claude Code em 2026-03-13.*
*Referência normativa: DECI-02 — Arquitetura do Fluxo Inicial do Aplicativo.*
*Status da deliberação: APROVADO pelo Cérebro Institucional.*
