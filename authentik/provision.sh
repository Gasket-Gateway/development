#!/bin/bash

API_URL="http://localhost:9000/api/v3"
HEALTH_URL="http://localhost:9000/-/health/live/"

# --- Helpers ---
log() { echo -e "\e[34m[*]\e[0m $1"; }
ok()  { echo -e "\e[32m[+]\e[0m $1"; }
err() { 
    echo -e "\e[31m[-]\e[0m $1" >&2
    exit 1 
}

api_call() {
    local method=$1 endpoint=$2; shift 2
    # Note the trailing slash on the endpoint
    curl -s -X "$method" "${API_URL}/${endpoint}/" \
        -H "$AUTH_HEADER" -H "Content-Type: application/json" "$@"
}

delete_resource() {
    local endpoint=$1 param=$2 val=$3
    log "Cleaning $endpoint ($val)..."
    local pk=$(api_call GET "$endpoint" | jq -r ".results[] | select(.$param == \"$val\") | .pk // empty")
    [[ -n "$pk" ]] && api_call DELETE "$endpoint/$pk" > /dev/null
}

# --- 1. Readiness & Auth ---
log "Waiting for Authentik Service..."
until curl -s -f "$HEALTH_URL" > /dev/null; do echo -n "."; sleep 2; done
echo ""

log "Waiting for database bootstrap..."
until docker compose exec -T postgresql psql -U authentik -d authentik -c "SELECT 1 FROM authentik_core_user WHERE username='akadmin';" | grep -q "1" &>/dev/null; do
    echo -n "."; sleep 2
done
echo ""

log "Provisioning API Token..."
RAW_OUTPUT=$(docker compose exec -T server python3 manage.py shell <<EOF
from authentik.core.models import Token, User
import secrets
user = User.objects.get(username='akadmin')
token, _ = Token.objects.update_or_create(
    identifier='dev-token', user=user,
    defaults={'intent': 'api', 'expiring': False, 'key': secrets.token_hex(64)}
)
print(token.key)
EOF
)
API_TOKEN=$(echo "$RAW_OUTPUT" | tail -n 1 | tr -d '\r\n ')
AUTH_HEADER="Authorization: Bearer $API_TOKEN"

# --- 2. Cleanup ---
for u in user1 user2 user3; do delete_resource "core/users" "username" "$u"; done
for g in gasket-users gasket-admins; do delete_resource "core/groups" "name" "$g"; done
delete_resource "providers/oauth2" "name" "gg-oidc-provider"
delete_resource "core/applications" "slug" "gasket-gateway"

# --- 3. Provisioning ---
log "Provisioning Users..."
for i in {1..3}; do
    api_call POST "core/users" -d "{
        \"username\": \"user$i\", \"name\": \"User $i\", 
        \"email\": \"user$i@localhost\", \"password\": \"password\", 
        \"type\": \"internal\", \"is_active\": true
    }" > /dev/null
done

log "Configuring Groups..."
for g in "users" "admins"; do
    group_name="gasket-$g"
    target_user="user$((g == "admins" ? 3 : 2))"
    
    group_pk=$(api_call POST "core/groups" -d "{\"name\": \"$group_name\"}" | jq -r '.pk')
    user_pk=$(api_call GET "core/users" | jq -r ".results[] | select(.username == \"$target_user\") | .pk")
    
    api_call POST "core/groups/$group_pk/add_user" -d "{\"pk\": $user_pk}" > /dev/null
    ok "Assigned $target_user to $group_name"
done

log "Configuring OIDC..."
FLOW_AUTH=$(api_call GET "flows/instances" | jq -r '.results[] | select(.slug == "default-authentication-flow") | .pk')
FLOW_AUTHZ=$(api_call GET "flows/instances" | jq -r '.results[] | select(.slug == "default-provider-authorization-explicit-consent") | .pk')
FLOW_INVAL=$(api_call GET "flows/instances" | jq -r '.results[] | select(.slug == "default-invalidation-flow") | .pk')

PROV_PK=$(api_call POST "providers/oauth2" -d "{
    \"name\": \"gg-oidc-provider\", \"client_id\": \"gg-client-id\", \"client_secret\": \"gg-client-secret\",
    \"authentication_flow\": \"$FLOW_AUTH\", \"authorization_flow\": \"$FLOW_AUTHZ\", \"invalidation_flow\": \"$FLOW_INVAL\",
    \"redirect_uris\": [{\"matching_mode\": \"strict\", \"url\": \"http://localhost:5000/auth/callback\"}],
    \"issuer_mode\": \"global\"
}" | jq -r '.pk')

log "Creating Application & Binding..."
api_call POST "core/applications" -d "{\"name\": \"Gasket Gateway\", \"slug\": \"gasket-gateway\"}" > /dev/null
api_call PATCH "core/applications/gasket-gateway" -d "{\"provider\": $PROV_PK}" > /dev/null

ok "Full stack provisioned. Gasket Gateway OIDC is live."
