#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\e[34m[*]\e[0m $1"; }
ok()  { echo -e "\e[32m[+]\e[0m $1"; }
err() { echo -e "\e[31m[-]\e[0m $1" >&2; exit 1; }

# ─── Pre-flight: sysctl checks ───────────────────────────────────────────────
# OpenSearch requires vm.max_map_count >= 262144.
# Without this, the OpenSearch node will refuse to start.
MIN_MAP_COUNT=262144
CURRENT_MAP_COUNT=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)

echo ""
echo "══════════════════════════════════════"
echo "  Pre-flight: sysctl checks"
echo "══════════════════════════════════════"

if [[ "$CURRENT_MAP_COUNT" -ge "$MIN_MAP_COUNT" ]]; then
  ok "  vm.max_map_count = ${CURRENT_MAP_COUNT} (>= ${MIN_MAP_COUNT})"
else
  echo "  ✗  vm.max_map_count = ${CURRENT_MAP_COUNT} (need >= ${MIN_MAP_COUNT})"
  echo ""
  echo "  Fix (current session only):"
  echo "    sudo sysctl -w vm.max_map_count=${MIN_MAP_COUNT}"
  echo ""
  echo "  Fix (persistent across reboots) — add to /etc/sysctl.conf:"
  echo "    vm.max_map_count=${MIN_MAP_COUNT}"
  echo ""
  err "sysctl pre-flight failed. OpenSearch will not start without this."
fi

echo "══════════════════════════════════════"

log "Starting OpenSearch and Dashboards ..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" up -d

DASHBOARDS_URL="http://localhost:5601"

# ─── Wait for Dashboards to be ready ─────────────────────────────────────────
log "Waiting for OpenSearch Dashboards to be ready ..."
until curl -s -f "${DASHBOARDS_URL}/api/status" &>/dev/null; do
    echo -n "."; sleep 2
done
echo ""
ok "Dashboards is ready."

# ─── Create index patterns ───────────────────────────────────────────────────
log "Provisioning index patterns ..."

INDEX_PATTERNS=(
    "gg-audit-*"
)

for pattern in "${INDEX_PATTERNS[@]}"; do
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${DASHBOARDS_URL}/api/saved_objects/index-pattern/${pattern}" \
        -H "osd-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{
            \"attributes\": {
                \"title\": \"${pattern}\",
                \"timeFieldName\": \"@timestamp\"
            }
        }" 2>/dev/null)
    if [[ "$response" == "200" || "$response" == "409" ]]; then
        ok "  ✓ ${pattern}"
    else
        err "  Failed to create index pattern '${pattern}' (HTTP ${response})"
    fi
done

