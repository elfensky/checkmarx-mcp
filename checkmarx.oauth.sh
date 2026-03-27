#!/usr/bin/env bash
#
# Checkmarx One API - OAuth2 client credentials flow
# Authenticates using Client ID + Secret and lists projects.
# Usage: ./checkmarx.oauth.sh [-v|--verbose]
#
set -euo pipefail

# --- Load shared library and environment ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

source "${SCRIPT_DIR}/.env"

# --- Validate required variables ---
for var in CLIENT_ID CLIENT_SECRET TENANT BASE_URI; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: Required environment variable ${var} is not set or empty." >&2
    exit 1
  fi
done

# --- Derive URLs from BASE_URI ---
# Strip trailing slash, replace ast → iam, append token path
BASE="${BASE_URI%/}"
IAM_URL="${BASE/ast.checkmarx.net/iam.checkmarx.net}/auth/realms/${TENANT}/protocol/openid-connect/token"
API_URL="${BASE}/api/projects"

cx_vlog "IAM_URL=${IAM_URL}"
cx_vlog "API_URL=${API_URL}"

# --- Step 1: Get access token via OAuth2 client credentials ---
cx_log "Requesting access token for tenant: ${TENANT} (OAuth2 flow)..."

TOKEN_RESPONSE=$(cx_curl --silent --fail --request POST "${IAM_URL}" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --header 'Accept: application/json' \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}")

ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.access_token')

if [ -z "${ACCESS_TOKEN}" ] || [ "${ACCESS_TOKEN}" = "null" ]; then
  echo "ERROR: Failed to obtain access token." >&2
  echo "Response: ${TOKEN_RESPONSE}" >&2
  exit 1
fi

EXPIRES_IN=$(echo "${TOKEN_RESPONSE}" | jq -r '.expires_in')
cx_log "Token obtained successfully (expires in ${EXPIRES_IN}s)"

# --- Step 2: List projects ---
echo ""
cx_log "Fetching projects..."

PROJECTS_RESPONSE=$(cx_curl --silent --fail --request GET "${API_URL}?offset=0&limit=20" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header 'Accept: application/json; version=1.0')

TOTAL=$(echo "${PROJECTS_RESPONSE}" | jq -r '.totalCount // .filteredTotalCount // "unknown"')
cx_log "Total projects: ${TOTAL}"
echo ""

# Pretty-print project names and IDs
if echo "${PROJECTS_RESPONSE}" | jq -e '.projects' > /dev/null 2>&1; then
  echo "${PROJECTS_RESPONSE}" | jq -r '.projects[] | "  \(.name)  (\(.id))"'
else
  # Unknown structure — dump raw JSON for inspection
  cx_log "Raw response:"
  echo "${PROJECTS_RESPONSE}" | jq .
fi
