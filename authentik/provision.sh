#!/bin/bash
set -e

API_URL="http://localhost:9000/api/v3"
HEALTH_URL="http://localhost:9000/-/health/live/"

# --- Helpers ---
log() { echo -e "\e[34m[*]\e[0m $1"; }
ok()  { echo -e "\e[32m[+]\e[0m $1"; }
err() { echo -e "\e[31m[-]\e[0m $1" >&2; exit 1; }

api_call() {
    local method=$1 endpoint=$2; shift 2
    curl -s -X "$method" "${API_URL}/${endpoint}/" \
        -H "$AUTH_HEADER" -H "Content-Type: application/json" "$@"
}

# Poll endpoint until the given pk appears (for propagation checks)
# $1 endpoint  $2 pk
wait_for_pk() {
    local endpoint="$1" pk="$2"
    local attempts=0
    until curl -s "${API_URL}/${endpoint}/${pk}/" -H "$AUTH_HEADER" \
            | jq -e '.pk' &>/dev/null; do
        ((attempts++)) || true
        [[ $attempts -ge 15 ]] && err "  Timed out waiting for ${endpoint}/${pk} to be ready"
        sleep 2
    done
}

# Bulk-delete all resources matching an optional jq filter on the .pk field.
# Loops until the endpoint returns nothing — Authentik deletes some resources
# asynchronously (e.g. applications with bound providers) so a single pass isn't enough.
# $1 label  $2 endpoint  $3 jq filter (default: .pk)
bulk_delete() {
    local label="$1" endpoint="$2" filter="${3:-.pk}"
    log "  Purging ${label}..."
    local total=0 round=0 pks count
    while true; do
        ((round++)) || true
        [[ $round -gt 10 ]] && err "  bulk_delete: gave up purging ${label} after 10 rounds"
        pks=$(curl -s "${API_URL}/${endpoint}/?page_size=200" \
            -H "$AUTH_HEADER" | jq -r ".results[] | ${filter}")
        count=0
        while IFS= read -r pk; do
            [[ -z "$pk" ]] && continue
            curl -s -X DELETE "${API_URL}/${endpoint}/${pk}/" -H "$AUTH_HEADER" > /dev/null
            ((count++)) || true
        done <<< "$pks"
        ((total += count)) || true
        [[ $count -eq 0 ]] && break   # nothing left to delete
        sleep 2                        # give Authentik time to propagate async deletions
    done
    ok "  Removed ${total} ${label} (${round} round(s))."
}

# Create an OAuth2 provider, return its pk
# Uses SIGNING_KEY_UUID (RS256) and SCOPE_MAPPING_UUIDS (openid+email+profile) set after auth
create_provider() {
    local slug="$1" client_id="$2" client_secret="$3" redirect_uri="$4"
    local response pk
    response=$(api_call POST "providers/oauth2" -d "{
        \"name\": \"${slug}-provider\",
        \"client_id\": \"${client_id}\",
        \"client_secret\": \"${client_secret}\",
        \"authentication_flow\": \"${FLOW_AUTH}\",
        \"authorization_flow\": \"${FLOW_AUTHZ}\",
        \"invalidation_flow\": \"${FLOW_INVAL}\",
        \"redirect_uris\": [{\"matching_mode\": \"strict\", \"url\": \"${redirect_uri}\"}],
        \"issuer_mode\": \"per_provider\",
        \"signing_key\": \"${SIGNING_KEY_UUID}\",
        \"property_mappings\": ${SCOPE_MAPPING_UUIDS}
    }")
    pk=$(echo "$response" | jq -r '.pk')
    [[ -z "$pk" || "$pk" == "null" ]] && err "  Failed to create provider '${slug}': $(echo "$response" | jq -c .)"
    wait_for_pk "providers/oauth2" "$pk"
    echo "$pk"
}

# Create an application bound to a provider, return its pk (UUID)
# Retries on transient slug-conflict after bulk_delete hasn't fully propagated
create_application() {
    local name="$1" slug="$2" prov_pk="$3"
    local attempts=0 response pk
    until response=$(api_call POST "core/applications" -d "{
        \"name\": \"${name}\",
        \"slug\": \"${slug}\",
        \"provider\": ${prov_pk}
    }") && pk=$(echo "$response" | jq -r '.pk') && [[ -n "$pk" && "$pk" != "null" ]]; do
        ((attempts++)) || true
        [[ $attempts -ge 10 ]] && err "  Failed to create application '${name}' after ${attempts} attempts: ${response}"
        sleep 2
    done
    echo "$pk"
}

# Bind an application to a group (UUID pk) — retries on transient failure
bind_group() {
    local app_pk="$1" group_pk="$2"
    local attempts=0 result
    until result=$(api_call POST "policies/bindings" -d "{
        \"target\": \"${app_pk}\",
        \"group\": \"${group_pk}\",
        \"order\": 0, \"enabled\": true
    }") && echo "$result" | jq -e '.pk' &>/dev/null; do
        ((attempts++)) || true
        [[ $attempts -ge 5 ]] && err "  bind_group failed after ${attempts} attempts (app=${app_pk} group=${group_pk}): ${result}"
        sleep 2
    done
}

