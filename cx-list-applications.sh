#!/usr/bin/env bash
#
# List all applications in the Checkmarx One tenant.
# Outputs a JSON array of application objects to stdout.
#
# Usage: ./cx-list-applications.sh [-v|--verbose] [--name NAME]
#
# Examples:
#   ./cx-list-applications.sh                                # all applications
#   ./cx-list-applications.sh --name "MyApp"                 # filter by name
#   ./cx-list-applications.sh | jq '.[].name'               # just names
#   ./cx-list-applications.sh | jq '.[] | {name, id, projectIds}' # summary
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# Parse script-specific flags
NAME_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME_FILTER="$2"; shift 2 ;;
    *)      echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

source "${SCRIPT_DIR}/.env"
cx_authenticate

URL="${BASE}/api/applications"
if [ -n "${NAME_FILTER}" ]; then
  URL="${URL}?name=$(cx_urlencode "${NAME_FILTER}")"
fi

cx_paginate "${URL}" "applications"
