#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[ollama-internal] Stopping ..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" down
