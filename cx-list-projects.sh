#!/usr/bin/env bash
#
# List all projects in the Checkmarx One tenant.
# Outputs a JSON array of project objects to stdout.
#
# Usage: ./cx-list-projects.sh [-v|--verbose] [--name NAME] [--limit N]
#
# Examples:
#   ./cx-list-projects.sh                          # all projects
#   ./cx-list-projects.sh --name "my-project"      # filter by name
#   ./cx-list-projects.sh | jq '.[].name'          # just names
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# Parse script-specific flags
NAME_FILTER=""
LIMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)  NAME_FILTER="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *)       echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

source "${SCRIPT_DIR}/.env"
cx_authenticate

# Build query string
QUERY=""
if [ -n "${NAME_FILTER}" ]; then
  QUERY="name=$(cx_urlencode "${NAME_FILTER}")"
fi

URL="${BASE}/api/projects"
if [ -n "${QUERY}" ]; then
  URL="${URL}?${QUERY}"
fi

if [ -n "${LIMIT}" ]; then
  # Single page with explicit limit
  SEP="?"
  [[ "${URL}" == *"?"* ]] && SEP="&"
  RESPONSE=$(cx_get "${URL}${SEP}offset=0&limit=${LIMIT}")
  echo "${RESPONSE}" | jq '.projects // []'
else
  cx_paginate "${URL}" "projects"
fi
