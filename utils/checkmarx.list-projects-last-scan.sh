#!/usr/bin/env bash
#
# checkmarx.list-projects-last-scan.sh
# =====================================
# List projects with their last scan information.
#
# Fetches project-level scan status from the Checkmarx One Projects API
# (GET /api/projects/last-scan) which returns the most recent scan info
# per project in a single call. This is far more efficient than looping
# over individual projects to fetch their last scan.
#
# Supports filtering by application, scan status, and per-engine status
# (SAST, SCA, KICS, API Security). Useful for project inventory reports.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/projects/last-scan
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Pagination: offset/limit
#   See also:   docs/rest-api-reference.md § 13.8
#
# Usage:
#   ./utils/checkmarx.list-projects-last-scan.sh [-v|--verbose] [OPTIONS]
#
# Options:
#   -v, --verbose         Print curl commands and derived URLs to stderr
#   --application-id ID   Filter by application UUID
#   --scan-status S       Filter by overall scan status (e.g., Completed, Failed)
#   --sast-status S       Filter by SAST engine status
#   --sca-status S        Filter by SCA engine status
#   --kics-status S       Filter by KICS engine status
#   --apisec-status S     Filter by API Security engine status
#   --branch B            Filter by branch name
#   --use-main-branch     Only include scans from the project's main branch
#   --limit N             Return at most N results (single page, no pagination)
#
# Output:
#   A JSON array of project objects with embedded last-scan info to stdout.
#   Each object includes project details plus the latest scan metadata
#   (scan ID, status, engines, dates, per-engine status).
#
# Examples:
#   ./utils/checkmarx.list-projects-last-scan.sh
#   ./utils/checkmarx.list-projects-last-scan.sh --application-id "uuid"
#   ./utils/checkmarx.list-projects-last-scan.sh --scan-status Completed --use-main-branch
#   ./utils/checkmarx.list-projects-last-scan.sh --sast-status Completed --limit 20
#   ./utils/checkmarx.list-projects-last-scan.sh | jq '.[].name'
#
# Composability:
#   # Get all projects for an app with their last scan status
#   APP_ID=$(./utils/checkmarx.list-applications.sh --name "MyApp" | jq -r '.[0].id')
#   ./utils/checkmarx.list-projects-last-scan.sh --application-id "$APP_ID"
#
# Exit codes:
#   0  Success
#   1  Bad flag or API error
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
APPLICATION_ID=""
SCAN_STATUS=""
SAST_STATUS=""
SCA_STATUS=""
KICS_STATUS=""
APISEC_STATUS=""
BRANCH=""
USE_MAIN_BRANCH=0
LIMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --application-id) APPLICATION_ID="$2"; shift 2 ;;
    --scan-status)    SCAN_STATUS="$2"; shift 2 ;;
    --sast-status)    SAST_STATUS="$2"; shift 2 ;;
    --sca-status)     SCA_STATUS="$2"; shift 2 ;;
    --kics-status)    KICS_STATUS="$2"; shift 2 ;;
    --apisec-status)  APISEC_STATUS="$2"; shift 2 ;;
    --branch)         BRANCH="$2"; shift 2 ;;
    --use-main-branch) USE_MAIN_BRANCH=1; shift ;;
    --limit)          LIMIT="$2"; shift 2 ;;
    *)                echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build query string ---
PARAMS=()
[ -n "${APPLICATION_ID}" ] && PARAMS+=("application_id=${APPLICATION_ID}")
[ -n "${SCAN_STATUS}" ]    && PARAMS+=("scan_status=${SCAN_STATUS}")
[ -n "${SAST_STATUS}" ]    && PARAMS+=("sast_status=${SAST_STATUS}")
[ -n "${SCA_STATUS}" ]     && PARAMS+=("sca_status=${SCA_STATUS}")
[ -n "${KICS_STATUS}" ]    && PARAMS+=("kics_status=${KICS_STATUS}")
[ -n "${APISEC_STATUS}" ]  && PARAMS+=("apisec_status=${APISEC_STATUS}")
[ -n "${BRANCH}" ]         && PARAMS+=("branch=$(cx_urlencode "${BRANCH}")")
[ "${USE_MAIN_BRANCH}" -eq 1 ] && PARAMS+=("use_main_branch=true")

URL="${BASE}/api/projects/last-scan"
if [ ${#PARAMS[@]} -gt 0 ]; then
  QUERY=$(IFS='&'; echo "${PARAMS[*]}")
  URL="${URL}?${QUERY}"
fi

# --- Determine URL separator ---
SEP="?"
[[ "${URL}" == *"?"* ]] && SEP="&"

# --- Fetch and output ---
if [ -n "${LIMIT}" ]; then
  RESPONSE=$(cx_get "${URL}${SEP}offset=0&limit=${LIMIT}")
  echo "${RESPONSE}" | jq 'if type == "array" then . elif .projects then .projects elif .items then .items else [.] end'
else
  # Probe the response shape, then paginate with the correct array key
  RESPONSE=$(cx_get "${URL}${SEP}offset=0&limit=100")
  if echo "${RESPONSE}" | jq -e 'type == "array"' > /dev/null 2>&1; then
    echo "${RESPONSE}"
  elif echo "${RESPONSE}" | jq -e '.projects' > /dev/null 2>&1; then
    cx_paginate "${URL}" "projects"
  elif echo "${RESPONSE}" | jq -e '.items' > /dev/null 2>&1; then
    cx_paginate "${URL}" "items"
  else
    echo "${RESPONSE}" | jq '.'
  fi
fi
