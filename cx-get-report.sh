#!/usr/bin/env bash
#
# Generate and download a Checkmarx report for a scan.
# Polls until the report is ready, then downloads to a local file.
#
# Usage: ./cx-get-report.sh [-v|--verbose] --scan-id ID --project-id ID [--format FMT] [--output FILE]
#
# Examples:
#   ./cx-get-report.sh --scan-id "uuid" --project-id "uuid"
#   ./cx-get-report.sh --scan-id "uuid" --project-id "uuid" --format json
#   ./cx-get-report.sh --scan-id "uuid" --project-id "uuid" --output my-report.pdf
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# Parse script-specific flags
SCAN_ID=""
PROJECT_ID=""
FORMAT="pdf"
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-id)    SCAN_ID="$2"; shift 2 ;;
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --format)     FORMAT="$2"; shift 2 ;;
    --output)     OUTPUT="$2"; shift 2 ;;
    *)            echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${SCAN_ID}" ] || [ -z "${PROJECT_ID}" ]; then
  echo "Usage: $0 [-v|--verbose] --scan-id ID --project-id ID [--format FMT] [--output FILE]" >&2
  echo "  --format: pdf (default), json, csv, sarif" >&2
  exit 1
fi

# Default output filename
if [ -z "${OUTPUT}" ]; then
  OUTPUT="report-${SCAN_ID:0:8}.${FORMAT}"
fi

source "${SCRIPT_DIR}/.env"
cx_authenticate

# Step 1: Create report
cx_log "Creating ${FORMAT} report for scan ${SCAN_ID:0:8}..."

REPORT_BODY=$(jq -n \
  --arg sid "${SCAN_ID}" \
  --arg pid "${PROJECT_ID}" \
  --arg fmt "${FORMAT}" \
  '{
    reportName: "scan-report",
    reportType: "cli",
    fileFormat: $fmt,
    data: {
      scanId: $sid,
      projectId: $pid,
      sections: ["ScanSummary", "ExecutiveSummary", "ScanResults"],
      scanners: ["SAST", "SCA", "KICS"]
    }
  }')

REPORT_RESPONSE=$(cx_curl --silent --fail --request POST "${BASE}/api/reports" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --data "${REPORT_BODY}")

REPORT_ID=$(echo "${REPORT_RESPONSE}" | jq -r '.reportId')
if [ -z "${REPORT_ID}" ] || [ "${REPORT_ID}" = "null" ]; then
  echo "ERROR: Failed to create report." >&2
  echo "Response: ${REPORT_RESPONSE}" >&2
  exit 1
fi

cx_vlog "Report ID: ${REPORT_ID}"

# Step 2: Poll for completion (max 5 minutes)
cx_log "Waiting for report generation..."
MAX_ATTEMPTS=60
ATTEMPT=0
STATUS="requested"

while [ "${STATUS}" != "completed" ] && [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; do
  sleep 5
  STATUS_RESPONSE=$(cx_get "${BASE}/api/reports/${REPORT_ID}?returnUrl=true")
  STATUS=$(echo "${STATUS_RESPONSE}" | jq -r '.status')
  cx_vlog "Report status: ${STATUS} (attempt ${ATTEMPT}/${MAX_ATTEMPTS})"

  if [ "${STATUS}" = "failed" ]; then
    echo "ERROR: Report generation failed." >&2
    echo "${STATUS_RESPONSE}" | jq . >&2
    exit 1
  fi

  ATTEMPT=$((ATTEMPT + 1))
done

if [ "${STATUS}" != "completed" ]; then
  echo "ERROR: Report generation timed out after $((MAX_ATTEMPTS * 5))s." >&2
  exit 1
fi

# Step 3: Download
cx_log "Downloading report to ${OUTPUT}..."
cx_curl --silent --fail --output "${OUTPUT}" \
  --request GET "${BASE}/api/reports/${REPORT_ID}/download" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}"

cx_log "Report saved: ${OUTPUT}"
