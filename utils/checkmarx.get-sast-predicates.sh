#!/usr/bin/env bash
#
# checkmarx.get-sast-predicates.sh
# =================================
# Get triage predicates (state/severity overrides) for a SAST finding.
#
# Queries the Checkmarx One SAST Results Predicates API
# (GET /api/sast-results-predicates/{similarity_id}/latest) to retrieve
# the current triage state for a finding, including severity overrides,
# state changes, and comments. Use this for compliance/triage reports.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/sast-results-predicates/{similarity_id}/latest
#   Auth:       Bearer token (obtained via cx_authenticate)
#   See also:   docs/rest-api-reference.md § 9.2
#
# Usage:
#   ./utils/checkmarx.get-sast-predicates.sh [-v|--verbose] --similarity-id ID [OPTIONS]
#
# Required:
#   --similarity-id ID   Similarity ID of the SAST finding
#
# Options:
#   -v, --verbose        Print curl commands and derived URLs to stderr
#   --project-ids IDS    Comma-separated project UUIDs to filter by
#   --scan-id ID         Filter by scan UUID
#
# Output:
#   JSON object with the latest predicate for the finding, including:
#   severity, state, comment, createdBy, createdAt.
#
# Examples:
#   ./utils/checkmarx.get-sast-predicates.sh --similarity-id "12345"
#   ./utils/checkmarx.get-sast-predicates.sh --similarity-id "12345" --scan-id "uuid"
#   ./utils/checkmarx.get-sast-predicates.sh --similarity-id "12345" --project-ids "uuid1,uuid2"
#
# Composability:
#   # Get triage info for all HIGH findings in a scan
#   ./utils/checkmarx.list-results.sh --scan-id "$SID" --severity HIGH \
#     | jq -r '.[].similarityId' \
#     | while read sim_id; do
#         ./utils/checkmarx.get-sast-predicates.sh --similarity-id "$sim_id" --scan-id "$SID"
#       done
#
# Exit codes:
#   0  Success
#   1  Missing --similarity-id, bad flag, or API error
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
SIMILARITY_ID=""
PROJECT_IDS=""
SCAN_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --similarity-id) SIMILARITY_ID="$2"; shift 2 ;;
    --project-ids)   PROJECT_IDS="$2"; shift 2 ;;
    --scan-id)       SCAN_ID="$2"; shift 2 ;;
    *)               echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${SIMILARITY_ID}" ]; then
  echo "Usage: $0 [-v|--verbose] --similarity-id ID [--project-ids IDS] [--scan-id ID]" >&2
  exit 1
fi

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build query string ---
PARAMS=()
[ -n "${PROJECT_IDS}" ] && PARAMS+=("project-ids=${PROJECT_IDS}")
[ -n "${SCAN_ID}" ]     && PARAMS+=("scan-id=${SCAN_ID}")

URL="${BASE}/api/sast-results-predicates/${SIMILARITY_ID}/latest"
if [ ${#PARAMS[@]} -gt 0 ]; then
  QUERY=$(IFS='&'; echo "${PARAMS[*]}")
  URL="${URL}?${QUERY}"
fi

# --- Fetch and output ---
cx_get "${URL}"
