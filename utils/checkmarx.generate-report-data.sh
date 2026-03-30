#!/usr/bin/env bash
#
# checkmarx.generate-report-data.sh
# ===================================
# Generate a Power BI-ready CSV data pack of security trend metrics.
#
# Orchestrates the trend scripts to produce two CSV files covering all
# engines and granularities, ready for import into Power BI, Excel, or
# any BI tool. Each CSV has "granularity" and "engine" columns so the
# BI tool can slice and filter without multiple files.
#
# Produces:
#   trend-severity.csv      — absolute severity counts per period
#   trend-new-vs-fixed.csv  — period-over-period net change
#   metadata.json            — generation timestamp, scope, parameters
#
# API Reference:
#   Uses: trend-severity.sh, trend-new-vs-fixed.sh (which use scan-timeline.sh + scan-summary API)
#
# Usage:
#   ./utils/checkmarx.generate-report-data.sh [-v|--verbose] [OPTIONS]
#
# Scope (mutually exclusive):
#   --project-id ID      Single project UUID
#   --application-id ID  All projects in this application
#   (neither)            All projects in the tenant
#
# Options:
#   -v, --verbose        Print curl commands and progress to stderr
#   --output-dir DIR     Output directory (default: report-data/YYYY-MM-DD)
#   --engines E          Comma-separated engine filter (default: all)
#                        Values: sast, sca, kics, containers, apisec
#
# Output:
#   Files written to the output directory:
#
#   trend-severity.csv:
#     granularity,engine,period,critical,high,medium,low,info,total
#     monthly,sast,2026-03,5,42,120,300,15,482
#     ...
#
#   trend-new-vs-fixed.csv:
#     granularity,engine,period,critical,high,medium,low,info,net_change
#     monthly,sast,2026-03,-2,-5,3,-1,0,-5
#     ...
#
#   metadata.json:
#     {"generated_at": "...", "scope": "...", "engines": [...], ...}
#
# Examples:
#   ./utils/checkmarx.generate-report-data.sh --project-id "uuid"
#   ./utils/checkmarx.generate-report-data.sh --application-id "uuid" --engines sast,sca
#   ./utils/checkmarx.generate-report-data.sh --output-dir /tmp/report -v
#
# Exit codes:
#   0  Success
#   1  Conflicting scope flags, API error, or write failure
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
PROJECT_ID=""
APPLICATION_ID=""
OUTPUT_DIR=""
ENGINES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)      PROJECT_ID="$2"; shift 2 ;;
    --application-id)  APPLICATION_ID="$2"; shift 2 ;;
    --output-dir)      OUTPUT_DIR="$2"; shift 2 ;;
    --engines)         ENGINES="$2"; shift 2 ;;
    *)                 echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Defaults ---
if [ -z "${OUTPUT_DIR}" ]; then
  OUTPUT_DIR="report-data/$(date +%Y-%m-%d)"
fi

if [ -z "${ENGINES}" ]; then
  ENGINES="sast,sca,kics,containers,apisec"
fi

# --- Create output directory ---
mkdir -p "${OUTPUT_DIR}"
cx_log "Output directory: ${OUTPUT_DIR}"

# --- Build scope flags ---
SCOPE_FLAGS=()
[ -n "${PROJECT_ID}" ]     && SCOPE_FLAGS+=(--project-id "${PROJECT_ID}")
[ -n "${APPLICATION_ID}" ] && SCOPE_FLAGS+=(--application-id "${APPLICATION_ID}")

VERBOSE_FLAGS=()
[ "${VERBOSE}" -eq 1 ] && VERBOSE_FLAGS+=("-v")

# --- Define granularities and their ranges ---
# Monthly: 12 periods, Quarterly: 8 periods, Yearly: 3 periods
GRANULARITIES=("monthly:12" "quarterly:8" "yearly:3")

# --- Initialize CSV files with headers ---
SEVERITY_CSV="${OUTPUT_DIR}/trend-severity.csv"
DELTA_CSV="${OUTPUT_DIR}/trend-new-vs-fixed.csv"

echo "granularity,engine,period,critical,high,medium,low,info,total" > "${SEVERITY_CSV}"
echo "granularity,engine,period,critical,high,medium,low,info,net_change" > "${DELTA_CSV}"

