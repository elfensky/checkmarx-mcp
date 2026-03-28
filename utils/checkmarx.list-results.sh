#!/usr/bin/env bash
#
# checkmarx.list-results.sh
# =========================
# List scan results (vulnerabilities) for a given scan.
#
# Fetches vulnerability findings from the Checkmarx One Results API
# (GET /api/results). Returns results from all scanner engines (SAST,
# SCA, KICS, API Security) in a unified format. Use --severity and
# --state to filter to the most relevant findings.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/results
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Pagination: offset/limit with totalCount
#   See also:   docs/rest-api-reference.md § 6 (Results API)
#
# Usage:
#   ./utils/checkmarx.list-results.sh [-v|--verbose] --scan-id ID [--severity S] [--state S] [--limit N]
#
# Required:
#   --scan-id ID     UUID of the scan to fetch results for
#
# Options:
#   -v, --verbose    Print curl commands and derived URLs to stderr
#   --severity S     Comma-separated severity filter.
#                    Values: CRITICAL, HIGH, MEDIUM, LOW, INFO
#   --state S        Comma-separated state filter.
#                    Values: TO_VERIFY, NOT_EXPLOITABLE, PROPOSED_NOT_EXPLOITABLE, CONFIRMED, URGENT
#   --limit N        Return at most N results (single page, no pagination)
#
# Output:
#   A JSON array of result objects to stdout. Each object includes:
#   type (sast/sca/kics/apisec), id, severity, status, state,
#   description, confidenceLevel, firstFoundAt, data, etc.
#
# Examples:
#   ./utils/checkmarx.list-results.sh --scan-id "uuid"
#   ./utils/checkmarx.list-results.sh --scan-id "uuid" --severity "HIGH,CRITICAL"
#   ./utils/checkmarx.list-results.sh --scan-id "uuid" --state "TO_VERIFY" --limit 10
#   ./utils/checkmarx.list-results.sh --scan-id "uuid" | jq '[.[] | {type, severity, status}]'
#   ./utils/checkmarx.list-results.sh --scan-id "uuid" | jq 'group_by(.severity) | map({(.[0].severity): length}) | add'
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
STATE=""
LIMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-id)  SCAN_ID="$2"; shift 2 ;;
    --severity) SEVERITY="$2"; shift 2 ;;
    --state)    STATE="$2"; shift 2 ;;
    --limit)    LIMIT="$2"; shift 2 ;;
    *)          echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${SCAN_ID}" ]; then
  echo "Usage: $0 [-v|--verbose] --scan-id ID [--severity S] [--state S] [--limit N]" >&2
  exit 1
fi

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build query string ---
PARAMS=("scan-id=${SCAN_ID}")
[ -n "${SEVERITY}" ] && PARAMS+=("severity=${SEVERITY}")
[ -n "${STATE}" ]    && PARAMS+=("state=${STATE}")

QUERY=$(IFS='&'; echo "${PARAMS[*]}")
URL="${BASE}/api/results?${QUERY}"

# --- Fetch and output ---
if [ -n "${LIMIT}" ]; then
  RESPONSE=$(cx_get "${URL}&offset=0&limit=${LIMIT}")
  echo "${RESPONSE}" | jq '.results // []'
else
  cx_paginate "${URL}" "results"
fi
