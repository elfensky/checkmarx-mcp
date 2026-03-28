#!/usr/bin/env bash
#
# List scans, optionally filtered by project.
# Outputs a JSON array of scan objects to stdout.
#
# Usage: ./cx-list-scans.sh [-v|--verbose] [--project-id ID] [--statuses S] [--limit N]
#
# Examples:
#   ./cx-list-scans.sh --project-id "uuid"                       # scans for a project
#   ./cx-list-scans.sh --statuses "Completed"                    # only completed
#   ./cx-list-scans.sh --project-id "uuid" --limit 5             # last 5 scans
#   ./cx-list-scans.sh --project-id "uuid" | jq '.[0].status'   # latest scan status
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# Parse script-specific flags
PROJECT_ID=""
STATUSES=""
LIMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --statuses)   STATUSES="$2"; shift 2 ;;
    --limit)      LIMIT="$2"; shift 2 ;;
    *)            echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

source "${SCRIPT_DIR}/.env"
cx_authenticate

# Build query string
PARAMS=()
[ -n "${PROJECT_ID}" ] && PARAMS+=("project-id=${PROJECT_ID}")
[ -n "${STATUSES}" ]   && PARAMS+=("statuses=${STATUSES}")

QUERY=""
if [ ${#PARAMS[@]} -gt 0 ]; then
  QUERY=$(IFS='&'; echo "${PARAMS[*]}")
fi

URL="${BASE}/api/scans"
[ -n "${QUERY}" ] && URL="${URL}?${QUERY}"

if [ -n "${LIMIT}" ]; then
  SEP="?"
  [[ "${URL}" == *"?"* ]] && SEP="&"
  RESPONSE=$(cx_get "${URL}${SEP}offset=0&limit=${LIMIT}&sort=%2Bcreated_at")
  echo "${RESPONSE}" | jq '.scans // []'
else
  cx_paginate "${URL}" "scans"
fi
