#!/usr/bin/env bash
set -e

ENV_FILE=".env"

# Ensure the .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating $ENV_FILE template..."
    cat <<EOF > "$ENV_FILE"
# Core Security
WEBUI_SECRET_KEY=$(openssl rand -base64 32)

# OIDC Configuration
ENABLE_OAUTH_SIGNUP=true
OAUTH_CLIENT_ID=your_client_id_here
OAUTH_CLIENT_SECRET=your_client_secret_here
OPENID_PROVIDER_URL=https://your-idp.com/application/o/tenant/.well-known/openid-configuration
OAUTH_PROVIDER_NAME=OIDC
OAUTH_SCOPES=openid email profile
EOF
fi

# Deploy the container stack
echo "Deploying Open WebUI..."
docker compose up -d

echo "Deployment complete. Open WebUI is running."
