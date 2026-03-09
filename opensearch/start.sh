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
