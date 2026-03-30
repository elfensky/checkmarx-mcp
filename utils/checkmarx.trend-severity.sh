#!/usr/bin/env bash
#
# checkmarx.trend-severity.sh
# ============================
# Severity counts over time — the "are we getting better?" trend.
#
# For each time period, returns vulnerability counts broken down by
# severity (CRITICAL, HIGH, MEDIUM, LOW, INFO) and engine (SAST, SCA,
# KICS, Containers, API Security). Supports monthly, quarterly, and
# yearly granularity at project, application, or tenant scope.
#
# Internally uses scan-timeline.sh to select representative scans per
# period, then batch-fetches scan-summary for all scans in one request.
#
# API Reference:
#   Uses: GET /api/scans (via scan-timeline.sh), GET /api/scan-summary
#   See also: docs/rest-api-reference.md § 11 (Results Summary API)
#
# Usage:
#   ./utils/checkmarx.trend-severity.sh [-v|--verbose] --period PERIOD [OPTIONS]
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
#       "sast": {"critical": 5, "high": 42, "medium": 120, "low": 300, "info": 15, "total": 482},
#       "sca": {"critical": 1, "high": 12, ...},
#       "total": {"critical": 6, "high": 54, ...}
#     }
#   ]
#
#   Periods with no completed scan have null values for all engines.
#   When --engines is specified, only those engines + "total" appear.
#   For multi-project scopes, counts are summed across projects per period.
#
# Examples:
#   ./utils/checkmarx.trend-severity.sh --project-id "uuid" --period monthly --range 6
#   ./utils/checkmarx.trend-severity.sh --application-id "uuid" --period quarterly --range 4
#   ./utils/checkmarx.trend-severity.sh --period yearly --range 3 --engines sast,sca
#
# Composability:
#   # Severity trend as CSV
#   ./utils/checkmarx.trend-severity.sh --project-id "$PID" --period monthly --range 6 \
#     | jq '[.[] | {period, high: .total.high, critical: .total.critical}]' \
#     | cx_format_csv .period .critical .high
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
  # Return all-null periods
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
# Map user-facing engine names to API counter keys
ENGINE_MAP='{"sast":"sastCounters","sca":"scaCounters","kics":"kicsCounters","containers":"scaContainersCounters","apisec":"apiSecCounters"}'

# Default to all engines if not specified
if [ -z "${ENGINES}" ]; then
  ENGINES="sast,sca,kics,containers,apisec"
fi

# --- Assemble trend output ---
# Write timeline and summaries to temp files, then use --slurpfile
# to avoid "Argument list too long" for large datasets.
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

  # Parse engine list
  ($engines | split(",")) as $engine_list |

  # Helper: extract severity counts from a counter object
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

  # Helper: sum two severity objects
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

  # Group timeline entries by period
  group_by(.period) | sort_by(.[0].period) | reverse | map(
    .[0].period as $period |

    # For each entry in this period (one per project), look up its scan summary
    map(
      .scanId as $sid |
      if $sid == null then null
      else
        ($sum.scansSummaries // [] | map(select(.scanId == $sid)) | .[0]) // null
      end
    ) as $period_summaries |

    # Build per-engine severity counts, summed across projects
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

    # Build total across all requested engines
    (reduce ($engine_counts | to_entries[]) as $e (
      null;
      sum_severity(.; $e.value)
    )) as $total_counts |

    {period: $period} + $engine_counts + {total: $total_counts}
  )
'
