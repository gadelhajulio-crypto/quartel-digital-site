#!/usr/bin/env bash
# ============================================================
# Quartel Digital — Checklist de validação pós-implantação
# ============================================================
# EXECUÇÃO NA VPS (após deploy):
#   bash /opt/quartel-digital/validate.sh
# ============================================================

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
check_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
check_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARN=$((WARN+1)); }
section()    { echo ""; echo "── $1 ──────────────────────────────────"; }

echo "══════════════════════════════════════════════════════"
echo "  Quartel Digital — Validação da VPS KVM1"
echo "  $(date)"
echo "══════════════════════════════════════════════════════"

# ── CONTAINERS ───────────────────────────────────────────
section "CONTAINERS"

N8N_STATUS=$(docker inspect --format='{{.State.Status}}' quartel-n8n 2>/dev/null || echo "not_found")
N8N_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' quartel-n8n 2>/dev/null || echo "not_found")

if [[ "$N8N_STATUS" == "running" ]]; then
  check_pass "quartel-n8n: running"
else
  check_fail "quartel-n8n: ${N8N_STATUS}"
fi

if [[ "$N8N_HEALTH" == "healthy" ]]; then
  check_pass "quartel-n8n: healthy"
elif [[ "$N8N_HEALTH" == "starting" ]]; then
  check_warn "quartel-n8n: ainda inicializando (health=starting)"
else
  check_fail "quartel-n8n: health=${N8N_HEALTH}"
fi

CF_STATUS=$(docker inspect --format='{{.State.Status}}' quartel-cloudflared 2>/dev/null || echo "not_found")
if [[ "$CF_STATUS" == "running" ]]; then
  check_pass "quartel-cloudflared: running"
else
  check_fail "quartel-cloudflared: ${CF_STATUS}"
fi

# ── HEALTHCHECK INTERNO ──────────────────────────────────
section "HEALTHCHECK INTERNO"

if docker exec quartel-n8n wget -qO- http://localhost:5678/healthz &>/dev/null; then
  check_pass "n8n /healthz interno: OK"
else
  check_fail "n8n /healthz interno: falhou"
fi

# ── HEALTHCHECK EXTERNO (via domínio público) ────────────
section "HEALTHCHECK EXTERNO"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time 10 \
  https://n8n.recrutapadrao.com.br/healthz 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
  check_pass "https://n8n.recrutapadrao.com.br/healthz: HTTP ${HTTP_CODE}"
elif [[ "$HTTP_CODE" == "000" ]]; then
  check_fail "https://n8n.recrutapadrao.com.br/healthz: sem resposta (tunnel ativo?)"
else
  check_warn "https://n8n.recrutapadrao.com.br/healthz: HTTP ${HTTP_CODE}"
fi

# ── TUNNEL CLOUDFLARE ────────────────────────────────────
section "CLOUDFLARE TUNNEL"

CF_LOGS=$(docker logs quartel-cloudflared --tail=20 2>&1 || echo "")
if echo "$CF_LOGS" | grep -q "Registered tunnel connection"; then
  check_pass "cloudflared: tunnel connection registrado"
elif echo "$CF_LOGS" | grep -q "error"; then
  check_fail "cloudflared: erro nos logs (verificar manualmente)"
  echo "  Últimas linhas:"
  docker logs quartel-cloudflared --tail=5 2>&1 | sed 's/^/    /'
else
  check_warn "cloudflared: não foi possível confirmar conexão (verificar logs)"
fi

# ── VARIÁVEIS DE AMBIENTE ────────────────────────────────
section "VARIÁVEIS DE AMBIENTE"

ENV_FILE="/opt/quartel-digital/.env"
if [[ -f "$ENV_FILE" ]]; then
  check_pass ".env existe"
  PERM=$(stat -c "%a" "$ENV_FILE")
  if [[ "$PERM" == "600" ]]; then
    check_pass ".env permissão: 600"
  else
    check_warn ".env permissão: ${PERM} (esperado 600)"
  fi

  for VAR in N8N_ENCRYPTION_KEY SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY \
             STRIPE_WEBHOOK_SECRET QD_HMAC_SECRET CLOUDFLARED_TUNNEL_TOKEN; do
    if grep -q "^${VAR}=.\+" "$ENV_FILE" 2>/dev/null; then
      check_pass "${VAR}: configurado"
    else
      check_fail "${VAR}: ausente ou vazio"
    fi
  done
else
  check_fail ".env não encontrado em ${ENV_FILE}"
fi

# ── BACKUP ───────────────────────────────────────────────
section "BACKUP"

BACKUP_DIR="/opt/quartel-digital/backups/n8n"
if [[ -d "$BACKUP_DIR" ]]; then
  check_pass "Diretório de backup existe"
else
  check_fail "Diretório de backup não existe: ${BACKUP_DIR}"
fi

if crontab -l 2>/dev/null | grep -q "n8n-db-backup"; then
  check_pass "Crontab de backup configurado"
else
  check_warn "Crontab de backup não encontrado (executar deploy.sh para configurar)"
fi

# ── MEMÓRIA / RECURSOS ───────────────────────────────────
section "RECURSOS DO HOST"

MEM_FREE=$(free -m | awk '/^Mem:/ {print $7}')
MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
MEM_USED=$((MEM_TOTAL - MEM_FREE))
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))

if [[ $MEM_PCT -lt 80 ]]; then
  check_pass "Memória: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)"
elif [[ $MEM_PCT -lt 90 ]]; then
  check_warn "Memória: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%) — atenção"
else
  check_fail "Memória: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%) — crítico"
fi

DISK_PCT=$(df /opt --output=pcent | tail -1 | tr -d ' %')
if [[ $DISK_PCT -lt 70 ]]; then
  check_pass "Disco /opt: ${DISK_PCT}% usado"
elif [[ $DISK_PCT -lt 85 ]]; then
  check_warn "Disco /opt: ${DISK_PCT}% usado — monitorar"
else
  check_fail "Disco /opt: ${DISK_PCT}% usado — crítico"
fi

# ── RESUMO ───────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  RESULTADO: ${PASS} passou | ${WARN} aviso | ${FAIL} falhou"
echo "══════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Há falhas críticas. Verificar logs:"
  echo "  docker compose logs -f"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo ""
  echo "Avisos detectados — revisar antes de cutover final."
  exit 0
else
  echo ""
  echo "VPS pronta para operação."
  exit 0
fi
