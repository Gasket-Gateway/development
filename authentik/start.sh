#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DC="docker compose -f docker-compose.yaml -f docker-compose.override.yaml"

# --- Helpers ---
log() { echo -e "\e[34m[*]\e[0m $1"; }
ok()  { echo -e "\e[32m[+]\e[0m $1"; }
err() { echo -e "\e[31m[-]\e[0m $1" >&2; exit 1; }

COMPOSE_URL="https://docs.goauthentik.io/compose.yml"
ADMIN_EMAIL="admin@localhost"
ADMIN_PASS="password"

# 1. Fetch compose manifest if not present (re-run reset.sh to force re-fetch)
if [ ! -f docker-compose.yaml ]; then
    log "Fetching compose manifest..."
    curl -sL "$COMPOSE_URL" -o docker-compose.yaml
fi

# 2. Generate .env if not present (re-run reset.sh to clear secrets)
if [ ! -f .env ]; then
    log "Generating fresh secrets..."
    cat <<EOF > .env
PG_PASS="$(openssl rand -base64 36)"
AUTHENTIK_SECRET_KEY="$(openssl rand -base64 60)"
AUTHENTIK_BOOTSTRAP_PASSWORD="${ADMIN_PASS}"
AUTHENTIK_BOOTSTRAP_EMAIL="${ADMIN_EMAIL}"

# Performance & Privacy Tuning
AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true
AUTHENTIK_DISABLE_UPDATE_CHECK=true
AUTHENTIK_ERROR_REPORTING__ENABLED=false
AUTHENTIK_OUTPOSTS__DISCOVER=false
AUTHENTIK_WORKER__THREADS=2
EOF
fi

log "Starting containers..."
$DC up -d

# 4. Wait for all containers to be healthy
log "Waiting for containers to become healthy..."
TIMEOUT=600
ELAPSED=0
until $DC ps --format json \
    | jq -s 'flatten | map(select(.Health == "healthy")) | length' \
    | grep -q "^$($DC ps --format json | jq -s 'flatten | length')$"; do
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo ""
        err "Timeout waiting for healthy containers."
    fi
    echo -n "."; sleep 5; ((ELAPSED+=5))
done
echo ""

# # 5. Hand off to provisioner
# log "Handing off to provisioner..."
bash provision.sh
