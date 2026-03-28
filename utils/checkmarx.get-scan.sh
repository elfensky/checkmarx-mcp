#!/usr/bin/env bash
#
# checkmarx.get-scan.sh
# =====================
# Get a single scan by its ID.
#
# Fetches the full scan object from the Checkmarx One Scans API
# (GET /api/scans/{id}). This is the simplest utility — it takes
# a scan UUID and returns the complete scan JSON.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/scans/{id}
#   Auth:       Bearer token (obtained via cx_authenticate)
#   See also:   docs/rest-api-reference.md § 3.3 (Get Scan by ID)
#
# Usage:
#   ./utils/checkmarx.get-scan.sh [-v|--verbose] <SCAN_ID>
#
# Arguments:
#   SCAN_ID   UUID of the scan to retrieve
#
# Options:
#   -v, --verbose   Print curl commands and derived URLs to stderr
#
# Output:
#   A single scan JSON object to stdout containing: id, status,
#   statusDetails, branch, createdAt, updatedAt, projectId,
#   projectName, engines, tags, metadata, sourceType, sourceOrigin.
#
# Examples:
#   ./utils/checkmarx.get-scan.sh "scan-uuid"
#   ./utils/checkmarx.get-scan.sh "scan-uuid" | jq '.status'
#   ./utils/checkmarx.get-scan.sh "scan-uuid" | jq '.engines'
#   ./utils/checkmarx.get-scan.sh "scan-uuid" | jq '.statusDetails[] | {name, status}'
#
# Exit codes:
#   0  Success
#   1  Missing argument or API error (e.g., scan not found → HTTP 404)
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Validate required argument ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 [-v|--verbose] <SCAN_ID>" >&2
  exit 1
fi

SCAN_ID="$1"

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Fetch and output ---
cx_get "${BASE}/api/scans/${SCAN_ID}"
