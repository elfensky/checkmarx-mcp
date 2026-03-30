#!/usr/bin/env bash
#
# checkmarx.trend-new-vs-fixed.sh
# =================================
# Period-over-period net change — the "are we introducing faster than fixing?" trend.
#
# For each time period, computes the delta in severity counts compared to
# the previous period. Negative net_change means improvement (fewer findings).
# Positive means regression. Supports all engines uniformly by diffing
# scan-summary counters.
#
# Internally uses scan-timeline.sh to select representative scans per
# period, then batch-fetches scan-summary and computes deltas.
#
# API Reference:
#   Uses: GET /api/scans (via scan-timeline.sh), GET /api/scan-summary
#   See also: docs/rest-api-reference.md § 11 (Results Summary API)
#
# Usage:
#   ./utils/checkmarx.trend-new-vs-fixed.sh [-v|--verbose] --period PERIOD [OPTIONS]
#
# Required:
#   --period P           Time granularity: monthly, quarterly, or yearly
#
# Scope (mutually exclusive):
#   --project-id ID      Single project UUID
#   --application-id ID  All projects in this application
#   (neither)            All projects in the tenant
#
# Options:
#   -v, --verbose        Print curl commands and derived URLs to stderr
#   --range N            Number of periods back (default: 6)
#   --engines E          Comma-separated engine filter (default: all)
#                        Values: sast, sca, kics, containers, apisec
#
# Output:
#   A JSON array of period objects to stdout, ordered most-recent-first:
#   [
#     {
#       "period": "2026-03",
#       "sast": {"critical": -2, "high": -5, ..., "net_change": -5},
#       "total": {"critical": -2, "high": -8, ..., "net_change": -9}
#     },
#     {
#       "period": "2025-10",
#       "sast": null, "total": null
#     }
#   ]
#
#   The oldest period has null values (no prior period to diff against).
#   Negative values = improvement. Positive = regression.
#   For multi-project scopes, deltas are summed across projects per period.
#
# Examples:
#   ./utils/checkmarx.trend-new-vs-fixed.sh --project-id "uuid" --period monthly --range 6
#   ./utils/checkmarx.trend-new-vs-fixed.sh --application-id "uuid" --period quarterly --range 4
#   ./utils/checkmarx.trend-new-vs-fixed.sh --period yearly --range 3 --engines sast,sca
#
# Composability:
#   # Net change as markdown table
#   ./utils/checkmarx.trend-new-vs-fixed.sh --project-id "$PID" --period monthly --range 6 \
#     | jq '[.[] | {period, net: .total.net_change}]' \
#     | cx_format_table .period .net
#
# Exit codes:
#   0  Success
#   1  Missing --period, conflicting scope, or API error
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
PERIOD=""
RANGE="6"
ENGINES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)      PROJECT_ID="$2"; shift 2 ;;
    --application-id)  APPLICATION_ID="$2"; shift 2 ;;
    --period)          PERIOD="$2"; shift 2 ;;
    --range)           RANGE="$2"; shift 2 ;;
    --engines)         ENGINES="$2"; shift 2 ;;
    *)                 echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${PERIOD}" ]; then
  echo "Usage: $0 [-v|--verbose] --period monthly|quarterly|yearly [--project-id ID | --application-id ID] [--range N] [--engines E]" >&2
  exit 1
fi

# --- Load credentials and authenticate (needed for scan-summary calls) ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Build scope flags for scan-timeline ---
SCOPE_FLAGS=()
[ -n "${PROJECT_ID}" ]     && SCOPE_FLAGS+=(--project-id "${PROJECT_ID}")
[ -n "${APPLICATION_ID}" ] && SCOPE_FLAGS+=(--application-id "${APPLICATION_ID}")

VERBOSE_FLAGS=()
[ "${VERBOSE}" -eq 1 ] && VERBOSE_FLAGS+=("-v")

# --- Get timeline ---
cx_log "Building scan timeline (${PERIOD} x ${RANGE})..."
TIMELINE=$("${SCRIPT_DIR}/checkmarx.scan-timeline.sh" \
  "${VERBOSE_FLAGS[@]+"${VERBOSE_FLAGS[@]}"}" \
  "${SCOPE_FLAGS[@]+"${SCOPE_FLAGS[@]}"}" \
  --period "${PERIOD}" \
  --range "${RANGE}")

# --- Collect unique non-null scan IDs ---
SCAN_IDS=$(echo "${TIMELINE}" | jq -r '[.[].scanId | select(. != null)] | unique | .[]')

if [ -z "${SCAN_IDS}" ]; then
  cx_log "No completed scans found in the specified range"
  echo "${TIMELINE}" | jq '[group_by(.period)[] | {period: .[0].period, sast: null, sca: null, kics: null, containers: null, apisec: null, total: null}]'
  exit 0
fi

