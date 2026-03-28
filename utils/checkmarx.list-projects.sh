#!/usr/bin/env bash
#
# checkmarx.list-projects.sh
# ==========================
# List all projects in the Checkmarx One tenant.
#
# This utility fetches projects from the Checkmarx One Projects API
# (GET /api/projects) and outputs a JSON array to stdout. By default
# it auto-paginates to retrieve every project; use --limit to cap
# the result to a single page.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/projects
#   Auth:       Bearer token (obtained via cx_authenticate)
#   Pagination: offset/limit with filteredTotalCount
#   See also:   docs/rest-api-reference.md § 13 (Projects API)
#
# Usage:
#   ./utils/checkmarx.list-projects.sh [-v|--verbose] [--name NAME] [--limit N]
#
# Options:
#   -v, --verbose   Print curl commands and derived URLs to stderr
#   --name NAME     Filter projects by name (API-level substring match)
#   --limit N       Return at most N projects (single page, no pagination)
#
# Output:
#   A JSON array of project objects written to stdout. Each object
#   includes: id, name, mainBranch, tags, repoUrl, applicationIds, etc.
#   Pipe through jq for field extraction.
#
# Examples:
#   ./utils/checkmarx.list-projects.sh                          # all projects
#   ./utils/checkmarx.list-projects.sh --name "my-project"      # filter by name
#   ./utils/checkmarx.list-projects.sh --limit 10               # first 10 only
#   ./utils/checkmarx.list-projects.sh | jq '.[].name'          # just names
#   ./utils/checkmarx.list-projects.sh | jq 'length'            # count projects
#
# Prerequisites:
#   - curl, jq
#   - Configured .env file in the repo root (see CLAUDE.md § Configuration)
#
# Exit codes:
#   0  Success
#   1  Missing argument, bad flag, or API error
#
set -euo pipefail

# --- Bootstrap: load shared library and parse global flags ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
NAME_FILTER=""
LIMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)  NAME_FILTER="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *)       echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build request URL ---
# The API's "name" parameter does substring matching, so callers should
# post-filter with jq if exact matching is needed.
QUERY=""
if [ -n "${NAME_FILTER}" ]; then
  QUERY="name=$(cx_urlencode "${NAME_FILTER}")"
fi

URL="${BASE}/api/projects"
if [ -n "${QUERY}" ]; then
  URL="${URL}?${QUERY}"
fi

# --- Fetch and output ---
if [ -n "${LIMIT}" ]; then
  # Single page with explicit limit — skip pagination
  SEP="?"
  [[ "${URL}" == *"?"* ]] && SEP="&"
  RESPONSE=$(cx_get "${URL}${SEP}offset=0&limit=${LIMIT}")
  echo "${RESPONSE}" | jq '.projects // []'
else
  # Auto-paginate to retrieve all projects
  cx_paginate "${URL}" "projects"
fi
