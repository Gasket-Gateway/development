#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_MODEL="granite4:350m"

echo "[ollama-internal] Starting Ollama (internal) ..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" up -d

echo "[ollama-internal] Waiting for Ollama to be ready ..."
until docker exec ollama-internal ollama list &>/dev/null; do
    sleep 1
done

echo "[ollama-internal] Pulling model: ${DEFAULT_MODEL} ..."
docker exec ollama-internal ollama pull "${DEFAULT_MODEL}"
echo "[ollama-internal] Model ${DEFAULT_MODEL} ready."