# --- Batch fetch scan summaries ---
cx_log "Fetching scan summaries..."
SUMMARY_PARAMS=""
while IFS= read -r sid; do
  [ -n "${SUMMARY_PARAMS}" ] && SUMMARY_PARAMS="${SUMMARY_PARAMS}&"
  SUMMARY_PARAMS="${SUMMARY_PARAMS}scan-ids=${sid}"
done <<< "${SCAN_IDS}"

SUMMARIES=$(cx_get "${BASE}/api/scan-summary?${SUMMARY_PARAMS}&include-severity-status=true")

# --- Engine mapping and filter ---
ENGINE_MAP='{"sast":"sastCounters","sca":"scaCounters","kics":"kicsCounters","containers":"scaContainersCounters","apisec":"apiSecCounters"}'

if [ -z "${ENGINES}" ]; then
  ENGINES="sast,sca,kics,containers,apisec"
fi

# --- First compute severity snapshots per period (same as trend-severity),
#     then diff consecutive periods ---
TMP_TIMELINE=$(mktemp)
TMP_SUMMARIES=$(mktemp)
trap 'rm -f "${TMP_TIMELINE}" "${TMP_SUMMARIES}"' EXIT
echo "${TIMELINE}" > "${TMP_TIMELINE}"
echo "${SUMMARIES}" > "${TMP_SUMMARIES}"

jq -n \
  --slurpfile timeline "${TMP_TIMELINE}" \
  --slurpfile summaries "${TMP_SUMMARIES}" \
  --argjson engine_map "${ENGINE_MAP}" \
  --arg engines "${ENGINES}" '
  $timeline[0] as $tl |
  $summaries[0] as $sum |
  $tl |

  ($engines | split(",")) as $engine_list |

  def severity_counts:
    if . == null then null
    else
      (.severityCounters // []) as $sev |
      {
        critical: ([$sev[] | select(.severity == "CRITICAL") | .counter] | add // 0),
        high:     ([$sev[] | select(.severity == "HIGH") | .counter] | add // 0),
        medium:   ([$sev[] | select(.severity == "MEDIUM") | .counter] | add // 0),
        low:      ([$sev[] | select(.severity == "LOW") | .counter] | add // 0),
        info:     ([$sev[] | select(.severity == "INFO") | .counter] | add // 0)
      } | . + {total: (.critical + .high + .medium + .low + .info)}
    end;

  def sum_severity(a; b):
    if a == null and b == null then null
    elif a == null then b
    elif b == null then a
    else {
      critical: (a.critical + b.critical),
      high: (a.high + b.high),
      medium: (a.medium + b.medium),
      low: (a.low + b.low),
      info: (a.info + b.info),
      total: (a.total + b.total)
    } end;

  # Diff two severity objects: newer - older
  def diff_severity(newer; older):
    if newer == null or older == null then null
    else {
      critical: (newer.critical - older.critical),
      high: (newer.high - older.high),
      medium: (newer.medium - older.medium),
      low: (newer.low - older.low),
      info: (newer.info - older.info)
    } | . + {net_change: (.critical + .high + .medium + .low + .info)}
    end;

  # Step 1: Build severity snapshots per period (same logic as trend-severity)
  (group_by(.period) | sort_by(.[0].period) | reverse | map(
    .[0].period as $period |
    map(
      .scanId as $sid |
      if $sid == null then null
      else ($sum.scansSummaries // [] | map(select(.scanId == $sid)) | .[0]) // null
      end
    ) as $period_summaries |
    (reduce $engine_list[] as $eng (
      {};
      ($engine_map[$eng]) as $counter_key |
      . + {
        ($eng): (reduce $period_summaries[] as $ps (
          null;
          if $ps == null then .
          else sum_severity(.; ($ps[$counter_key] | severity_counts))
          end
        ))
      }
    )) as $engine_counts |
    (reduce ($engine_counts | to_entries[]) as $e (
      null;
      sum_severity(.; $e.value)
    )) as $total_counts |
    {period: $period} + $engine_counts + {total: $total_counts}
  )) as $snapshots |

  # Step 2: Diff consecutive periods (newer - older)
  [range($snapshots | length)] | map(. as $i |
    $snapshots[$i] as $current |
    if $i == (($snapshots | length) - 1) then
      # Oldest period: no prior to diff against
      {period: $current.period} +
      (reduce $engine_list[] as $eng ({}; . + {($eng): null})) +
      {total: null}
    else
      $snapshots[$i + 1] as $prev |
      {period: $current.period} +
      (reduce $engine_list[] as $eng (
        {};
        . + {($eng): diff_severity($current[$eng]; $prev[$eng])}
      )) as $engine_deltas |
      $engine_deltas + {
        period: $current.period,
        total: (reduce ($engine_deltas | to_entries[] | select(.key != "period")) as $e (
          null;
          if $e.value == null then .
          elif . == null then $e.value
          else {
            critical: (.critical + $e.value.critical),
            high: (.high + $e.value.high),
            medium: (.medium + $e.value.medium),
            low: (.low + $e.value.low),
            info: (.info + $e.value.info),
            net_change: (.net_change + $e.value.net_change)
          } end
        ))
      }
    end
  )
'
