#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[code-server-2] Starting Code Server and oauth2-proxy (user2) ..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" up -d
