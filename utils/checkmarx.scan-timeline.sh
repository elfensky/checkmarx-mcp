#!/usr/bin/env bash
#
# checkmarx.scan-timeline.sh
# ===========================
# Build a timeline of representative scans per time period.
#
# For a given scope (project, application, or entire tenant) and time
# granularity (monthly, quarterly, yearly), returns the latest Completed
# scan in each period. This is the reusable building block for all
# trend-based metrics — downstream scripts consume the scan IDs to
# fetch severity counts, deltas, or any other per-scan data.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/scans (to enumerate scans per project)
#   Auth:       Bearer token (obtained via cx_authenticate)
#   See also:   docs/rest-api-reference.md § 3.2 (Scans API)
#
# Usage:
#   ./utils/checkmarx.scan-timeline.sh [-v|--verbose] --period PERIOD [OPTIONS]
#
# Required:
#   --period P           Time granularity: monthly, quarterly, or yearly
#
# Scope (mutually exclusive — pick one or omit for tenant-wide):
#   --project-id ID      Single project UUID
#   --application-id ID  All projects in this application
#   (neither)            All projects in the tenant
#
# Options:
#   -v, --verbose        Print curl commands and derived URLs to stderr
#   --range N            Number of periods back (default: 6)
#   --branch B           Filter scans by branch name
#
# Output:
#   A JSON array of timeline entries to stdout, ordered most-recent-first.
#   Each entry represents one project in one time period:
#   {
#     "period": "2026-03",
#     "scanId": "abc-123" | null,
#     "projectId": "p1",
#     "projectName": "my-project",
#     "createdAt": "2026-03-27T21:07:04Z" | null
#   }
#
#   scanId/createdAt are null when no Completed scan exists in that period.
#   For multi-project scopes, entries appear for every project in every period.
#
# Examples:
#   ./utils/checkmarx.scan-timeline.sh --project-id "uuid" --period monthly --range 6
#   ./utils/checkmarx.scan-timeline.sh --application-id "uuid" --period quarterly --range 4
#   ./utils/checkmarx.scan-timeline.sh --period yearly --range 3   # tenant-wide
#
# Composability:
#   # Feed into scan-summary for severity trends
#   ./utils/checkmarx.scan-timeline.sh --project-id "$PID" --period monthly --range 6 \
#     | jq -r '[.[].scanId | select(. != null)] | unique[]' \
#     | xargs -I{} ./utils/checkmarx.scan-summary.sh --scan-id {}
#
# Exit codes:
#   0  Success
#   1  Missing --period, conflicting scope flags, or API error
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
BRANCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)      PROJECT_ID="$2"; shift 2 ;;
    --application-id)  APPLICATION_ID="$2"; shift 2 ;;
    --period)          PERIOD="$2"; shift 2 ;;
    --range)           RANGE="$2"; shift 2 ;;
    --branch)          BRANCH="$2"; shift 2 ;;
    *)                 echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${PERIOD}" ]; then
  echo "Usage: $0 [-v|--verbose] --period monthly|quarterly|yearly [--project-id ID | --application-id ID] [--range N] [--branch B]" >&2
  exit 1
fi

case "${PERIOD}" in
  monthly|quarterly|yearly) ;;
  *) echo "ERROR: --period must be monthly, quarterly, or yearly (got: ${PERIOD})" >&2; exit 1 ;;
esac

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Resolve scope to project IDs ---
PIDS_JSON=$(cx_resolve_project_ids)
cx_vlog "Resolved $(echo "${PIDS_JSON}" | jq 'length') project(s)"

# --- Generate time buckets ---
BUCKETS=$(cx_date_range "${PERIOD}" "${RANGE}")
cx_vlog "Generated ${RANGE} ${PERIOD} buckets"

# --- For each project, fetch scans and assign to buckets ---
TIMELINE="[]"

for PID in $(echo "${PIDS_JSON}" | jq -r '.[]'); do
  cx_vlog "Fetching scans for project ${PID}..."

  # Build query: completed scans, sorted oldest-first so we can walk forward
  SCAN_URL="${BASE}/api/scans?project-id=${PID}&statuses=Completed&sort=%2Bcreated_at"
  if [ -n "${BRANCH}" ]; then
    SCAN_URL="${SCAN_URL}&branch=$(cx_urlencode "${BRANCH}")"
  fi

  # Fetch all completed scans for this project
  SCANS=$(cx_paginate "${SCAN_URL}" "scans")
  SCAN_COUNT=$(echo "${SCANS}" | jq 'length')
  cx_vlog "  Found ${SCAN_COUNT} completed scan(s)"

  # Get project name from first scan, or "unknown"
  PNAME=$(echo "${SCANS}" | jq -r '.[0].projectName // "unknown"')

  # Assign scans to buckets: for each bucket, find the latest scan whose
  # createdAt falls within [start, end]. Pipe scans via stdin to avoid
  # "Argument list too long" errors on projects with thousands of scans.
  PROJECT_TIMELINE=$(echo "${SCANS}" | jq \
    --argjson buckets "${BUCKETS}" \
    --arg pid "${PID}" \
    --arg pname "${PNAME}" \
    '
    . as $scans |
    $buckets | map(. as $bucket |
      # Find scans within this bucket
      ($scans | map(
        select(.createdAt >= $bucket.start and .createdAt <= $bucket.end)
      )) as $matches |
      # Pick the latest (last in ascending-sorted array)
      if ($matches | length) > 0 then
        ($matches | last) as $scan |
        {
          period: $bucket.period,
          scanId: $scan.id,
          projectId: $pid,
          projectName: ($scan.projectName // $pname),
          createdAt: $scan.createdAt
        }
      else
        {
          period: $bucket.period,
          scanId: null,
          projectId: $pid,
          projectName: $pname,
          createdAt: null
        }
      end
    )
    ')

  TIMELINE=$(echo "${TIMELINE}" "${PROJECT_TIMELINE}" | jq -s '.[0] + .[1]')
done

echo "${TIMELINE}"
