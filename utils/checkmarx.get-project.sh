#!/usr/bin/env bash
#
# checkmarx.get-project.sh
# ========================
# Get a single project by ID or name.
#
# Accepts either a UUID (direct fetch via GET /api/projects/{id}) or a
# project name (searched via GET /api/projects?name=... with exact-match
# filtering on the client side, since the API does substring matching).
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/projects/{id}         (by UUID)
#               GET {BASE_URI}/api/projects?name={name}  (by name)
#   Auth:       Bearer token (obtained via cx_authenticate)
#   See also:   docs/rest-api-reference.md § 13.2–13.3 (Projects API)
#
# Usage:
#   ./utils/checkmarx.get-project.sh [-v|--verbose] <PROJECT_ID_OR_NAME>
#
# Arguments:
#   PROJECT_ID_OR_NAME   A UUID (e.g., a1b2c3d4-...) fetches by ID directly.
#                        Any other string is treated as a project name and
#                        searched with exact-match filtering.
#
# Options:
#   -v, --verbose   Print curl commands and derived URLs to stderr
#
# Output:
#   A single project JSON object written to stdout.
#   Includes: id, name, mainBranch, tags, groups, repoUrl, applicationIds, etc.
#
# Examples:
#   ./utils/checkmarx.get-project.sh "my-project"                     # by name
#   ./utils/checkmarx.get-project.sh "a1b2c3d4-e5f6-..."              # by UUID
#   ./utils/checkmarx.get-project.sh "my-project" | jq '.id'          # get ID
#   ./utils/checkmarx.get-project.sh "my-project" | jq '.mainBranch'  # get branch
#
# Error handling:
#   If no project matches the name, prints similar project names to stderr
#   and exits with code 1.
#
# Exit codes:
#   0  Success
#   1  Missing argument, project not found, or API error
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Validate required argument ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 [-v|--verbose] <PROJECT_ID_OR_NAME>" >&2
  exit 1
fi

IDENTIFIER="$1"

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Detect UUID vs. name ---
# UUIDs are 36 characters in 8-4-4-4-12 hex format. The regex is stored
# in a variable (not quoted on the RHS of =~) for bash 3.2 compatibility.
UUID_REGEX='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

if [[ "${IDENTIFIER}" =~ ${UUID_REGEX} ]]; then
  # --- Direct fetch by ID ---
  cx_vlog "Fetching project by ID: ${IDENTIFIER}"
  cx_get "${BASE}/api/projects/${IDENTIFIER}"
else
  # --- Search by name, then exact-match filter ---
  # The API's name param does substring matching, so we fetch candidates
  # and filter client-side with jq for an exact match.
  cx_vlog "Searching for project by name: ${IDENTIFIER}"
  NAME_ENCODED=$(cx_urlencode "${IDENTIFIER}")
  RESPONSE=$(cx_get "${BASE}/api/projects?name=${NAME_ENCODED}&limit=100")

  MATCH=$(echo "${RESPONSE}" | jq -e --arg name "${IDENTIFIER}" \
    '[.projects[] | select(.name == $name)] | if length == 0 then error("not found") else .[0] end') || {
    echo "ERROR: Project '${IDENTIFIER}' not found." >&2
    echo ">> Similar projects:" >&2
    echo "${RESPONSE}" | jq -r '.projects[]?.name // empty' >&2
    exit 1
  }

  echo "${MATCH}"
fi
