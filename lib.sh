#!/usr/bin/env bash
#
# Shared library for Checkmarx CLI scripts.
# Source this file after set -euo pipefail and before any logic.
#
# Provides:
#   cx_parse_flags "$@"  — parses common flags, sets globals, updates $@ via CX_POSITIONAL_ARGS
#   cx_curl ...          — curl wrapper that prints the command in verbose mode
#   cx_log  "msg"        — prints to stderr (respects quiet future flag)
#   cx_vlog "msg"        — prints to stderr only when VERBOSE=1
#   cx_require_vars V..  — validates that listed env vars are set and non-empty
#   cx_base_urls         — derives BASE, IAM_URL from BASE_URI and TENANT
#   cx_authenticate      — obtains ACCESS_TOKEN (cached in $TMPDIR per tenant)
#   cx_get URL           — authenticated GET with standard headers
#   cx_paginate URL KEY  — fetches all pages, outputs merged JSON array
#   cx_urlencode STR     — portable percent-encoding (no Python dependency)
#   cx_resolve_project_ids — resolves scope flags to JSON array of project IDs
#   cx_date_range P R     — generates JSON array of time buckets (monthly/quarterly/yearly)
#   cx_format_csv FIELDS  — reads JSON array from stdin, outputs CSV with header
#   cx_format_table FIELDS — reads JSON array from stdin, outputs markdown table
#
# Globals set by cx_parse_flags:
#   VERBOSE   — 0 or 1
#   DRY_RUN   — 0 or 1 (for future write scripts)
#   EXECUTE   — 0 or 1 (for future write scripts; --execute flips DRY_RUN off)
#   FORMAT    — json (default), csv, or md

VERBOSE="${VERBOSE:-0}"
DRY_RUN="${DRY_RUN:-0}"
EXECUTE="${EXECUTE:-0}"
FORMAT="${FORMAT:-json}"
CX_POSITIONAL_ARGS=()
ACCESS_TOKEN="${ACCESS_TOKEN:-}"

cx_parse_flags() {
  CX_POSITIONAL_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --execute|--confirm)
        EXECUTE=1
        DRY_RUN=0
        shift
        ;;
      --format)
        if [ -z "${2:-}" ]; then
          echo "ERROR: --format requires a value (json, csv, or md)" >&2
          return 1
        fi
        FORMAT="$2"
        case "${FORMAT}" in
          json|csv|md) ;;
          *) echo "ERROR: --format must be json, csv, or md (got: ${FORMAT})" >&2; return 1 ;;
        esac
        shift 2
        ;;
      --)
        shift
        CX_POSITIONAL_ARGS+=("$@")
        break
        ;;
      *)
        CX_POSITIONAL_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

cx_log() {
  echo ">> $1" >&2
}

cx_vlog() {
  if [[ "${VERBOSE}" -eq 1 ]]; then
    echo "[verbose] $1" >&2
  fi
}

# Wrapper around curl that logs the command in verbose mode.
# Usage: cx_curl [curl args...]
cx_curl() {
  if [[ "${VERBOSE}" -eq 1 ]]; then
    # Reconstruct a readable command, masking Authorization headers
    local display_args=()
    local skip_next=0
    for arg in "$@"; do
      if [[ "${skip_next}" -eq 1 ]]; then
        if [[ "${arg}" == Bearer* || "${arg}" == *"Bearer "* ]]; then
          display_args+=("'Authorization: Bearer <REDACTED>'")
        else
          display_args+=("'${arg}'")
        fi
        skip_next=0
        continue
      fi
      if [[ "${arg}" == "--header" || "${arg}" == "-H" ]]; then
        display_args+=("${arg}")
        skip_next=1
        continue
      fi
      # Mask refresh_token and client_secret values in --data-urlencode
      if [[ "${arg}" == refresh_token=* ]]; then
        display_args+=("'refresh_token=<REDACTED>'")
        continue
      fi
      if [[ "${arg}" == client_secret=* ]]; then
        display_args+=("'client_secret=<REDACTED>'")
        continue
      fi
      display_args+=("'${arg}'")
    done
    echo "[verbose] curl ${display_args[*]}" >&2
  fi

  curl "$@"
}

# ---------------------------------------------------------------------------
# cx_require_vars VAR1 VAR2 ...
# Exits with an error if any listed variable is unset or empty.
# ---------------------------------------------------------------------------
cx_require_vars() {
  local var
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then
      echo "ERROR: Required environment variable ${var} is not set or empty." >&2
      exit 1
    fi
  done
}

