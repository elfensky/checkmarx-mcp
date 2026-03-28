#!/usr/bin/env bash
#
# checkmarx.list-sast-results.sh
# ===============================
# List SAST-specific scan results with rich filtering.
#
# Queries the Checkmarx One SAST Results API (GET /api/sast-results)
# which provides richer filtering than the generic /api/results endpoint:
# filter by query name, language, CWE ID, source/sink files, compliance
# framework, and category. Also supports applying triage predicates.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/sast-results
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Pagination: offset/limit with totalCount
#   See also:   docs/rest-api-reference.md § 7 (SAST Results API)
#
# Usage:
#   ./utils/checkmarx.list-sast-results.sh [-v|--verbose] --scan-id ID [OPTIONS]
#
# Required:
#   --scan-id ID           UUID of the scan
#
# Options:
#   -v, --verbose          Print curl commands and derived URLs to stderr
#   --severity S           Comma-separated severity filter (CRITICAL, HIGH, MEDIUM, LOW, INFO)
#   --status S             Comma-separated status filter (NEW, RECURRENT)
#   --state S              Comma-separated state filter (TO_VERIFY, NOT_EXPLOITABLE, etc.)
#   --query Q              Filter by query name (substring)
#   --language L           Comma-separated language filter
#   --cwe-id ID            Filter by CWE ID
#   --source-file F        Filter by source file path
#   --sink-file F          Filter by sink file path
#   --compliance C         Filter by compliance framework
#   --category C           Filter by category
#   --apply-predicates B   Apply triage predicates (true/false, default: true)
#   --include-nodes        Include source/sink node details in results
#   --limit N              Return at most N results (single page, no pagination)
#
# Output:
#   A JSON array of SAST result objects to stdout. Each object includes
#   query name, language, severity, status, state, source/sink locations,
#   CWE, compliance, and optionally node details.
#
# Examples:
#   ./utils/checkmarx.list-sast-results.sh --scan-id "uuid"
#   ./utils/checkmarx.list-sast-results.sh --scan-id "uuid" --severity "HIGH,CRITICAL"
#   ./utils/checkmarx.list-sast-results.sh --scan-id "uuid" --language "JavaScript" --query "SQL_Injection"
#   ./utils/checkmarx.list-sast-results.sh --scan-id "uuid" --cwe-id 79
#   ./utils/checkmarx.list-sast-results.sh --scan-id "uuid" --source-file "src/auth" --include-nodes
#
# Composability:
#   # Find all SQL injection findings in JavaScript files
#   ./utils/checkmarx.list-sast-results.sh --scan-id "$SID" --query "SQL_Injection" --language "JavaScript" \
#     | jq '[.[] | {severity, state, sourceFile: .data.nodes[0].fileName}]'
#
# Exit codes:
#   0  Success
#   1  Missing --scan-id, bad flag, or API error
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
SCAN_ID=""
SEVERITY=""
STATUS=""
STATE=""
QUERY_NAME=""
LANGUAGE=""
CWE_ID=""
SOURCE_FILE=""
SINK_FILE=""
COMPLIANCE=""
CATEGORY=""
APPLY_PREDICATES=""
INCLUDE_NODES=0
LIMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-id)           SCAN_ID="$2"; shift 2 ;;
    --severity)          SEVERITY="$2"; shift 2 ;;
    --status)            STATUS="$2"; shift 2 ;;
    --state)             STATE="$2"; shift 2 ;;
    --query)             QUERY_NAME="$2"; shift 2 ;;
    --language)          LANGUAGE="$2"; shift 2 ;;
    --cwe-id)            CWE_ID="$2"; shift 2 ;;
    --source-file)       SOURCE_FILE="$2"; shift 2 ;;
    --sink-file)         SINK_FILE="$2"; shift 2 ;;
    --compliance)        COMPLIANCE="$2"; shift 2 ;;
    --category)          CATEGORY="$2"; shift 2 ;;
    --apply-predicates)  APPLY_PREDICATES="$2"; shift 2 ;;
    --include-nodes)     INCLUDE_NODES=1; shift ;;
    --limit)             LIMIT="$2"; shift 2 ;;
    *)                   echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${SCAN_ID}" ]; then
  echo "Usage: $0 [-v|--verbose] --scan-id ID [--severity S] [--status S] [--query Q] [--language L] [--cwe-id ID] [--limit N]" >&2
  exit 1
fi

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build query string ---
PARAMS=("scan-id=${SCAN_ID}")
[ -n "${SEVERITY}" ]          && PARAMS+=("severity=${SEVERITY}")
[ -n "${STATUS}" ]            && PARAMS+=("status=${STATUS}")
[ -n "${STATE}" ]             && PARAMS+=("state=${STATE}")
[ -n "${QUERY_NAME}" ]        && PARAMS+=("query=$(cx_urlencode "${QUERY_NAME}")")
[ -n "${LANGUAGE}" ]          && PARAMS+=("language=${LANGUAGE}")
[ -n "${CWE_ID}" ]            && PARAMS+=("cweId=${CWE_ID}")
[ -n "${SOURCE_FILE}" ]       && PARAMS+=("source-file=$(cx_urlencode "${SOURCE_FILE}")")
[ -n "${SINK_FILE}" ]         && PARAMS+=("sink-file=$(cx_urlencode "${SINK_FILE}")")
[ -n "${COMPLIANCE}" ]        && PARAMS+=("compliance=$(cx_urlencode "${COMPLIANCE}")")
[ -n "${CATEGORY}" ]          && PARAMS+=("category=$(cx_urlencode "${CATEGORY}")")
[ -n "${APPLY_PREDICATES}" ]  && PARAMS+=("apply-predicates=${APPLY_PREDICATES}")
[ "${INCLUDE_NODES}" -eq 1 ]  && PARAMS+=("include-nodes=true")

QUERY=$(IFS='&'; echo "${PARAMS[*]}")
URL="${BASE}/api/sast-results?${QUERY}"

# --- Fetch and output ---
if [ -n "${LIMIT}" ]; then
  RESPONSE=$(cx_get "${URL}&offset=0&limit=${LIMIT}")
  echo "${RESPONSE}" | jq '.results // []'
else
  cx_paginate "${URL}" "results"
fi
