#!/usr/bin/env bash
#
# checkmarx.list-applications.sh
# ==============================
# List all applications in the Checkmarx One tenant.
#
# Applications are logical groupings of projects. Each application
# has a name, criticality level, and a list of associated project IDs.
# This utility fetches from the Applications API (GET /api/applications)
# with auto-pagination.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/applications
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Pagination: offset/limit with totalCount
#   See also:   docs/rest-api-reference.md § 12 (Applications API)
#
# Usage:
#   ./utils/checkmarx.list-applications.sh [-v|--verbose] [--name NAME]
#
# Options:
#   -v, --verbose   Print curl commands and derived URLs to stderr
#   --name NAME     Filter applications by name (API-level substring match)
#
# Output:
#   A JSON array of application objects to stdout. Each object includes:
#   id, name, description, criticality, projectIds[], rules[], tags{}.
#
# Examples:
#   ./utils/checkmarx.list-applications.sh                               # all apps
#   ./utils/checkmarx.list-applications.sh --name "MyApp"                # filter by name
#   ./utils/checkmarx.list-applications.sh | jq '.[].name'              # just names
#   ./utils/checkmarx.list-applications.sh | jq '.[] | {name, id, projectIds}'  # summary
#
# Composability:
#   # Get all project IDs for an application
#   ./utils/checkmarx.list-applications.sh --name "MyApp" | jq -r '.[0].projectIds[]'
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
NAME_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME_FILTER="$2"; shift 2 ;;
    *)      echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build request URL ---
URL="${BASE}/api/applications"
if [ -n "${NAME_FILTER}" ]; then
  URL="${URL}?name=$(cx_urlencode "${NAME_FILTER}")"
fi

# --- Fetch and output (auto-paginated) ---
cx_paginate "${URL}" "applications"
