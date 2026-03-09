#!/usr/bin/env bash
set -euo pipefail
# Reset all stateful services (wipes volumes, secrets, and downloaded manifests).
# Run this before start-all.sh to get a completely fresh environment.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_reset() {
    local label="$1"
    local dir="$2"
    echo ""
    echo "══════════════════════════════════════"
    echo "  Resetting: ${label}"
    echo "══════════════════════════════════════"
    bash "${SCRIPT_DIR}/${dir}/reset.sh"
}

run_reset "Authentik"  authentik
run_reset "OpenSearch" opensearch
run_reset "Prometheus" prometheus
run_reset "Grafana"    grafana

echo ""
echo "══════════════════════════════════════"
echo "  All stateful services reset."
echo "  Run start-all.sh to bring everything up fresh."
echo "══════════════════════════════════════"
