#!/usr/bin/env bash
#
# checkmarx.get-report.sh
# =======================
# Generate and download a Checkmarx scan report.
#
# This is a three-step workflow:
#   1. Create a report request (POST /api/reports)
#   2. Poll for report completion (GET /api/reports/{id})
#   3. Download the generated file (GET /api/reports/{id}/download)
#
# The report includes findings from all configured scanners (SAST, SCA,
# KICS) with sections for scan summary, executive summary, and detailed
# results. Supports PDF, JSON, CSV, and SARIF output formats.
#
# API Reference:
#   Create:     POST {BASE_URI}/api/reports
#   Status:     GET  {BASE_URI}/api/reports/{id}?returnUrl=true
#   Download:   GET  {BASE_URI}/api/reports/{id}/download
#   Statuses:   requested → started → completed | failed
#   See also:   docs/rest-api-reference.md § 5 (Reports API)
#
# Usage:
#   ./utils/checkmarx.get-report.sh [-v|--verbose] --scan-id ID --project-id ID [--format FMT] [--output FILE]
#
# Required:
#   --scan-id ID       UUID of the scan to report on
#   --project-id ID    UUID of the project (required by the Reports API)
#
# Options:
#   -v, --verbose      Print curl commands and polling progress to stderr
#   --format FMT       Output format: pdf (default), json, csv, sarif
#   --output FILE      Output filename (default: ~/Downloads/checkmarx-reports/report-<scan-id-prefix>.<format>)
#
# Output:
#   Downloads the report file to the specified (or default) path.
#   Progress messages are written to stderr.
#
# Timing:
#   Report generation is asynchronous. This script polls every 5 seconds
#   for up to 5 minutes (60 attempts). Large scans with many findings
#   may take longer; increase MAX_ATTEMPTS if needed.
#
# Examples:
#   ./utils/checkmarx.get-report.sh --scan-id "uuid" --project-id "uuid"
#   ./utils/checkmarx.get-report.sh --scan-id "uuid" --project-id "uuid" --format json
#   ./utils/checkmarx.get-report.sh --scan-id "uuid" --project-id "uuid" --output my-report.pdf
#
# Composability:
#   # Full pipeline: project → latest scan → download report
#   PID=$(./utils/checkmarx.get-project.sh "my-project" | jq -r '.id')
#   SID=$(./utils/checkmarx.list-scans.sh --project-id "$PID" --statuses Completed --limit 1 | jq -r '.[0].id')
#   ./utils/checkmarx.get-report.sh --scan-id "$SID" --project-id "$PID"
#
# Exit codes:
#   0  Report downloaded successfully
#   1  Missing arguments, report generation failed, or timeout
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
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

# --- Default output filename (first 8 chars of scan UUID for brevity) ---
if [ -z "${OUTPUT}" ]; then
  OUTPUT="$(cx_output_dir)/report-${SCAN_ID:0:8}.${FORMAT}"
fi

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# =========================================================================
# Step 1: Create report request
# =========================================================================
cx_log "Creating ${FORMAT} report for scan ${SCAN_ID:0:8}..."

# Build the report request JSON using jq for proper escaping
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

# =========================================================================
# Step 2: Poll for report completion
# =========================================================================
# Reports are generated asynchronously. We poll every 5 seconds for up to
# 5 minutes (60 * 5s = 300s). Status transitions: requested → started → completed.
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

# =========================================================================
# Step 3: Download the report file
# =========================================================================
cx_log "Downloading report to ${OUTPUT}..."
cx_curl --silent --fail --output "${OUTPUT}" \
  --request GET "${BASE}/api/reports/${REPORT_ID}/download" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}"

cx_log "Report saved: ${OUTPUT}"
