#!/usr/bin/env bash
#
# List scan results (vulnerabilities) for a given scan.
# Outputs a JSON array of result objects to stdout.
#
# Usage: ./cx-list-results.sh [-v|--verbose] --scan-id ID [--severity S] [--state S] [--limit N]
#
# Examples:
#   ./cx-list-results.sh --scan-id "uuid"
#   ./cx-list-results.sh --scan-id "uuid" --severity "HIGH,CRITICAL"
#   ./cx-list-results.sh --scan-id "uuid" --state "TO_VERIFY" --limit 10
#   ./cx-list-results.sh --scan-id "uuid" | jq '[.[] | {type, severity, status}]'
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# Parse script-specific flags
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

source "${SCRIPT_DIR}/.env"
cx_authenticate

# Build query string
PARAMS=("scan-id=${SCAN_ID}")
[ -n "${SEVERITY}" ] && PARAMS+=("severity=${SEVERITY}")
[ -n "${STATE}" ]    && PARAMS+=("state=${STATE}")

QUERY=$(IFS='&'; echo "${PARAMS[*]}")
URL="${BASE}/api/results?${QUERY}"

if [ -n "${LIMIT}" ]; then
  RESPONSE=$(cx_get "${URL}&offset=0&limit=${LIMIT}")
  echo "${RESPONSE}" | jq '.results // []'
else
  cx_paginate "${URL}" "results"
fi
