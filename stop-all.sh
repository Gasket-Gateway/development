#!/usr/bin/env bash
set -euo pipefail
# Stop all development environment services (reverse startup order).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() {
  local label="$1"
  local dir="$2"
  echo ""
  echo "══════════════════════════════════════"
  echo "  Stopping: ${label}"
  echo "══════════════════════════════════════"
  bash "${SCRIPT_DIR}/${dir}/stop.sh"
}

# Stop in reverse startup order
run "Code Server 3 (user3)" code-server-3
run "Code Server 2 (user2)" code-server-2
run "Code Server 1 (user1)" code-server-1
run "Open WebUI"        open-webui
run "Ollama (internal)" ollama-internal
run "Ollama (external)" ollama-external
run "Grafana"           grafana
run "Prometheus"        prometheus
run "OpenSearch"        opensearch
run "Authentik"         authentik
run "Traefik"           traefik

echo ""
echo "══════════════════════════════════════"
echo "  All services stopped."
echo "  (gasket-portal must be stopped separately)"
echo "══════════════════════════════════════"
