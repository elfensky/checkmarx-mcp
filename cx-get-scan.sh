#!/usr/bin/env bash
#
# Get a single scan by ID.
# Outputs the scan JSON object to stdout.
#
# Usage: ./cx-get-scan.sh [-v|--verbose] <SCAN_ID>
#
# Examples:
#   ./cx-get-scan.sh "scan-uuid"
#   ./cx-get-scan.sh "scan-uuid" | jq '.status'
#   ./cx-get-scan.sh "scan-uuid" | jq '.engines'
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 [-v|--verbose] <SCAN_ID>" >&2
  exit 1
fi

SCAN_ID="$1"

source "${SCRIPT_DIR}/.env"
cx_authenticate

cx_get "${BASE}/api/scans/${SCAN_ID}"
