#!/usr/bin/env bash
#
# checkmarx.list-presets.sh
# =========================
# List SAST query presets available in the tenant.
#
# Presets define which SAST queries (vulnerability rules) are included
# in a scan. Common presets include "Checkmarx Default", "OWASP Top 10",
# "SANS top 25", etc. Use this utility to discover available presets
# for scan configuration.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/queries/presets
#   Auth:       Bearer token (obtained via cx_authenticate)
#   See also:   docs/rest-api-reference.md § 15.2 (SAST Query Presets)
#
# Usage:
#   ./utils/checkmarx.list-presets.sh [-v|--verbose]
#
# Options:
#   -v, --verbose   Print curl commands and derived URLs to stderr
#
# Output:
#   A JSON array of preset objects to stdout. Each object includes
#   at minimum: id, name.
#
# Examples:
#   ./utils/checkmarx.list-presets.sh                          # all presets
#   ./utils/checkmarx.list-presets.sh | jq '.[].name'          # just names
#   ./utils/checkmarx.list-presets.sh | jq '.[] | {id, name}'  # id + name pairs
#   ./utils/checkmarx.list-presets.sh | jq 'length'            # count presets
#
# Exit codes:
#   0  Success
#   1  API error
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Fetch and output ---
# This endpoint returns a flat array (no pagination wrapper).
cx_get "${BASE}/api/queries/presets"
