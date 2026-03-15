#!/usr/bin/env bash
set -euo pipefail
log() { echo -e "\e[34m[*]\e[0m $1"; }
ok()  { echo -e "\e[32m[+]\e[0m $1"; }

log "Resetting Open WebUI state (volumes)..."
docker compose down -v --remove-orphans &>/dev/null || true
docker volume rm open-webui_open_webui_data
ok "Open WebUI state cleared. Run start.sh to bring it back up fresh."