# ---------------------------------------------------------------------------
# cx_base_urls
# Derives BASE and IAM_URL from BASE_URI and TENANT.
# Must be called after sourcing .env.
# ---------------------------------------------------------------------------
cx_base_urls() {
  BASE="${BASE_URI%/}"
  IAM_URL="${BASE/ast.checkmarx.net/iam.checkmarx.net}/auth/realms/${TENANT}/protocol/openid-connect/token"
  cx_vlog "BASE=${BASE}"
  cx_vlog "IAM_URL=${IAM_URL}"
}

# ---------------------------------------------------------------------------
# cx_urlencode STRING
# Portable percent-encoding using only bash builtins + printf.
# ---------------------------------------------------------------------------
cx_urlencode() {
  jq -rn --arg s "$1" '$s | @uri'
}

# ---------------------------------------------------------------------------
# cx_authenticate
# Obtains an access token and exports ACCESS_TOKEN.
# Caches token in $TMPDIR/cx-token-<TENANT>.json; reuses if not expired.
# Auto-detects auth flow: uses CLIENT_ID/CLIENT_SECRET if both set,
# otherwise falls back to APIKEY.
# ---------------------------------------------------------------------------
cx_authenticate() {
  cx_require_vars TENANT BASE_URI
  cx_base_urls

  local token_file="${TMPDIR:-/tmp}/cx-token-${TENANT}.json"
  local now
  now=$(date +%s)

  # Try cached token
  if [ -f "${token_file}" ]; then
    local cached_expiry
    cached_expiry=$(jq -r '.expires_at // 0' "${token_file}" 2>/dev/null || echo 0)
    if [ "${now}" -lt "${cached_expiry}" ]; then
      ACCESS_TOKEN=$(jq -r '.access_token' "${token_file}")
      cx_vlog "Using cached token (expires at ${cached_expiry}, now=${now})"
      return 0
    fi
    cx_vlog "Cached token expired, re-authenticating"
  fi

  local token_response
  if [ -n "${CLIENT_ID:-}" ] && [ -n "${CLIENT_SECRET:-}" ]; then
    cx_log "Authenticating (OAuth2 client_credentials)..."
    token_response=$(cx_curl --silent --fail --request POST "${IAM_URL}" \
      --header 'Content-Type: application/x-www-form-urlencoded' \
      --header 'Accept: application/json' \
      --data-urlencode "grant_type=client_credentials" \
      --data-urlencode "client_id=${CLIENT_ID}" \
      --data-urlencode "client_secret=${CLIENT_SECRET}")
  elif [ -n "${APIKEY:-}" ]; then
    cx_log "Authenticating (API Key refresh_token)..."
    token_response=$(cx_curl --silent --fail --request POST "${IAM_URL}" \
      --header 'Content-Type: application/x-www-form-urlencoded' \
      --header 'Accept: application/json' \
      --data-urlencode "grant_type=refresh_token" \
      --data-urlencode "client_id=ast-app" \
      --data-urlencode "refresh_token=${APIKEY}")
  else
    echo "ERROR: No credentials found. Set APIKEY or CLIENT_ID+CLIENT_SECRET in .env" >&2
    exit 1
  fi

  ACCESS_TOKEN=$(echo "${token_response}" | jq -r '.access_token')
  if [ -z "${ACCESS_TOKEN}" ] || [ "${ACCESS_TOKEN}" = "null" ]; then
    echo "ERROR: Failed to obtain access token." >&2
    echo "Response: ${token_response}" >&2
    exit 1
  fi

  local expires_in
  expires_in=$(echo "${token_response}" | jq -r '.expires_in // 1800')
  local expires_at
  expires_at=$(( now + expires_in - 60 ))  # 60s safety buffer

  # Write cache file atomically with restricted permissions
  local tmp_file
  tmp_file=$(mktemp "${token_file}.XXXXXX")
  (umask 077; jq -n --arg t "${ACCESS_TOKEN}" --argjson e "${expires_at}" \
    '{"access_token": $t, "expires_at": $e}' > "${tmp_file}" && mv "${tmp_file}" "${token_file}")

  cx_log "Token obtained (expires in ${expires_in}s, cached)"
}

# ---------------------------------------------------------------------------
# cx_get URL
# Authenticated GET request with standard Accept header.
# ---------------------------------------------------------------------------
cx_get() {
  local url="$1"
  cx_curl --silent --fail --request GET "${url}" \
    --header "Authorization: Bearer ${ACCESS_TOKEN}" \
    --header 'Accept: application/json; version=1.0'
}

