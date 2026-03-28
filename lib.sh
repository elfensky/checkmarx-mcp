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
#
# Globals set by cx_parse_flags:
#   VERBOSE   — 0 or 1
#   DRY_RUN   — 0 or 1 (for future write scripts)
#   EXECUTE   — 0 or 1 (for future write scripts; --execute flips DRY_RUN off)

VERBOSE="${VERBOSE:-0}"
DRY_RUN="${DRY_RUN:-0}"
EXECUTE="${EXECUTE:-0}"
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
