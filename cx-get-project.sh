#!/usr/bin/env bash
#
# Get a single project by ID or name.
# Outputs the project JSON object to stdout.
#
# Usage: ./cx-get-project.sh [-v|--verbose] <PROJECT_ID_OR_NAME>
#
# Examples:
#   ./cx-get-project.sh "my-project"                     # by name
#   ./cx-get-project.sh "a1b2c3d4-..."                   # by UUID
#   ./cx-get-project.sh "my-project" | jq '.mainBranch'  # extract field
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 [-v|--verbose] <PROJECT_ID_OR_NAME>" >&2
  exit 1
fi

IDENTIFIER="$1"

source "${SCRIPT_DIR}/.env"
cx_authenticate

# Detect UUID pattern
UUID_REGEX='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

if [[ "${IDENTIFIER}" =~ ${UUID_REGEX} ]]; then
  cx_vlog "Fetching project by ID: ${IDENTIFIER}"
  cx_get "${BASE}/api/projects/${IDENTIFIER}"
else
  cx_vlog "Searching for project by name: ${IDENTIFIER}"
  NAME_ENCODED=$(cx_urlencode "${IDENTIFIER}")
  RESPONSE=$(cx_get "${BASE}/api/projects?name=${NAME_ENCODED}&limit=100")

  # Exact-match filter (API may do substring matching)
  MATCH=$(echo "${RESPONSE}" | jq -e --arg name "${IDENTIFIER}" \
    '[.projects[] | select(.name == $name)] | if length == 0 then error("not found") else .[0] end') || {
    echo "ERROR: Project '${IDENTIFIER}' not found." >&2
    echo ">> Similar projects:" >&2
    echo "${RESPONSE}" | jq -r '.projects[]?.name // empty' >&2
    exit 1
  }

  echo "${MATCH}"
fi
