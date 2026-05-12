#!/usr/bin/env bash
# ============================================================
# Quartel Digital — Script de implantação na VPS KVM1
# ============================================================
# EXECUÇÃO:
#   1. Copiar este diretório para a VPS:
#      scp -r infra/ root@IP_DA_VPS:/tmp/quartel-deploy/
#
#   2. SSH na VPS e executar:
#      bash /tmp/quartel-deploy/deploy.sh
#
# O script solicita os valores dos secrets interativamente.
# Nenhum secret é hardcoded aqui.
# ============================================================

set -euo pipefail

# ── Cores ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[DEPLOY]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
fail() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

DEPLOY_DIR="/opt/quartel-digital"

# ============================================================
# FASE 1 — Sistema
# ============================================================
log "FASE 1 — Atualizando sistema..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
ok "Sistema atualizado."

# ============================================================
# FASE 2 — Docker
# ============================================================
if command -v docker &>/dev/null; then
  ok "Docker já instalado: $(docker --version)"
else
  log "FASE 2 — Instalando Docker..."
  curl -fsSL https://get.docker.com | sh
  ok "Docker instalado: $(docker --version)"
fi

if docker compose version &>/dev/null; then
  ok "Docker Compose disponível: $(docker compose version)"
else
  fail "Docker Compose plugin não encontrado. Verificar instalação do Docker."
fi

# ============================================================
# FASE 3 — Estrutura de diretórios
# ============================================================
log "FASE 3 — Criando estrutura de diretórios..."
mkdir -p "${DEPLOY_DIR}/cloudflared"
mkdir -p "${DEPLOY_DIR}/n8n-data"
mkdir -p "${DEPLOY_DIR}/backups/n8n"
ok "Estrutura criada em ${DEPLOY_DIR}/"

# ============================================================
# FASE 4 — Copiar docker-compose.yml
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "FASE 4 — Copiando docker-compose.yml..."
cp "${SCRIPT_DIR}/docker-compose.yml" "${DEPLOY_DIR}/docker-compose.yml"
ok "docker-compose.yml copiado."

# ============================================================
# FASE 5 — Criar .env com secrets
# ============================================================
log "FASE 5 — Configurando secrets..."

if [[ -f "${DEPLOY_DIR}/.env" ]]; then
  warn ".env já existe em ${DEPLOY_DIR}/.env"
  read -rp "Sobrescrever? (s/N): " OVERWRITE
  [[ "$OVERWRITE" =~ ^[sS]$ ]] || { log "Mantendo .env existente."; }
fi

if [[ ! -f "${DEPLOY_DIR}/.env" ]] || [[ "$OVERWRITE" =~ ^[sS]$ ]]; then
  echo ""
  echo "──────────────────────────────────────────────"
  echo "  Preencha os secrets da VPS"
  echo "  (os valores NÃO aparecem na tela)"
  echo "──────────────────────────────────────────────"
  echo ""

  read -rsp "SUPABASE_URL (ex: https://xxx.supabase.co): " SUPABASE_URL; echo
  read -rsp "SUPABASE_SERVICE_ROLE_KEY (eyJ...): " SUPABASE_SERVICE_ROLE_KEY; echo
  read -rsp "STRIPE_WEBHOOK_SECRET (whsec_...): " STRIPE_WEBHOOK_SECRET; echo
  read -rsp "QD_HMAC_SECRET: " QD_HMAC_SECRET; echo
  read -rsp "CLOUDFLARED_TUNNEL_TOKEN (eyJ...): " CLOUDFLARED_TUNNEL_TOKEN; echo

  log "Gerando N8N_ENCRYPTION_KEY..."
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
  echo ""
  warn "=========================================================="
  warn "ATENÇÃO: guarde esta chave em local seguro (ex: 1Password)"
  warn "N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}"
  warn "Perder = perder todas as credentials salvas no n8n."
  warn "=========================================================="
  echo ""
  read -rp "Confirmei que salvei a chave → pressione ENTER para continuar: "

  cat > "${DEPLOY_DIR}/.env" <<EOF
