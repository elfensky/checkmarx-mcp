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
#
# Globals set by cx_parse_flags:
#   VERBOSE   — 0 or 1
#   DRY_RUN   — 0 or 1 (for future write scripts)
#   EXECUTE   — 0 or 1 (for future write scripts; --execute flips DRY_RUN off)

VERBOSE="${VERBOSE:-0}"
DRY_RUN="${DRY_RUN:-0}"
EXECUTE="${EXECUTE:-0}"
CX_POSITIONAL_ARGS=()

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
        if [[ "${arg}" == Bearer* ]]; then
          display_args+=("'Bearer <REDACTED>'")
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
