#!/usr/bin/env bash
#
# checkmarx.sast-aggregate.sh
# ============================
# Get aggregated SAST scan results grouped by category.
#
# Queries the Checkmarx One SAST Results Summary API
# (GET /api/sast-scan-summary/aggregate) to return SAST finding counts
# grouped by one or more fields: QUERY, SEVERITY, STATUS, SOURCE_FILE,
# SINK_FILE, or LANGUAGE. Useful for vulnerability distribution reports,
# top-N query lists, and severity breakdowns.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/sast-scan-summary/aggregate
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Pagination: offset/limit
#   See also:   docs/rest-api-reference.md § 8.1
#
# Usage:
#   ./utils/checkmarx.sast-aggregate.sh [-v|--verbose] --scan-id ID --group-by FIELD [OPTIONS]
#
# Required:
#   --scan-id ID       UUID of the scan to aggregate
#   --group-by FIELD   Grouping field (repeatable). Values:
#                      QUERY, SEVERITY, STATUS, SOURCE_FILE, SINK_FILE,
#                      SOURCE_NODE, SINK_NODE, LANGUAGE
#
# Options:
#   -v, --verbose      Print curl commands and derived URLs to stderr
#   --severity S       Comma-separated severity filter (HIGH, MEDIUM, LOW, INFO)
#   --status S         Comma-separated status filter (NEW, RECURRENT)
#   --language L       Comma-separated language filter
#   --limit N          Max results per page (default: 20)
#
# Output:
#   JSON response with aggregated counts grouped by the specified fields.
#
# Examples:
#   ./utils/checkmarx.sast-aggregate.sh --scan-id "uuid" --group-by SEVERITY
#   ./utils/checkmarx.sast-aggregate.sh --scan-id "uuid" --group-by QUERY --severity "HIGH,CRITICAL"
#   ./utils/checkmarx.sast-aggregate.sh --scan-id "uuid" --group-by LANGUAGE --group-by SEVERITY
#   ./utils/checkmarx.sast-aggregate.sh --scan-id "uuid" --group-by QUERY --limit 50
#
# Composability:
#   # Top 10 SAST query types by count for latest scan
#   SID=$(./utils/checkmarx.list-scans.sh --project-id "$PID" --statuses Completed --limit 1 \
#     | jq -r '.[0].id')
#   ./utils/checkmarx.sast-aggregate.sh --scan-id "$SID" --group-by QUERY --limit 10
#
# Exit codes:
#   0  Success
#   1  Missing required args, bad flag, or API error
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
SCAN_ID=""
GROUP_BY=()
SEVERITY=""
STATUS=""
LANGUAGE=""
LIMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-id)   SCAN_ID="$2"; shift 2 ;;
    --group-by)  GROUP_BY+=("$2"); shift 2 ;;
    --severity)  SEVERITY="$2"; shift 2 ;;
    --status)    STATUS="$2"; shift 2 ;;
    --language)  LANGUAGE="$2"; shift 2 ;;
    --limit)     LIMIT="$2"; shift 2 ;;
    *)           echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${SCAN_ID}" ] || [ ${#GROUP_BY[@]} -eq 0 ]; then
  echo "Usage: $0 [-v|--verbose] --scan-id ID --group-by FIELD [--group-by FIELD2] [--severity S] [--status S] [--language L] [--limit N]" >&2
  exit 1
fi

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build query string ---
PARAMS=("scan-id=${SCAN_ID}")
for gb in "${GROUP_BY[@]}"; do
  PARAMS+=("group-by-field=${gb}")
done
[ -n "${SEVERITY}" ] && PARAMS+=("severity=${SEVERITY}")
[ -n "${STATUS}" ]   && PARAMS+=("status=${STATUS}")
[ -n "${LANGUAGE}" ] && PARAMS+=("language=${LANGUAGE}")
[ -n "${LIMIT}" ]    && PARAMS+=("limit=${LIMIT}")

QUERY=$(IFS='&'; echo "${PARAMS[*]}")

# --- Fetch and output ---
cx_get "${BASE}/api/sast-scan-summary/aggregate?${QUERY}"