# ---------------------------------------------------------------------------
# cx_paginate URL ARRAY_KEY [LIMIT]
# Fetches all pages from a list endpoint and outputs a merged JSON array.
# URL should include any query params (pagination params are appended).
# ARRAY_KEY is the JSON key containing the array (e.g., "projects").
# LIMIT is the page size (default: 100).
# Safety cap: stops after 100 pages (10,000 items at default limit).
# ---------------------------------------------------------------------------
cx_paginate() {
  local base_url="$1"
  local array_key="$2"
  local limit="${3:-100}"
  local separator="?"
  if [[ "${base_url}" == *"?"* ]]; then
    separator="&"
  fi

  local offset=0
  local all_items="[]"
  local max_pages=100
  local page=0

  while [ "${page}" -lt "${max_pages}" ]; do
    local page_url="${base_url}${separator}offset=${offset}&limit=${limit}"
    local response
    response=$(cx_get "${page_url}")

    local page_items
    page_items=$(echo "${response}" | jq ".${array_key} // []")
    local page_size
    page_size=$(echo "${page_items}" | jq 'length')

    all_items=$(echo "${all_items}" "${page_items}" | jq -s '.[0] + .[1]')

    local total
    total=$(echo "${response}" | jq '.filteredTotalCount // .totalCount // empty')

    offset=$((offset + limit))
    page=$((page + 1))

    # Stop when: empty page, or we've fetched past the reported total
    if [ "${page_size}" -eq 0 ]; then
      break
    fi
    if [ -n "${total}" ] && [ "${offset}" -ge "${total}" ]; then
      break
    fi

    cx_vlog "Paginating ${array_key}: fetched ${offset}/${total}..."
  done

  echo "${all_items}"
}

# ---------------------------------------------------------------------------
# cx_resolve_project_ids
# Resolves scope flags to a JSON array of project IDs.
#
# Reads PROJECT_ID and APPLICATION_ID globals (set by the calling script).
#   - PROJECT_ID set       → ["<PROJECT_ID>"]
#   - APPLICATION_ID set   → fetches app, extracts projectIds[]
#   - Neither              → fetches all projects, extracts ids
#   - Both                 → error
#
# Requires: cx_authenticate must have been called.
# Output: JSON array of project ID strings to stdout.
# ---------------------------------------------------------------------------
cx_resolve_project_ids() {
  if [ -n "${PROJECT_ID:-}" ] && [ -n "${APPLICATION_ID:-}" ]; then
    echo "ERROR: Cannot specify both --project-id and --application-id" >&2
    return 1
  fi

  if [ -n "${PROJECT_ID:-}" ]; then
    jq -n --arg id "${PROJECT_ID}" '[$id]'
    return 0
  fi

  if [ -n "${APPLICATION_ID:-}" ]; then
    local app_list
    app_list=$(cx_paginate "${BASE}/api/applications" "applications")
    local project_ids
    project_ids=$(echo "${app_list}" | jq -r --arg aid "${APPLICATION_ID}" \
      '[.[] | select(.id == $aid) | .projectIds[]?] | unique')
    if [ "$(echo "${project_ids}" | jq 'length')" -eq 0 ]; then
      echo "ERROR: Application ${APPLICATION_ID} not found or has no projects" >&2
      return 1
    fi
    echo "${project_ids}"
    return 0
  fi

  # Tenant-wide: fetch all project IDs
  local all_projects
  all_projects=$(cx_paginate "${BASE}/api/projects" "projects")
  echo "${all_projects}" | jq '[.[].id]'
}