# Quartel Digital — VPS KVM1
# Gerado em: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# NÃO versionar este arquivo.

N8N_WEBHOOK_URL=https://n8n.recrutapadrao.com.br
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

SUPABASE_URL=${SUPABASE_URL}
SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}

STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}
QD_HMAC_SECRET=${QD_HMAC_SECRET}

CLOUDFLARED_TUNNEL_TOKEN=${CLOUDFLARED_TUNNEL_TOKEN}

N8N_BLOCK_ENV_ACCESS_IN_NODE=false
NODE_FUNCTION_ALLOW_BUILTIN=crypto

EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168
EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_PROGRESS=false
EOF

  chmod 600 "${DEPLOY_DIR}/.env"
  chown root:root "${DEPLOY_DIR}/.env"
  ok ".env criado e protegido (chmod 600)."
fi

# ============================================================
# FASE 6 — Subir containers
# ============================================================
log "FASE 6 — Subindo containers..."
cd "${DEPLOY_DIR}"
docker compose pull
docker compose up -d
ok "Containers iniciados."

# ============================================================
# FASE 7 — Validação
# ============================================================
log "FASE 7 — Aguardando n8n ficar saudável..."

MAX_WAIT=90
ELAPSED=0
INTERVAL=5

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' quartel-n8n 2>/dev/null || echo "starting")
  if [[ "$STATUS" == "healthy" ]]; then
    ok "quartel-n8n: healthy"
    break
  fi
  echo "  aguardando... (${ELAPSED}s / ${STATUS})"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ "$STATUS" != "healthy" ]]; then
  warn "n8n ainda não está healthy após ${MAX_WAIT}s. Verificar logs:"
  docker compose logs --tail=30 n8n
fi

log "Status dos containers:"
docker compose ps

# ============================================================
# FASE 8 — Teste de healthcheck
# ============================================================
log "FASE 8 — Testando healthcheck interno..."
if docker exec quartel-n8n wget -qO- http://localhost:5678/healthz &>/dev/null; then
  ok "Healthcheck n8n: OK"
else
  warn "Healthcheck interno falhou. n8n pode ainda estar inicializando."
fi

# ============================================================
# FASE 9 — Instalar backup automático via crontab
# ============================================================
log "FASE 9 — Configurando backup automático..."

CRON_CMD="0 3 * * * docker exec quartel-n8n cp /home/node/.n8n/database.sqlite /tmp/n8n-db-backup.sqlite && cp /tmp/n8n-db-backup.sqlite ${DEPLOY_DIR}/backups/n8n/database-\$(date +\\%Y\\%m\\%d).sqlite && find ${DEPLOY_DIR}/backups/n8n/ -name 'database-*.sqlite' -mtime +7 -delete 2>/dev/null"

# Adiciona ao crontab apenas se não existir
(crontab -l 2>/dev/null | grep -v "n8n-db-backup"; echo "${CRON_CMD}") | crontab -
ok "Crontab de backup configurado (diário às 03:00)."

# ============================================================
# RESUMO FINAL
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  IMPLANTAÇÃO CONCLUÍDA"
echo "══════════════════════════════════════════════════════════"
echo ""
echo "  Próximos passos obrigatórios:"
echo ""
echo "  1. Acesse o painel n8n:"
echo "     https://n8n.recrutapadrao.com.br"
echo "     → Crie a conta admin (primeiro acesso)"
echo ""
echo "  2. Importe os workflows:"
echo "     Settings → Import Workflows"
echo "     → workflows/billing/WF-STRIPE-WEBHOOK.workflow.json"
echo ""
echo "  3. Ative os workflows:"
echo "     WF-PAYMENT-WEBHOOK → toggle ON"
echo "     WF-BILLING-NOTIFICATIONS → toggle ON"
echo ""
echo "  4. Valide o webhook:"
echo "     curl https://n8n.recrutapadrao.com.br/healthz"
echo ""
echo "  5. Execute o checklist de validação completo:"
echo "     ver: infra/CHECKLIST-VALIDACAO.md"
echo ""
echo "══════════════════════════════════════════════════════════"
