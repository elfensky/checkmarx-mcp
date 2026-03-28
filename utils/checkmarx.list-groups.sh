#!/usr/bin/env bash
#
# checkmarx.list-groups.sh
# ========================
# List all access management groups in the Checkmarx One tenant.
#
# Groups control project access and role assignments. Each group has
# an ID and name, and can be assigned to projects to control who can
# view/scan them. This utility fetches from the Access Management API.
#
# Note: The groups endpoint may return either a flat JSON array (older
# API versions) or a paginated collection with a "groups" key. This
# script handles both response formats transparently.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/access-management/groups
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Params:     search, limit, offset, ids
#   See also:   docs/rest-api-reference.md § 14.1 (Groups API)
#
# Usage:
#   ./utils/checkmarx.list-groups.sh [-v|--verbose] [--search TERM]
#
# Options:
#   -v, --verbose    Print curl commands and derived URLs to stderr
#   --search TERM    Search groups by name (substring match)
#
# Output:
#   A JSON array of group objects to stdout. Each object includes:
#   id, name, briefName.
#
# Examples:
#   ./utils/checkmarx.list-groups.sh                          # all groups
#   ./utils/checkmarx.list-groups.sh --search "security"      # search by name
#   ./utils/checkmarx.list-groups.sh | jq '.[].name'          # just names
#   ./utils/checkmarx.list-groups.sh | jq '.[] | {id, name}'  # id + name pairs
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
SEARCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --search) SEARCH="$2"; shift 2 ;;
    *)        echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build request URL ---
URL="${BASE}/api/access-management/groups"
if [ -n "${SEARCH}" ]; then
  URL="${URL}?search=$(cx_urlencode "${SEARCH}")"
fi

# --- Fetch and normalize output ---
# The groups endpoint doesn't follow the standard paginated collection
# format — it may return a raw JSON array. Handle both cases.
RESPONSE=$(cx_get "${URL}")

if echo "${RESPONSE}" | jq -e 'type == "array"' > /dev/null 2>&1; then
  echo "${RESPONSE}"
else
  echo "${RESPONSE}" | jq '.groups // []'
fi