# Bind an application to a specific user (integer pk) — retries on transient failure
bind_user() {
    local app_pk="$1" user_pk="$2"
    local attempts=0 result
    until result=$(api_call POST "policies/bindings" -d "{
        \"target\": \"${app_pk}\",
        \"user\": ${user_pk},
        \"order\": 0, \"enabled\": true
    }") && echo "$result" | jq -e '.pk' &>/dev/null; do
        ((attempts++)) || true
        [[ $attempts -ge 5 ]] && err "  bind_user failed after ${attempts} attempts (app=${app_pk} user=${user_pk}): ${result}"
        sleep 2
    done
}

# Convenience: create provider + app + group binding
create_oidc_app_group() {
    local name="$1" slug="$2" client_id="$3" client_secret="$4" redirect_uri="$5" group_pk="$6"
    log "  Creating $name ..."
    local prov_pk app_pk
    prov_pk=$(create_provider "$slug" "$client_id" "$client_secret" "$redirect_uri")
    app_pk=$(create_application "$name" "$slug" "$prov_pk")
    bind_group "$app_pk" "$group_pk"
    ok "  ✓ $name → group binding"
}

# ─── 1. Readiness & Auth ──────────────────────────────────────────────────────

log "Waiting for Authentik to become healthy..."
until curl -s -f "$HEALTH_URL" > /dev/null; do echo -n "."; sleep 2; done
echo ""

log "Waiting for akadmin to be bootstrapped..."
until docker compose exec -T postgresql \
    psql -U authentik -d authentik \
    -c "SELECT 1 FROM authentik_core_user WHERE username='akadmin';" \
    | grep -q "1" &>/dev/null; do
    echo -n "."; sleep 2
done
echo ""

log "Provisioning API token..."
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

# ─── 2. Cleanup ───────────────────────────────────────────────────────────────

log "Purging existing provisioning state..."
# Deletion order matters — Authentik won't fully process app deletes while bindings still exist,
# and providers can't be cleaned up while applications reference them.
# 1. Policy bindings targeting applications (group/user→app mappings only)
# Our bindings always have group or user set; system flow/stage bindings have both null
bulk_delete "policy bindings" "policies/bindings" 'select(.group != null or .user != null) | .pk'
# 2. Applications (reference providers via FK)
bulk_delete "applications"    "core/applications"   '.slug'
# 3. OAuth2 providers (now unreferenced)
bulk_delete "OAuth2 providers" "providers/oauth2"   '.pk'
# 4. Internal users (except akadmin)
bulk_delete "users"           "core/users"          'select(.username != "akadmin" and .type == "internal") | .pk'
# 5. Custom groups (preserve built-in Authentik groups)
bulk_delete "groups"          "core/groups"         'select(.name | IN("authentik Admins","authentik Read-only") | not) | .pk'

# ─── 3. Users ────────────────────────────────────────────────────────────────

log "Provisioning test users..."
for i in {1..3}; do
    user_pk=$(api_call POST "core/users" -d "{
        \"username\": \"user$i\", \"name\": \"User $i\",
        \"email\": \"user$i@localhost\",
        \"type\": \"internal\", \"is_active\": true
    }" | jq -r '.pk')
    [[ -z "$user_pk" || "$user_pk" == "null" ]] && err "  Failed to create user$i"
    api_call POST "core/users/$user_pk/set_password" \
        -d "{\"password\": \"password\"}" > /dev/null
    ok "  user$i (password: password)"
done

# Grab user PKs (integer) for later use
USER1_PK=$(api_call GET "core/users" | jq -r '.results[] | select(.username == "user1") | .pk')
USER2_PK=$(api_call GET "core/users" | jq -r '.results[] | select(.username == "user2") | .pk')
USER3_PK=$(api_call GET "core/users" | jq -r '.results[] | select(.username == "user3") | .pk')

# ─── 4. Groups ───────────────────────────────────────────────────────────────

log "Configuring groups..."

# test-users: all 3 users — code-server + open-webui access
TEST_USERS_PK=$(api_call POST "core/groups" -d '{"name": "test-users"}' | jq -r '.pk')
for pk in "$USER1_PK" "$USER2_PK" "$USER3_PK"; do
    api_call POST "core/groups/$TEST_USERS_PK/add_user" -d "{\"pk\": $pk}" > /dev/null
done
ok "  test-users: user1, user2, user3"

# gasket-users: user2 + user3 (NOT user1 — intentional for negative testing)
USERS_GROUP_PK=$(api_call POST "core/groups" -d '{"name": "gasket-users"}' | jq -r '.pk')
for pk in "$USER2_PK" "$USER3_PK"; do
    api_call POST "core/groups/$USERS_GROUP_PK/add_user" -d "{\"pk\": $pk}" > /dev/null