# --- Generate data for each granularity ---
for GRAN_SPEC in "${GRANULARITIES[@]}"; do
  GRAN="${GRAN_SPEC%%:*}"
  RANGE="${GRAN_SPEC##*:}"

  cx_log "Generating ${GRAN} data (${RANGE} periods)..."

  # --- Severity trend ---
  SEVERITY_JSON=$("${SCRIPT_DIR}/checkmarx.trend-severity.sh" \
    "${VERBOSE_FLAGS[@]+"${VERBOSE_FLAGS[@]}"}" \
    "${SCOPE_FLAGS[@]+"${SCOPE_FLAGS[@]}"}" \
    --period "${GRAN}" \
    --range "${RANGE}" \
    --engines "${ENGINES}")

  # Convert JSON to CSV rows (one row per engine per period)
  echo "${SEVERITY_JSON}" | jq -r --arg gran "${GRAN}" '
    .[] | .period as $period |
    to_entries[] |
    select(.key != "period" and .key != "total" and .value != null) |
    "\($gran),\(.key),\($period),\(.value.critical),\(.value.high),\(.value.medium),\(.value.low),\(.value.info),\(.value.total)"
  ' >> "${SEVERITY_CSV}"

  # Add total rows
  echo "${SEVERITY_JSON}" | jq -r --arg gran "${GRAN}" '
    .[] | select(.total != null) |
    "\($gran),total,\(.period),\(.total.critical),\(.total.high),\(.total.medium),\(.total.low),\(.total.info),\(.total.total)"
  ' >> "${SEVERITY_CSV}"

  # --- New vs Fixed trend ---
  DELTA_JSON=$("${SCRIPT_DIR}/checkmarx.trend-new-vs-fixed.sh" \
    "${VERBOSE_FLAGS[@]+"${VERBOSE_FLAGS[@]}"}" \
    "${SCOPE_FLAGS[@]+"${SCOPE_FLAGS[@]}"}" \
    --period "${GRAN}" \
    --range "${RANGE}" \
    --engines "${ENGINES}")

  echo "${DELTA_JSON}" | jq -r --arg gran "${GRAN}" '
    .[] | .period as $period |
    to_entries[] |
    select(.key != "period" and .key != "total" and .value != null) |
    "\($gran),\(.key),\($period),\(.value.critical),\(.value.high),\(.value.medium),\(.value.low),\(.value.info),\(.value.net_change)"
  ' >> "${DELTA_CSV}"

  echo "${DELTA_JSON}" | jq -r --arg gran "${GRAN}" '
    .[] | select(.total != null) |
    "\($gran),total,\(.period),\(.total.critical),\(.total.high),\(.total.medium),\(.total.low),\(.total.info),\(.total.net_change)"
  ' >> "${DELTA_CSV}"
done

# --- Write metadata ---
SCOPE_DESC="tenant"
[ -n "${PROJECT_ID}" ]     && SCOPE_DESC="project:${PROJECT_ID}"
[ -n "${APPLICATION_ID}" ] && SCOPE_DESC="application:${APPLICATION_ID}"

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg scope "${SCOPE_DESC}" \
  --arg engines "${ENGINES}" \
  --arg output_dir "${OUTPUT_DIR}" \
  '{
    generated_at: $generated_at,
    scope: $scope,
    engines: ($engines | split(",")),
    granularities: {monthly: 12, quarterly: 8, yearly: 3},
    files: ["trend-severity.csv", "trend-new-vs-fixed.csv"],
    output_dir: $output_dir
  }' > "${OUTPUT_DIR}/metadata.json"

# --- Summary ---
SEV_ROWS=$(( $(wc -l < "${SEVERITY_CSV}") - 1 ))
DELTA_ROWS=$(( $(wc -l < "${DELTA_CSV}") - 1 ))
cx_log "Done! Generated:"
cx_log "  ${SEVERITY_CSV} (${SEV_ROWS} data rows)"
cx_log "  ${DELTA_CSV} (${DELTA_ROWS} data rows)"
cx_log "  ${OUTPUT_DIR}/metadata.json"
