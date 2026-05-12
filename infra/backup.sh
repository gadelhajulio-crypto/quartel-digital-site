#!/usr/bin/env bash
# ============================================================
# Quartel Digital — Backup manual do n8n
# ============================================================
# EXECUÇÃO NA VPS:
#   bash /opt/quartel-digital/backup.sh
# ============================================================

set -euo pipefail

DEPLOY_DIR="/opt/quartel-digital"
BACKUP_DIR="${DEPLOY_DIR}/backups/n8n"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/database-${TIMESTAMP}.sqlite"

echo "[BACKUP] Iniciando backup do n8n..."

# Verifica se o container está rodando
if ! docker inspect quartel-n8n &>/dev/null; then
  echo "[ERRO] Container quartel-n8n não encontrado."
  exit 1
fi

# Copia o sqlite de dentro do container
docker exec quartel-n8n cp /home/node/.n8n/database.sqlite /tmp/n8n-db-backup.sqlite

# Copia do container para o host
docker cp quartel-n8n:/tmp/n8n-db-backup.sqlite "${BACKUP_FILE}"

# Remove backups com mais de 7 dias
find "${BACKUP_DIR}" -name "database-*.sqlite" -mtime +7 -delete

echo "[OK] Backup salvo em: ${BACKUP_FILE}"
echo "[OK] Tamanho: $(du -sh "${BACKUP_FILE}" | cut -f1)"

# Lista backups disponíveis
echo ""
echo "Backups disponíveis:"
ls -lh "${BACKUP_DIR}"/database-*.sqlite 2>/dev/null || echo "  (nenhum)"
