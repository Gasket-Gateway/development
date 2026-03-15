#!/usr/bin/env bash
set -euo pipefail
# Start all development environment services in dependency order.
# The Gasket portal (gasket-portal/) must have the 'gasket:dev' image built
# from the gasket repo before its start.sh will succeed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() {
  local label="$1"
  local dir="$2"
  echo ""
  echo "══════════════════════════════════════"
  echo "  Starting: ${label}"
  echo "══════════════════════════════════════"
  bash "${SCRIPT_DIR}/${dir}/start.sh"
}

# ─── Pre-flight: DNS check ───────────────────────────────────────────────────
preflight_dns() {
  local hosts=(
    portal.gasket-dev.local
    api.gasket-dev.local
    metrics.gasket-dev.local
    traefik.gasket-dev.local
    traefik-metrics.gasket-dev.local
    authentik.gasket-dev.local
    authentik-metrics.gasket-dev.local
    opensearch.gasket-dev.local
    opensearch-dashboard.gasket-dev.local
    prometheus.gasket-dev.local
    grafana.gasket-dev.local
    open-webui.gasket-dev.local
    ollama-external.gasket-dev.local
    ollama-internal.gasket-dev.local
  )

  local failed=()
  echo ""
  echo "══════════════════════════════════════"
  echo "  Pre-flight: DNS checks"
  echo "══════════════════════════════════════"
  for host in "${hosts[@]}"; do
    local resolved
    resolved=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | head -1) || true
    if [[ "$resolved" == "127.0.0.1" ]]; then
      echo "  ✓  $host → 127.0.0.1"
    else
      echo "  ✗  $host → ${resolved:-<not found>}"
      failed+=("$host")
    fi
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    echo ""
    echo "  DNS pre-flight FAILED. Add the following to /etc/hosts:"
    echo ""
    for host in "${failed[@]}"; do
      echo "    127.0.0.1  $host"
    done
    echo ""
    exit 1
  fi
  echo "  All DNS records OK."
  echo "══════════════════════════════════════"
}

preflight_dns

# 1. Traefik — must come first; handles TLS termination and hostname routing for all services
run "Traefik"           traefik

# 2. Authentik — OIDC provider; other services depend on it for auth
run "Authentik"         authentik

# 3. OpenSearch — audit log backend
run "OpenSearch"        opensearch

# 4. Prometheus + Grafana — metrics
run "Prometheus"        prometheus
run "Grafana"           grafana

# 5. Ollama instances — OpenAI-compatible backends
run "Ollama (external)" ollama-external
run "Ollama (internal)" ollama-internal

# 6. Open WebUI — uses Gasket as its OpenAI backend
run "Open WebUI"        open-webui

echo ""
echo "══════════════════════════════════════"
echo "  All supporting services started."
echo "══════════════════════════════════════"
