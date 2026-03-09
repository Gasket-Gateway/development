#!/bin/bash
set -e # Exit on error

# --- Helpers ---
log() { echo -e "\e[34m[*]\e[0m $1"; }
ok()  { echo -e "\e[32m[+]\e[0m $1"; }
err() { 
    echo -e "\e[31m[-]\e[0m $1" >&2
    exit 1 
}

# Configuration
COMPOSE_URL="https://docs.goauthentik.io/compose.yml"
ADMIN_EMAIL="admin@localhost"
ADMIN_PASS="password"

# 1. Manifest Management
if [ ! -f docker-compose.yaml ]; then
    log "Fetching compose manifest..."
    curl -sL "$COMPOSE_URL" -o docker-compose.yaml
fi

# 2. State Reset (Volumes and local mounts)
log "Resetting local state..."
docker compose down -v --remove-orphans &>/dev/null
rm -rf ./data ./certs ./custom-templates

# 3. Environment Preparation
# Using -n to avoid overwriting secrets if you manually edit .env later
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

# 4. Container Lifecycle
log "Orchestrating containers (Pulling & Starting)..."
docker compose pull -q # -q keeps the pull logs clean
docker compose up -d

log "Waiting for services to pass health checks..."
TIMEOUT=600
ELAPSED=0

until docker compose ps --format json | jq -s 'flatten | map(select(.Health == "healthy")) | length' | grep -q "^$(docker compose ps --format json | jq -s 'flatten | length')$"; do
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo ""
        err "Timeout reached. Some containers failed to become healthy."
    fi
    echo -n "."
    sleep 5
    ((ELAPSED+=5))
done

echo ""

# 5. Readiness Handover
log "Handing off to provisioner..."
bash provision.sh
