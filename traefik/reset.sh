#!/usr/bin/env bash
set -euo pipefail
log() { echo -e "\e[34m[*]\e[0m $1"; }
ok()  { echo -e "\e[32m[+]\e[0m $1"; }

log "Resetting Traefik state (volumes)..."
docker compose down -v --remove-orphans &>/dev/null || true
rm -rf certs/*
ok "Traefik state cleared. Run start.sh to bring it back up fresh."
