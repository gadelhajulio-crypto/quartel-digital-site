# Integração Stripe — Quartel Digital
## Documento Técnico Interno

**Sistema:** Quartel Digital
**Data:** 2026-03-13
**Status:** Implementado — aguardando configuração de ambiente

---

## 1. VISÃO GERAL

A integração Stripe no Quartel Digital segue o princípio banco-first da DECI-02:

```
Paywall do app
    ↓
Edge Function cria Checkout Session (metadata institucional)
    ↓
App abre Stripe Checkout via Linking.openURL()
    ↓
Stripe envia webhook
    ↓
n8n WF-STRIPE-WEBHOOK valida Stripe-Signature
    ↓
n8n chama rpc_billing_processar_evento_pagamento
    ↓
Supabase atualiza assinatura / acesso
    ↓
BootstrapGate revalida v_billing_status_recruta
    ↓
Usuário entra no app (/(tabs))
```

**Regras invioláveis:**
- O banco é a única fonte de verdade de acesso
- O n8n não decide acesso — apenas repassa eventos ao banco
- O frontend não decide acesso — apenas abre URL e revalida o gate
- A Stripe apenas informa fatos de pagamento

---

## 2. ARQUIVOS IMPLEMENTADOS

| Arquivo | Tipo | Responsabilidade |
|---|---|---|
| `supabase/functions/stripe-create-checkout-session/index.ts` | Edge Function | Cria Checkout Session com metadata institucional |
| `src/services/stripeService.ts` | Service (frontend) | Chama Edge Function e retorna checkout_url |
| `app/(auth)/paywall.tsx` | Screen (frontend) | Seleção de plano, abertura do checkout, deep link return |
| `workflows/billing/WF-STRIPE-WEBHOOK.workflow.json` | n8n workflow | Recebe webhook, valida assinatura, chama RPC |
| `supabase/config.toml` | Configuração | Registra nova Edge Function |

---

## 3. PARTE 1 — EDGE FUNCTION

### `stripe-create-checkout-session`

**Endpoint:** `POST /functions/v1/stripe-create-checkout-session`
**JWT:** obrigatório (`verify_jwt = true`)

**Request:**
```json
{
  "recruta_id": "uuid",
  "plan_slug": "mensal | anual"
}
```

**Response (sucesso):**
```json
{
  "ok": true,
  "checkout_url": "https://checkout.stripe.com/c/pay/cs_...",
  "session_id": "cs_...",
  "correlation_id": "uuid"
}
```

**Response (erro):**
```json
{
  "ok": false,
  "reason": "missing_env | invalid_plan_slug | recruta_not_found | internal_error",
  "request_id": "uuid"
}
```

**Fluxo interno:**
1. Valida secrets obrigatórios (`STRIPE_SECRET_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`)
2. Extrai JWT do header `Authorization`
3. Valida `recruta_id` e `plan_slug` no body
4. Seleciona `price_id` baseado em `plan_slug`
5. Busca recruta em `v_identidade_recruta`
6. Busca email do usuário via `auth.admin.getUserById()`
7. Cria Checkout Session na Stripe via REST API
8. Inclui metadata em `session.metadata` E `subscription_data.metadata`
9. Retorna `checkout_url` e `session_id`

**Metadata incluída na Checkout Session:**
```
metadata.recruta_id         = uuid do recruta
metadata.auth_id            = uuid do usuário Supabase
metadata.plan_slug          = "mensal" | "anual"
metadata.correlation_id     = uuid gerado por request
subscription_data.metadata  = (mesmo conjunto — disponível nos eventos de invoice)
```

---

## 4. PARTE 2 — N8N WORKFLOW

### `WF-STRIPE-WEBHOOK`

**Arquivo:** `workflows/billing/WF-STRIPE-WEBHOOK.workflow.json`
**Endpoint n8n:** `POST /webhook/billing/stripe`

**Nodes:**

