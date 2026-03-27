#!/usr/bin/env bash
#
# Checkmarx One - CSV Report: Projects by Application
# Generates a CSV of projects for a given application with scan metadata.
# Usage: ./checkmarx.report.sh [-v|--verbose] [APPLICATION_NAME]
#        Defaults to "OneApp" if no argument is provided.
#
set -euo pipefail

# --- Load shared library ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Configuration ---
APP_NAME="${1:-OneApp}"
REPORT_DATE="$(date +%Y-%m-%d)"
OUTPUT_FILE="report_${APP_NAME}_${REPORT_DATE}.csv"

# --- Load environment ---
source "${SCRIPT_DIR}/.env"

# --- Validate required variables ---
for var in APIKEY TENANT BASE_URI; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: Required environment variable ${var} is not set or empty." >&2
    exit 1
  fi
done

# --- Derive URLs from BASE_URI ---
BASE="${BASE_URI%/}"
IAM_URL="${BASE/ast.checkmarx.net/iam.checkmarx.net}/auth/realms/${TENANT}/protocol/openid-connect/token"

cx_vlog "IAM_URL=${IAM_URL}"
cx_vlog "APP_NAME=${APP_NAME}"
cx_vlog "OUTPUT_FILE=${OUTPUT_FILE}"

# --- Step 1: Get access token via API Key ---
cx_log "Requesting access token for tenant: ${TENANT}..."

TOKEN_RESPONSE=$(cx_curl --silent --fail --request POST "${IAM_URL}" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --header 'Accept: application/json' \
  --data-urlencode "grant_type=refresh_token" \
  --data-urlencode "client_id=ast-app" \
  --data-urlencode "refresh_token=${APIKEY}")

ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.access_token')

if [ -z "${ACCESS_TOKEN}" ] || [ "${ACCESS_TOKEN}" = "null" ]; then
  echo "ERROR: Failed to obtain access token." >&2
  echo "Response: ${TOKEN_RESPONSE}" >&2
  exit 1
fi

EXPIRES_IN=$(echo "${TOKEN_RESPONSE}" | jq -r '.expires_in')
cx_log "Token obtained (expires in ${EXPIRES_IN}s)"

# --- Helper: authenticated GET request ---
cx_get() {
  local url="$1"
  cx_curl --silent --fail --request GET "${url}" \
    --header "Authorization: Bearer ${ACCESS_TOKEN}" \
    --header 'Accept: application/json; version=1.0'
}

# --- Step 2: Look up application to get project IDs ---
cx_log "Looking up application: ${APP_NAME}..."

APP_RESPONSE=$(cx_get "${BASE}/api/applications?name=${APP_NAME}&limit=100")

# Exact-match filter (the API name param may do substring matching)
APP_JSON=$(echo "${APP_RESPONSE}" | jq -e --arg name "${APP_NAME}" \
  '[.applications[] | select(.name == $name)] | if length == 0 then error("not found") else .[0] end') || {
  echo "ERROR: Application '${APP_NAME}' not found." >&2
  echo ">> Available applications:" >&2
  echo "${APP_RESPONSE}" | jq -r '.applications[]?.name // empty' >&2
  exit 1
}

PROJECT_IDS_JSON=$(echo "${APP_JSON}" | jq '.projectIds // []')
PROJECT_COUNT=$(echo "${PROJECT_IDS_JSON}" | jq 'length')

if [ "${PROJECT_COUNT}" -eq 0 ]; then
  echo "ERROR: Application '${APP_NAME}' has no associated projects." >&2
  exit 1
fi

cx_log "Found ${PROJECT_COUNT} project(s) in '${APP_NAME}'"

# --- Step 3: Fetch project details (paginated) ---
# Build ids query string: ids=uuid1&ids=uuid2&...
IDS_QUERY=$(echo "${PROJECT_IDS_JSON}" | jq -r '.[]' | while read -r pid; do
  printf "ids=%s&" "${pid}"
done)

cx_log "Fetching project details..."

ALL_PROJECTS="[]"
OFFSET=0
LIMIT=100

while true; do
  PAGE_RESPONSE=$(cx_get "${BASE}/api/projects?${IDS_QUERY}offset=${OFFSET}&limit=${LIMIT}")

  PAGE_PROJECTS=$(echo "${PAGE_RESPONSE}" | jq '.projects // []')
  PAGE_SIZE=$(echo "${PAGE_PROJECTS}" | jq 'length')

  ALL_PROJECTS=$(echo "${ALL_PROJECTS}" "${PAGE_PROJECTS}" | jq -s '.[0] + .[1]')

  FILTERED_TOTAL=$(echo "${PAGE_RESPONSE}" | jq '.filteredTotalCount // 0')

  OFFSET=$((OFFSET + LIMIT))
  if [ "${OFFSET}" -ge "${FILTERED_TOTAL}" ] || [ "${PAGE_SIZE}" -eq 0 ]; then
    break
  fi
done

TOTAL_FETCHED=$(echo "${ALL_PROJECTS}" | jq 'length')
cx_log "Fetched ${TOTAL_FETCHED} project(s)"

# --- Step 4: Fetch last scan date per project ---
cx_log "Fetching last scan dates..."

declare -A LAST_SCAN_MAP

while read -r pid; do
  SCAN_RESPONSE=$(cx_get "${BASE}/api/scans?project-id=${pid}&limit=1&sort=-createdAt&statuses=Completed" 2>/dev/null) || SCAN_RESPONSE='{"scans":[]}'

  LAST_SCAN_DATE=$(echo "${SCAN_RESPONSE}" | jq -r '
    if (.scans // []) | length > 0 then .scans[0].createdAt
    else "N/A"
    end
  ')

  LAST_SCAN_MAP["${pid}"]="${LAST_SCAN_DATE}"
  cx_vlog "Fetched scan date for project ${pid:0:8}..."
done < <(echo "${ALL_PROJECTS}" | jq -r '.[].id')

# --- Step 5: Generate CSV ---
cx_log "Generating CSV: ${OUTPUT_FILE}"

echo '"Project Name","Primary Branch","Scan Origin","Tags","Last Scan Date"' > "${OUTPUT_FILE}"

while read -r project_json; do
  NAME=$(echo "${project_json}" | jq -r '.name // "N/A"')
  BRANCH=$(echo "${project_json}" | jq -r '.mainBranch // "N/A"')
  ORIGIN=$(echo "${project_json}" | jq -r '.origin // "N/A"')

  TAGS=$(echo "${project_json}" | jq -r '
    .tags // {} | to_entries | map("\(.key):\(.value)") | join("; ")
  ')
  if [ -z "${TAGS}" ]; then
    TAGS=""
  fi

  PID=$(echo "${project_json}" | jq -r '.id')
  SCAN_DATE="${LAST_SCAN_MAP[${PID}]:-N/A}"

  # CSV-escape: double-quote fields, escape internal quotes per RFC 4180
  printf '"%s","%s","%s","%s","%s"\n' \
    "${NAME//\"/\"\"}" \
    "${BRANCH//\"/\"\"}" \
    "${ORIGIN//\"/\"\"}" \
    "${TAGS//\"/\"\"}" \
    "${SCAN_DATE//\"/\"\"}"
done < <(echo "${ALL_PROJECTS}" | jq -c '.[]') >> "${OUTPUT_FILE}"

cx_log "Done! Report saved to ${OUTPUT_FILE} (${TOTAL_FETCHED} projects)"
