#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_MODEL="gemma3:270m"

echo "[ollama-external] Starting Ollama (external) ..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" up -d

echo "[ollama-external] Waiting for Ollama to be ready ..."
until docker exec ollama-external ollama list &>/dev/null; do
    sleep 1
done

echo "[ollama-external] Pulling model: ${DEFAULT_MODEL} ..."
docker exec ollama-external ollama pull "${DEFAULT_MODEL}"
echo "[ollama-external] Model ${DEFAULT_MODEL} ready."