| Node | Tipo | Função |
|---|---|---|
| Stripe Webhook | Webhook | Recebe POST com rawBody habilitado |
| Validar Assinatura Stripe | Code | HMAC-SHA256 timing-safe com STRIPE_WEBHOOK_SECRET |
| Normalizar Evento | Code | Extrai metadata, mapeia status_pagamento |
| Deve Processar? | If | Filtra eventos sem recruta_id ou ignorados |
| RPC Billing Processar Evento | HTTP Request | POST para rpc_billing_processar_evento_pagamento |
| Responder 200 - Processado | Respond to Webhook | HTTP 200 |
| Responder 200 - Ignorado | Respond to Webhook | HTTP 200 (evento não suportado) |

**Eventos tratados:**
| Evento Stripe | `status_pagamento` enviado à RPC |
|---|---|
| `checkout.session.completed` | `paid` |
| `invoice.paid` | `paid` |
| `invoice.payment_failed` | `failed` |
| `customer.subscription.deleted` | `cancelled` |

**Eventos ignorados (HTTP 200 sem chamar RPC):**
- Qualquer evento fora da lista acima
- Eventos sem `recruta_id` na metadata

**Validação de assinatura:**
- Algoritmo: HMAC-SHA256 do payload `{timestamp}.{rawBody}` com `STRIPE_WEBHOOK_SECRET`
- Tolerância de timestamp: 300 segundos (5 minutos)
- Comparação: timing-safe (proteção contra timing attack)
- Falha → exceção → n8n retorna 500 (Stripe vai retentar)

---

## 5. PARTE 3 — MAPEAMENTO BILLING RPC

### Parâmetros enviados para `rpc_billing_processar_evento_pagamento`

```json
{
  "p_gateway_nome": "stripe",
  "p_gateway_event_id": "evt_...",
  "p_status_pagamento": "paid | failed | cancelled",
  "p_recruta_id": "uuid",
  "p_auth_id": "uuid",
  "p_plan_slug": "mensal | anual",
  "p_correlation_id": "uuid",
  "p_amount": 9900,
  "p_currency": "brl",
  "p_customer_id": "cus_...",
  "p_subscription_id": "sub_...",
  "p_raw_event_type": "invoice.paid"
}
```

> A RPC é responsável por verificar idempotência (`rpc_billing_verificar_idempotencia`), atualizar a assinatura e liberar acesso. O n8n não faz nada além de repassar os dados.

---

## 6. PARTE 4 — FRONTEND

### Fluxo no paywall

1. Paywall renderiza billing atual (`v_billing_status_recruta`)
2. Usuário escolhe plano (Mensal ou Anual)
3. App chama `createCheckoutSession(profile.id, plan_slug)` via `stripeService`
4. App recebe `checkout_url` da Edge Function
5. App chama `Linking.openURL(checkout_url)` — abre browser externo
6. Usuário paga no Stripe
7. Stripe redireciona para `quarteldigital://checkout/success` (deep link)
8. App detecta deep link via `Linking.addEventListener('url', ...)`
9. App chama `retriggerGate()` — BootstrapGate revalida billing
10. Se `acesso_liberado = true` → navega para `/(tabs)`

**Importante:**
- O app não assume que o pagamento foi bem-sucedido ao receber o deep link
- O BootstrapGate revalida `v_billing_status_recruta` diretamente no banco
- A abertura do checkout não gera nenhuma mudança local de estado de acesso

### Deep link configurado

```
Scheme: quarteldigital (app.json → expo.scheme)
Success URL: quarteldigital://checkout/success
Cancel URL:  quarteldigital://checkout/cancel
```

---

## 7. PARTE 5 — CONFIGURAÇÃO DE AMBIENTE

### 7.1 Secrets da Edge Function (Supabase)

Configurar via `supabase secrets set` ou Dashboard → Settings → Edge Functions:

```bash
supabase secrets set STRIPE_SECRET_KEY="sk_live_..."
supabase secrets set STRIPE_PRICE_ID_MENSAL="price_..."
supabase secrets set STRIPE_PRICE_ID_ANUAL="price_..."
supabase secrets set STRIPE_SUCCESS_URL="quarteldigital://checkout/success"
supabase secrets set STRIPE_CANCEL_URL="quarteldigital://checkout/cancel"
```

