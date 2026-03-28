#!/usr/bin/env bash
#
# List SAST query presets available in the tenant.
# Outputs a JSON array of preset objects to stdout.
#
# Usage: ./cx-list-presets.sh [-v|--verbose]
#
# Examples:
#   ./cx-list-presets.sh                         # all presets
#   ./cx-list-presets.sh | jq '.[].name'         # just names
#   ./cx-list-presets.sh | jq '.[] | {id, name}' # id + name pairs
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

source "${SCRIPT_DIR}/.env"
cx_authenticate

cx_get "${BASE}/api/queries/presets"
