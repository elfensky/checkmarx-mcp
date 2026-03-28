#!/usr/bin/env bash
#
# Get scan results summary (severity/status counts) for one or more scans.
# Outputs the summary JSON to stdout.
#
# Usage: ./cx-scan-summary.sh [-v|--verbose] --scan-id ID [--scan-id ID2 ...]
#
# Examples:
#   ./cx-scan-summary.sh --scan-id "uuid"
#   ./cx-scan-summary.sh --scan-id "uuid" | jq '.scansSummaries[0].sastCounters'
#   ./cx-scan-summary.sh --scan-id "id1" --scan-id "id2"   # multiple scans
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# Parse scan IDs
SCAN_IDS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-id) SCAN_IDS+=("$2"); shift 2 ;;
    *)         echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ ${#SCAN_IDS[@]} -eq 0 ]; then
  echo "Usage: $0 [-v|--verbose] --scan-id ID [--scan-id ID2 ...]" >&2
  exit 1
fi

source "${SCRIPT_DIR}/.env"
cx_authenticate

# Build scan-ids query params
QUERY=""
for sid in "${SCAN_IDS[@]}"; do
  [ -n "${QUERY}" ] && QUERY="${QUERY}&"
  QUERY="${QUERY}scan-ids=${sid}"
done

cx_get "${BASE}/api/scan-summary?${QUERY}&include-severity-status=true"