> `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` são injetados automaticamente pelo Supabase nas Edge Functions.

### 7.2 Variáveis de ambiente do n8n

Configurar no painel n8n → Settings → Variables:

```
STRIPE_WEBHOOK_SECRET   = whsec_...   (gerado no Stripe Dashboard → Webhooks)
SUPABASE_URL            = https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY = eyJ...
```

### 7.3 Stripe Dashboard — Webhook

1. Acessar: https://dashboard.stripe.com/webhooks
2. Criar endpoint: `https://seu-n8n.dominio.com/webhook/billing/stripe`
3. Selecionar eventos:
   - `checkout.session.completed`
   - `invoice.paid`
   - `invoice.payment_failed`
   - `customer.subscription.deleted`
4. Copiar o **Signing secret** (`whsec_...`) → variável `STRIPE_WEBHOOK_SECRET` no n8n

### 7.4 Stripe Dashboard — Produtos e Preços

1. Criar produto: "Quartel Digital"
2. Criar preço mensal (recorrente, mensal) → copiar Price ID → `STRIPE_PRICE_ID_MENSAL`
3. Criar preço anual (recorrente, anual) → copiar Price ID → `STRIPE_PRICE_ID_ANUAL`

### 7.5 Variável de ambiente do app (frontend)

Já existente em `.env`:
```
EXPO_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
```
Nenhuma chave Stripe é exposta no frontend.

---

## 8. INSTRUÇÕES DE TESTE (SANDBOX)

### 8.1 Configuração inicial

1. Usar Stripe em modo **Test** (chaves `sk_test_...` e `pk_test_...`)
2. Configurar `STRIPE_SECRET_KEY` com a chave de teste
3. Criar webhook no Stripe Test com o endpoint do n8n
4. Usar o **Stripe CLI** para testar webhooks localmente:

```bash
# Instalar Stripe CLI
stripe login

# Redirecionar webhooks para n8n local
stripe listen --forward-to https://seu-n8n.dominio.com/webhook/billing/stripe

# Simular eventos
stripe trigger checkout.session.completed
stripe trigger invoice.paid
stripe trigger invoice.payment_failed
stripe trigger customer.subscription.deleted
```

### 8.2 Cartões de teste Stripe

| Cenário | Número do Cartão |
|---|---|
| Pagamento aprovado | `4242 4242 4242 4242` |
| Pagamento recusado | `4000 0000 0000 0002` |
| Requer autenticação 3DS | `4000 0025 0000 3155` |
| Saldo insuficiente | `4000 0000 0000 9995` |

Validade: qualquer data futura | CVV: qualquer 3 dígitos | CEP: qualquer

### 8.3 Fluxo de teste completo

```
1. Login com usuário de teste (onboarding concluído)
2. BootstrapGate detecta acesso_liberado = false → navega para paywall
3. Escolher "Plano Mensal" no paywall
4. App chama Edge Function → recebe checkout_url
5. Browser abre Stripe Checkout
6. Preencher com cartão 4242 4242 4242 4242
7. Completar pagamento
8. Stripe envia webhook para n8n
9. n8n valida assinatura → chama RPC billing
10. Supabase atualiza v_billing_status_recruta (acesso_liberado = true)
11. Stripe redireciona para quarteldigital://checkout/success
12. App detecta deep link → retriggerGate()
13. BootstrapGate consulta v_billing_status_recruta → acesso_liberado = true
14. App navega para /(tabs) ✓
```

### 8.4 Verificação de logs

**Edge Function:**
```bash
supabase functions logs stripe-create-checkout-session
```

**n8n:**
- Acessar execuções do workflow WF-STRIPE-WEBHOOK no painel n8n

**Supabase DB:**
```sql
-- Verificar se evento foi processado
SELECT * FROM billing_eventos WHERE gateway_event_id = 'evt_...' LIMIT 1;

-- Verificar status de acesso
SELECT * FROM v_billing_status_recruta WHERE recruta_id = 'uuid';
```

