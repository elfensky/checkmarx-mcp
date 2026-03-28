#!/usr/bin/env bash
#
# checkmarx.list-scans.sh
# =======================
# List scans, optionally filtered by project and/or status.
#
# Fetches scans from the Checkmarx One Scans API (GET /api/scans).
# By default, auto-paginates to retrieve all matching scans. When
# --limit is provided, returns a single page sorted by most recent first.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/scans
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Pagination: offset/limit with filteredTotalCount
#   Sort:       +created_at = descending (most recent first)
#   See also:   docs/rest-api-reference.md § 3.2 (Scans API)
#
# Usage:
#   ./utils/checkmarx.list-scans.sh [-v|--verbose] [--project-id ID] [--statuses S] [--limit N]
#
# Options:
#   -v, --verbose       Print curl commands and derived URLs to stderr
#   --project-id ID     Filter scans to a single project (UUID)
#   --statuses S        Comma-separated status filter.
#                       Values: Queued, Running, Completed, Failed, Partial, Canceled
#   --limit N           Return at most N scans (single page, most recent first)
#
# Output:
#   A JSON array of scan objects to stdout. Each object includes:
#   id, status, statusDetails, branch, createdAt, engines, projectId, etc.
#
# Examples:
#   ./utils/checkmarx.list-scans.sh --project-id "uuid"                     # all scans for project
#   ./utils/checkmarx.list-scans.sh --statuses "Completed"                  # only completed
#   ./utils/checkmarx.list-scans.sh --project-id "uuid" --limit 1          # latest scan
#   ./utils/checkmarx.list-scans.sh --project-id "uuid" | jq '.[0].id'     # latest scan ID
#
# Composability:
#   # Get the latest completed scan ID for a project
#   SCAN_ID=$(./utils/checkmarx.list-scans.sh --project-id "$PID" --statuses Completed --limit 1 \
#     | jq -r '.[0].id')
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

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build query string from provided filters ---
PARAMS=()
[ -n "${PROJECT_ID}" ] && PARAMS+=("project-id=${PROJECT_ID}")
[ -n "${STATUSES}" ]   && PARAMS+=("statuses=${STATUSES}")

QUERY=""
if [ ${#PARAMS[@]} -gt 0 ]; then
  QUERY=$(IFS='&'; echo "${PARAMS[*]}")
fi

URL="${BASE}/api/scans"
[ -n "${QUERY}" ] && URL="${URL}?${QUERY}"

# --- Fetch and output ---
if [ -n "${LIMIT}" ]; then
  # Single page, sorted most-recent-first (%2B = '+' = descending)
  SEP="?"
  [[ "${URL}" == *"?"* ]] && SEP="&"
  RESPONSE=$(cx_get "${URL}${SEP}offset=0&limit=${LIMIT}&sort=%2Bcreated_at")
  echo "${RESPONSE}" | jq '.scans // []'
else
  cx_paginate "${URL}" "scans"
fi
