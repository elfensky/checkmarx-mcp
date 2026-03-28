#!/usr/bin/env bash
#
# checkmarx.scan-summary.sh
# =========================
# Get scan results summary (severity and status counts) for one or more scans.
#
# Queries the Checkmarx One Results Summary API (GET /api/scan-summary)
# which returns aggregated vulnerability counts broken down by scanner
# type (SAST, SCA, KICS, API Security), severity, status, and state.
# This is much faster than fetching individual results when you only
# need counts.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/scan-summary
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Params:     scan-ids (required, repeatable), include-severity-status,
#               include-queries, include-files
#   See also:   docs/rest-api-reference.md § 11 (Results Summary API)
#
# Usage:
#   ./utils/checkmarx.scan-summary.sh [-v|--verbose] --scan-id ID [--scan-id ID2 ...] [--include-queries] [--include-files]
#
# Options:
#   -v, --verbose       Print curl commands and derived URLs to stderr
#   --scan-id ID        Scan UUID to include in the summary (repeatable)
#   --include-queries   Include per-query breakdown in the response
#   --include-files     Include per-file breakdown in the response
#
# Output:
#   The full scan-summary JSON to stdout. Key structure:
#   {
#     "scansSummaries": [{
#       "scanId": "...",
#       "sastCounters":  { totalCounter, severityCounters[], statusCounters[], ... },
#       "scaCounters":   { ... },
#       "kicsCounters":  { ... },
#       "apiSecCounters": { ... }
#     }],
#     "totalCount": 1
#   }
#
# Examples:
#   ./utils/checkmarx.scan-summary.sh --scan-id "uuid"
#   ./utils/checkmarx.scan-summary.sh --scan-id "uuid" --include-queries
#   ./utils/checkmarx.scan-summary.sh --scan-id "uuid" | jq '.scansSummaries[0].sastCounters'
#   ./utils/checkmarx.scan-summary.sh --scan-id "id1" --scan-id "id2"
#
#   # Extract just HIGH severity SAST count:
#   ./utils/checkmarx.scan-summary.sh --scan-id "uuid" \
#     | jq '.scansSummaries[0].sastCounters.severityCounters[] | select(.severity=="HIGH") | .counter'
#
# Exit codes:
#   0  Success
#   1  Missing --scan-id or API error
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse scan IDs (repeatable flag) ---
SCAN_IDS=()
INCLUDE_QUERIES=0
INCLUDE_FILES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-id)          SCAN_IDS+=("$2"); shift 2 ;;
    --include-queries)  INCLUDE_QUERIES=1; shift ;;
    --include-files)    INCLUDE_FILES=1; shift ;;
    *)                  echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ ${#SCAN_IDS[@]} -eq 0 ]; then
  echo "Usage: $0 [-v|--verbose] --scan-id ID [--scan-id ID2 ...] [--include-queries] [--include-files]" >&2
  exit 1
fi

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build query string ---
# The API accepts multiple scan-ids params: ?scan-ids=id1&scan-ids=id2
QUERY=""
for sid in "${SCAN_IDS[@]}"; do
  [ -n "${QUERY}" ] && QUERY="${QUERY}&"
  QUERY="${QUERY}scan-ids=${sid}"
done

# --- Add optional params ---
QUERY="${QUERY}&include-severity-status=true"
[ "${INCLUDE_QUERIES}" -eq 1 ] && QUERY="${QUERY}&include-queries=true"
[ "${INCLUDE_FILES}" -eq 1 ]   && QUERY="${QUERY}&include-files=true"

# --- Fetch and output ---
cx_get "${BASE}/api/scan-summary?${QUERY}"