---

## 9. RISCOS E PONTOS DE ATENÇÃO

### 9.1 Metadata em eventos de invoice
Eventos `invoice.paid` e `invoice.payment_failed` têm metadata na **subscription**, não na session. O workflow n8n tenta extrair `obj.metadata` primeiro e depois `obj.subscription.metadata`. Validar que a Stripe popula esse campo corretamente em ambiente de produção.

### 9.2 Deep link vs. background app
Quando o usuário paga e o app está em background (não fechado), `Linking.addEventListener` recebe o deep link. Quando o app foi fechado completamente, `Linking.getInitialURL()` captura o URL. Ambos estão implementados. Testar nos dois cenários.

### 9.3 Webhook antes do deep link
O webhook Stripe pode levar alguns segundos para ser processado pelo n8n e refletir no banco. Se o usuário chegar no app antes do webhook ser processado, `retriggerGate()` pode encontrar `acesso_liberado = false` ainda. O botão "Verificar Acesso" no paywall resolve isso — o usuário pode revalidar manualmente.

### 9.4 Idempotência da RPC
A RPC `rpc_billing_processar_evento_pagamento` deve ser idempotente por `gateway_event_id`. Caso o n8n retente o webhook (por timeout ou falha), a RPC não deve processar o mesmo evento duas vezes. Confirmar que a RPC faz essa verificação internamente.

### 9.5 Rejeição de webhook (n8n retornando 5xx)
Se a validação de assinatura falhar ou a RPC retornar erro, o n8n lança exceção e retorna 500. A Stripe vai retentar o webhook conforme sua política (até 24h). Monitorar execuções com falha no painel n8n.

### 9.6 Expiração do checkout_url
URLs de Checkout Session da Stripe expiram em 24h. Se o usuário não completar o pagamento nesse prazo, precisará iniciar um novo checkout no paywall.

### 9.7 `plan_slug = 'trial'` não implementado
O contrato de entrada menciona `trial` como opção de `plan_slug`. A Edge Function rejeita esse valor atualmente (retorna `invalid_plan_slug`). Se o trial precisar ser tratado como checkout, adicionar o `price_id` correspondente e incluir `STRIPE_PRICE_ID_TRIAL` no ambiente.

---

## 10. CHECKLIST DE CONFIGURAÇÃO

```
[ ] Stripe: conta em modo Test configurada
[ ] Stripe: produto "Quartel Digital" criado
[ ] Stripe: preço mensal criado → STRIPE_PRICE_ID_MENSAL configurado
[ ] Stripe: preço anual criado → STRIPE_PRICE_ID_ANUAL configurado
[ ] Stripe: webhook criado com os 4 eventos obrigatórios
[ ] Stripe: Signing secret copiado → STRIPE_WEBHOOK_SECRET configurado no n8n
[ ] Supabase: STRIPE_SECRET_KEY configurado via secrets
[ ] Supabase: STRIPE_SUCCESS_URL configurado via secrets
[ ] Supabase: STRIPE_CANCEL_URL configurado via secrets
[ ] Supabase: Edge Function deployed (supabase functions deploy stripe-create-checkout-session)
[ ] n8n: workflow WF-STRIPE-WEBHOOK importado e ativado
[ ] n8n: variáveis SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY configuradas
[ ] DB: rpc_billing_processar_evento_pagamento existe e aceita os parâmetros mapeados
[ ] DB: v_billing_status_recruta expõe acesso_liberado por RLS para usuário autenticado
[ ] App: scheme "quarteldigital" confirmado em app.json ✓ (já configurado)
[ ] Teste: fluxo completo sandbox executado com sucesso
[ ] Teste: webhook de invoice.payment_failed valida corretamente
[ ] Teste: retriggerGate() após deep link navega para /(tabs) ✓
```

---

*Documento gerado pelo Agente Claude Code em 2026-03-13.*
*Referência normativa: DECI-02 — Arquitetura do Fluxo Inicial do Aplicativo.*
