#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[grafana] Starting Grafana ..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" up -d
