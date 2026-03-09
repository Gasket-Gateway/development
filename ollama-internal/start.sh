#!/usr/bin/env bash
set -euo pipefail

# Default to 'mistral' if no argument is provided
MODEL="gemma3n:e2b"
ENDPOINT="http://localhost:11434"

echo "[*] Starting Ollama container..."
docker compose up -d

echo "[*] Waiting for the Ollama API to become responsive..."
# Poll the tags endpoint until it returns a successful HTTP status
until curl -s -o /dev/null -w "%{http_code}" "${ENDPOINT}/api/tags" | grep -q "200"; do
  sleep 2
done

echo "[*] API is up. Pulling model: ${MODEL}..."
# Execute the pull command directly inside the container
docker compose exec ollama ollama pull "${MODEL}"

echo "[+] Setup complete. The model '${MODEL}' is ready."
