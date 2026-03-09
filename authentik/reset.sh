#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DC="docker compose -f docker-compose.yaml -f docker-compose.override.yaml"

log() { echo -e "\e[34m[*]\e[0m $1"; }
ok()  { echo -e "\e[32m[+]\e[0m $1"; }

log "Resetting Authentik state (volumes, data dirs, secrets, compose manifest)..."

$DC down -v --remove-orphans &>/dev/null || true

rm -rf ./data ./certs ./custom-templates
rm -f .env
rm -f docker-compose.yaml   # force re-fetch of upstream compose on next start

ok "Authentik state cleared. Run start.sh to bring it back up fresh."
