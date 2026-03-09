#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[opensearch] Stopping ..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" down
