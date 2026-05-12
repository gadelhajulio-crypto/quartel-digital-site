#!/usr/bin/env bash
# ============================================================
# Quartel Digital — Restauração do n8n a partir de backup
# ============================================================
# EXECUÇÃO NA VPS:
#   bash /opt/quartel-digital/restore.sh database-20260315.sqlite
# ============================================================

set -euo pipefail

DEPLOY_DIR="/opt/quartel-digital"
BACKUP_DIR="${DEPLOY_DIR}/backups/n8n"

if [[ -z "${1:-}" ]]; then
  echo "Uso: $0 <nome-do-arquivo-de-backup>"
  echo ""
  echo "Backups disponíveis:"
  ls "${BACKUP_DIR}"/database-*.sqlite 2>/dev/null || echo "  (nenhum backup encontrado)"
  exit 1
fi

BACKUP_FILE="${BACKUP_DIR}/$1"

if [[ ! -f "${BACKUP_FILE}" ]]; then
  echo "[ERRO] Arquivo não encontrado: ${BACKUP_FILE}"
  exit 1
fi

echo "[RESTORE] Arquivo: ${BACKUP_FILE}"
echo "[RESTORE] Tamanho: $(du -sh "${BACKUP_FILE}" | cut -f1)"
echo ""
read -rp "Confirmar restauração? Isso vai parar o n8n brevemente. (s/N): " CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 0; }

cd "${DEPLOY_DIR}"

echo "[RESTORE] Parando n8n..."
docker compose stop n8n

echo "[RESTORE] Substituindo database.sqlite..."
cp "${BACKUP_FILE}" "${DEPLOY_DIR}/n8n-data/database.sqlite"
chmod 600 "${DEPLOY_DIR}/n8n-data/database.sqlite"

echo "[RESTORE] Subindo n8n..."
docker compose start n8n

echo "[RESTORE] Aguardando healthcheck..."
sleep 10
docker inspect --format='{{.State.Health.Status}}' quartel-n8n

echo "[OK] Restauração concluída."
