#!/usr/bin/env bash
#
# List all groups in the Checkmarx One tenant.
# Outputs a JSON array of group objects to stdout.
#
# Usage: ./cx-list-groups.sh [-v|--verbose] [--search TERM]
#
# Examples:
#   ./cx-list-groups.sh                          # all groups
#   ./cx-list-groups.sh --search "security"      # search by name
#   ./cx-list-groups.sh | jq '.[].name'          # just names
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# Parse script-specific flags
SEARCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --search) SEARCH="$2"; shift 2 ;;
    *)        echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

source "${SCRIPT_DIR}/.env"
cx_authenticate

URL="${BASE}/api/access-management/groups"
if [ -n "${SEARCH}" ]; then
  URL="${URL}?search=$(cx_urlencode "${SEARCH}")"
fi

# The groups endpoint returns a flat array, not a paginated collection
RESPONSE=$(cx_get "${URL}")

# Handle both array-style and paginated-style responses
if echo "${RESPONSE}" | jq -e 'type == "array"' > /dev/null 2>&1; then
  echo "${RESPONSE}"
else
  echo "${RESPONSE}" | jq '.groups // []'
fi