done
ok "  gasket-users: user2, user3 (user1 excluded for negative testing)"

# gasket-admins: user3 only
ADMINS_GROUP_PK=$(api_call POST "core/groups" -d '{"name": "gasket-admins"}' | jq -r '.pk')
api_call POST "core/groups/$ADMINS_GROUP_PK/add_user" -d "{\"pk\": $USER3_PK}" > /dev/null
ok "  gasket-admins: user3"

# ─── 5. Flows ────────────────────────────────────────────────────────────────

log "Fetching default flows..."
FLOW_AUTH=$(api_call GET "flows/instances" \
    | jq -r '.results[] | select(.slug == "default-authentication-flow") | .pk')
FLOW_AUTHZ=$(api_call GET "flows/instances" \
    | jq -r '.results[] | select(.slug == "default-provider-authorization-explicit-consent") | .pk')
FLOW_INVAL=$(api_call GET "flows/instances" \
    | jq -r '.results[] | select(.slug == "default-invalidation-flow") | .pk')

log "Fetching RS256 signing certificate..."
# Authentik uses its self-signed cert for RS256; signing_key=null means HS256, so we must set it explicitly
SIGNING_KEY_UUID=$(api_call GET "crypto/certificatekeypairs" \
    | jq -r '.results[] | select(.private_key_available == true) | .pk' | head -1)
[[ -z "$SIGNING_KEY_UUID" || "$SIGNING_KEY_UUID" == "null" ]] && err "No signing certificate with private key found in Authentik"
ok "  Signing cert: ${SIGNING_KEY_UUID}"

log "Fetching openid/email/profile/groups scope mappings..."
# propertymappings/scope/ was removed in Authentik 2026.2; use /all/ and filter by managed key
# scope_name field no longer exists — scopes are identified by their goauthentik.io managed key
SCOPE_MAPPING_UUIDS=$(api_call GET "propertymappings/all" \
    | jq -c '[.results[] | select(
        .managed == "goauthentik.io/providers/oauth2/scope-openid" or
        .managed == "goauthentik.io/providers/oauth2/scope-email" or
        .managed == "goauthentik.io/providers/oauth2/scope-profile" or
        .managed == "goauthentik.io/providers/oauth2/scope-entitlements"
      ) | .pk]')
[[ -z "$SCOPE_MAPPING_UUIDS" || "$SCOPE_MAPPING_UUIDS" == "null" || "$SCOPE_MAPPING_UUIDS" == "[]" ]] \
    && err "Could not find openid/email/profile/groups scope mappings"
ok "  Scope mappings: ${SCOPE_MAPPING_UUIDS}"

# Patch the email scope mapping to return email_verified=True
# The built-in expression hardcodes False — oauth2-proxy rejects tokens with email_verified=false
# The /propertymappings/all/ PATCH endpoint doesn't expose expression (polymorphic serializer),
# so we patch it directly via the Django ORM.
docker compose exec -T server python3 manage.py shell <<'PYEOF' > /dev/null
from authentik.providers.oauth2.models import ScopeMapping
sm = ScopeMapping.objects.filter(managed='goauthentik.io/providers/oauth2/scope-email').first()
if sm:
    sm.expression = 'return {\n    "email": request.user.email,\n    "email_verified": True\n}'
    sm.save()
PYEOF
ok "  Patched email scope mapping: email_verified=True"

# ─── 6. OIDC Applications ────────────────────────────────────────────────────

log "Provisioning OIDC applications..."

# Gasket Gateway — gasket-users (user2, user3)
# Credentials match gasket-portal/.env
create_oidc_app_group \
    "Gasket Gateway" "gasket-gateway" \
    "gg-client-id" "gg-client-secret" \
    "https://portal.gasket-dev.local/auth/callback" \
    "$USERS_GROUP_PK"

# Open WebUI — test-users (all 3 users)
# Credentials match open-webui/.env
create_oidc_app_group \
    "Open WebUI" "open-webui" \
    "open-webui-client-id" "open-webui-client-secret" \
    "https://open-webui.gasket-dev.local/oauth/oidc/callback" \
    "$TEST_USERS_PK"

# ─── Done ────────────────────────────────────────────────────────────────────

echo ""
ok "════════════════════════════════════════════"
ok "  Authentik provisioning complete."
ok ""
ok "  Test accounts (password: password):"
ok "    user1  → test-users only (negative test: no gasket-gateway access)"
ok "    user2  → test-users + gasket-users"
ok "    user3  → test-users + gasket-users + gasket-admins"
ok ""
ok "  App access:"
ok "    Gasket Gateway       → gasket-users  (user2, user3)"
ok "    Open WebUI           → test-users    (user1, user2, user3)"
ok "════════════════════════════════════════════"