# ---------------------------------------------------------------------------
# cx_date_range PERIOD RANGE
# Pure function — no API calls. Generates a JSON array of time buckets.
#
# PERIOD: "monthly", "quarterly", or "yearly"
# RANGE:  Number of periods back from the current period (default: 6)
#
# Output: JSON array ordered most-recent-first:
#   [{"period": "2026-03", "start": "2026-03-01T00:00:00Z", "end": "2026-03-31T23:59:59Z"}, ...]
#
# Period label formats:
#   monthly   → YYYY-MM
#   quarterly → YYYY-Q1, YYYY-Q2, YYYY-Q3, YYYY-Q4
#   yearly    → YYYY
# ---------------------------------------------------------------------------
cx_date_range() {
  local period_type="${1:?cx_date_range requires PERIOD (monthly|quarterly|yearly)}"
  local range="${2:-6}"

  jq -n --arg period_type "${period_type}" --argjson range "${range}" '
    def pad2: tostring | if length < 2 then "0" + . else . end;
    def days_in_month(y; m):
      if m == 2 then (if (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0) then 29 else 28 end)
      elif [4,6,9,11] | index(m) then 30
      else 31 end;

    # Current date components
    (now | strftime("%Y") | tonumber) as $cur_year |
    (now | strftime("%m") | tonumber) as $cur_month |

    if $period_type == "monthly" then
      [range($range)] | map(. as $i |
        # Subtract $i months from current
        (($cur_year * 12 + $cur_month - 1 - $i) / 12 | floor) as $y |
        (($cur_year * 12 + $cur_month - 1 - $i) % 12 + 1) as $m |
        {
          period: "\($y)-\($m | pad2)",
          start: "\($y)-\($m | pad2)-01T00:00:00Z",
          end: "\($y)-\($m | pad2)-\(days_in_month($y; $m) | pad2)T23:59:59Z"
        }
      )
    elif $period_type == "quarterly" then
      # Current quarter: Q1=1-3, Q2=4-6, Q3=7-9, Q4=10-12
      (($cur_month - 1) / 3 | floor) as $cur_q |
      [range($range)] | map(. as $i |
        ($cur_q - $i) as $q_offset |
        ($cur_year + (($q_offset) / 4 | floor)) as $y |
        ((($q_offset % 4) + 4) % 4) as $q |
        ($q * 3 + 1) as $start_month |
        ($q * 3 + 3) as $end_month |
        {
          period: "\($y)-Q\($q + 1)",
          start: "\($y)-\($start_month | pad2)-01T00:00:00Z",
          end: "\($y)-\($end_month | pad2)-\(days_in_month($y; $end_month) | pad2)T23:59:59Z"
        }
      )
    elif $period_type == "yearly" then
      [range($range)] | map(. as $i |
        ($cur_year - $i) as $y |
        {
          period: "\($y)",
          start: "\($y)-01-01T00:00:00Z",
          end: "\($y)-12-31T23:59:59Z"
        }
      )
    else
      error("cx_date_range: unknown period type: \($period_type)")
    end
  '
}

# ---------------------------------------------------------------------------
# cx_format_csv FIELD1 FIELD2 ...
# Reads a JSON array from stdin and outputs RFC 4180 CSV to stdout.
# Fields are jq expressions evaluated against each array element.
# The field names (with dots/brackets stripped) become the CSV header.
#
# Example:
#   echo '[{"name":"a","id":1}]' | cx_format_csv .name .id
#   → "name","id"
#     "a",1
# ---------------------------------------------------------------------------
cx_format_csv() {
  local fields=("$@")
  if [ ${#fields[@]} -eq 0 ]; then
    echo "ERROR: cx_format_csv requires at least one field" >&2
    return 1
  fi

  # Build jq expression for header and rows
  local header_parts=()
  local row_parts=()
  for f in "${fields[@]}"; do
    # Strip leading dot and brackets for header name
    local name="${f#.}"
    name="${name//[\[\]]/}"
    header_parts+=("\"${name}\"")
    row_parts+=("${f}")
  done

  local header
  header=$(IFS=','; echo "${header_parts[*]}")

  # Build jq row expression: [.field1, .field2, ...] | @csv
  local jq_fields
  jq_fields=$(IFS=','; echo "${row_parts[*]}")

  # Capture stdin first to avoid split-read issues
  local json
  json=$(cat)

  echo "${header}"
  echo "${json}" | jq -r ".[] | [${jq_fields}] | @csv"
}

# ---------------------------------------------------------------------------
# cx_format_table FIELD1 FIELD2 ...
# Reads a JSON array from stdin and outputs a markdown table to stdout.
# Fields are jq expressions evaluated against each array element.
#
# Example:
#   echo '[{"name":"a","id":1}]' | cx_format_table .name .id
#   → | name | id |
#     |------|-----|
#     | a    | 1   |
# ---------------------------------------------------------------------------
cx_format_table() {
  local fields=("$@")
  if [ ${#fields[@]} -eq 0 ]; then
    echo "ERROR: cx_format_table requires at least one field" >&2
    return 1
  fi

  # Build header names
  local header_names=()
  for f in "${fields[@]}"; do
    local name="${f#.}"
    name="${name//[\[\]]/}"
    header_names+=("${name}")
  done

  # Build jq row expression
  local jq_fields
  jq_fields=$(IFS=','; echo "${fields[*]}")

  # Use jq to produce the full table
  local json
  json=$(cat)

  # Header row
  local header="| "
  local separator="| "
  for name in "${header_names[@]}"; do
    header="${header}${name} | "
    separator="${separator}--- | "
  done
  echo "${header}"
  echo "${separator}"

  # Data rows
  echo "${json}" | jq -r ".[] | [${jq_fields}] | \"| \" + (map(if . == null then \"\" else tostring end) | join(\" | \")) + \" |\""
}
