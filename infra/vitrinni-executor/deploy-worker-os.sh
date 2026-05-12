#!/usr/bin/env bash
# ============================================================
# deploy-worker-os.sh
# Copia worker-os.ts para a VPS e atualiza package.json
#
# USO:
#   bash infra/vitrinni-executor/deploy-worker-os.sh VPS_HOST
#
# Exemplo:
#   bash infra/vitrinni-executor/deploy-worker-os.sh root@IP_DA_VPS
#
# Pré-requisitos:
#   - SSH configurado para o host alvo
#   - jq instalado na VPS (apt install jq)
# ============================================================

set -euo pipefail

VPS_HOST="${1:?Uso: $0 root@IP_DA_VPS}"
EXECUTOR_DIR="/root/vitrinni-studio/tools/vitrinni-executor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_FILE="${SCRIPT_DIR}/src/worker-os.ts"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "[DEPLOY] Target: ${VPS_HOST}"
echo "[DEPLOY] Executor dir: ${EXECUTOR_DIR}"

# ── 1. Verifica arquivo fonte ────────────────────────────────
if [[ ! -f "${WORKER_FILE}" ]]; then
  echo "[ERRO] worker-os.ts não encontrado em: ${WORKER_FILE}"
  exit 1
fi

# ── 2. Backup do arquivo existente na VPS (se houver) ────────
ssh "${VPS_HOST}" "
  if [[ -f ${EXECUTOR_DIR}/src/worker-os.ts ]]; then
    cp ${EXECUTOR_DIR}/src/worker-os.ts ${EXECUTOR_DIR}/src/worker-os.ts.bak.${TIMESTAMP}
    echo '[DEPLOY] Backup criado: worker-os.ts.bak.${TIMESTAMP}'
  else
    echo '[DEPLOY] Nenhum arquivo existente — sem backup necessário'
  fi
"

# ── 3. Copia worker-os.ts para a VPS ─────────────────────────
echo "[DEPLOY] Copiando worker-os.ts..."
scp "${WORKER_FILE}" "${VPS_HOST}:${EXECUTOR_DIR}/src/worker-os.ts"
echo "[DEPLOY] worker-os.ts copiado."

# ── 4. Atualiza package.json com script worker:os ────────────
echo "[DEPLOY] Atualizando package.json..."
ssh "${VPS_HOST}" "
  cd ${EXECUTOR_DIR}
  PKG='package.json'

  if ! command -v jq &>/dev/null; then
    echo '[AVISO] jq não instalado — editar package.json manualmente:'
    echo '  \"worker:os\": \"tsx src/worker-os.ts\"'
    exit 0
  fi

  # Backup do package.json
  cp \"\${PKG}\" \"\${PKG}.bak.${TIMESTAMP}\"

  # Adiciona o script sem remover os existentes
  jq '.scripts[\"worker:os\"] = \"tsx src/worker-os.ts\"' \"\${PKG}\" > \"\${PKG}.tmp\" \
    && mv \"\${PKG}.tmp\" \"\${PKG}\"

  echo '[DEPLOY] package.json atualizado.'
  echo ''
  echo 'Scripts disponíveis após deploy:'
  jq '.scripts' \"\${PKG}\"
"

# ── 5. Verifica dependência @supabase/supabase-js ────────────
echo ""
echo "[DEPLOY] Verificando dependências..."
ssh "${VPS_HOST}" "
  cd ${EXECUTOR_DIR}
  if grep -q '@supabase/supabase-js' package.json; then
    echo '[OK] @supabase/supabase-js já listado em package.json'
  else
    echo '[AVISO] @supabase/supabase-js NÃO encontrado em package.json'
    echo '        Instalar com: npm install @supabase/supabase-js'
  fi
"

# ── 6. Resumo final ──────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  DEPLOY CONCLUÍDO"
echo "══════════════════════════════════════════════════════"
echo ""
echo "  Para iniciar o worker na VPS:"
echo ""
echo "    ssh ${VPS_HOST}"
echo "    cd ${EXECUTOR_DIR}"
echo "    export SUPABASE_URL='https://xxx.supabase.co'"
echo "    export SUPABASE_SERVICE_ROLE_KEY='eyJ...'"
echo "    npm run worker:os"
echo ""
echo "  Variáveis opcionais:"
echo "    OS_WORKER_ID             (default: worker-1)"
echo "    OS_WORKER_POLL_INTERVAL_MS (default: 2000)"
echo "    OS_EXECUTOR_URL          (default: http://127.0.0.1:3099/execute)"
echo ""
echo "══════════════════════════════════════════════════════"
