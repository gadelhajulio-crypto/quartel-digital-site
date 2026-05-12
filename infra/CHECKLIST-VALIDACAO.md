# CHECKLIST DE VALIDAÇÃO — Quartel Digital VPS KVM1

Execute em ordem após `deploy.sh` concluir.

---

## FASE 1 — Infra

```bash
# Rodar script automatizado
bash /opt/quartel-digital/validate.sh
```

Verificação manual se necessário:

```bash
docker compose ps
# quartel-n8n         → Up (healthy)
# quartel-cloudflared → Up

docker compose logs --tail=20 n8n
docker compose logs --tail=20 cloudflared
```

---

## FASE 2 — Healthcheck público

```bash
curl -i https://n8n.recrutapadrao.com.br/healthz
# Esperado: HTTP/2 200
```

---

## FASE 3 — Painel n8n

- [ ] Acessar `https://n8n.recrutapadrao.com.br`
- [ ] Login funciona
- [ ] WF-PAYMENT-WEBHOOK aparece e está **ATIVO** (verde)
- [ ] WF-BILLING-NOTIFICATIONS aparece e está **ATIVO** (verde)
- [ ] URL do webhook exibida no node = `https://n8n.recrutapadrao.com.br/webhook/billing/stripe`

---

## FASE 4 — Teste de webhook (Stripe CLI)

```bash
# Instalar Stripe CLI se necessário: https://stripe.com/docs/stripe-cli
stripe login

# Disparar evento de teste
stripe trigger checkout.session.completed

# Monitorar execução no painel n8n:
# https://n8n.recrutapadrao.com.br → Executions → WF-PAYMENT-WEBHOOK
# Esperado: status SUCCESS
```

---

## FASE 5 — Validação no banco

```sql
-- Verificar no Supabase SQL Editor:

-- Evento foi registrado?
SELECT * FROM billing_eventos
ORDER BY created_at DESC
LIMIT 5;

-- Acesso foi liberado para recruta de teste?
SELECT recruta_id, acesso_liberado, plano_ativo
FROM v_billing_status_recruta
WHERE recruta_id = 'UUID_DO_RECRUTA_TESTE';
```

---

## FASE 6 — Stripe Dashboard

- [ ] `dashboard.stripe.com → Webhooks`
- [ ] Endpoint `n8n.recrutapadrao.com.br/webhook/billing/stripe` → último evento: **200 OK**
- [ ] Nenhum evento em fila de retry com falha

---

## FASE 7 — Cutover final

Somente após todas as fases acima passarem:

- [ ] Cloudflare Zero Trust → **desativar** tunnel da máquina local
- [ ] Máquina local pode ser desligada sem impacto
- [ ] Monitorar Stripe Dashboard por 30 minutos após o cutover

---

## Rollback de emergência

Se algo falhar após o cutover:

```bash
# 1. Cloudflare Zero Trust → reativar tunnel local
# 2. Iniciar cloudflared localmente com token do tunnel local:
cloudflared tunnel run --token $TOKEN_DO_TUNNEL_LOCAL

# 3. Stripe vai retentar webhooks falhos por até 24h automaticamente
```
