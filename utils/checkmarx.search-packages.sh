#!/usr/bin/env bash
#
# checkmarx.search-packages.sh
# ==============================
# Search for a specific package across projects.
#
# Answers the question: "Which projects in our organisation use package X
# (at version Y)?" by scanning the SCA package inventory across project
# scans. Uses the efficient last-scan endpoint to get scan IDs, then
# fetches the SCA risk report for each to search for matching packages.
#
# Scope can be narrowed to a single project, an application, or run
# tenant-wide (default). When running across many projects, progress
# is logged to stderr.
#
# API Reference:
#   Uses: GET /api/projects/last-scan (project listing)
#         GET /api/sca/risk-management/risk-reports/{scan_id}/export (packages)
#   Auth: Bearer token (obtained via cx_authenticate)
#
# Usage:
#   ./utils/checkmarx.search-packages.sh [-v|--verbose] --package NAME [OPTIONS]
#
# Required:
#   --package NAME       Package name to search for (case-insensitive substring match)
#
# Scope (mutually exclusive):
#   --project-id ID      Single project UUID
#   --application-id ID  All projects in this application
#   (neither)            All projects in the tenant
#
# Options:
#   -v, --verbose        Print curl commands and derived URLs to stderr
#   --version VER        Also filter by version (exact match)
#   --direct-only        Only match direct dependencies (skip transitive)
#
# Output:
#   A JSON array of match objects to stdout. Each object includes:
#   {
#     "projectId": "...",
#     "projectName": "...",
#     "scanId": "...",
#     "package": {
#       "name": "axios", "version": "1.6.0", "packageManager": "Npm",
#       "isDirect": true, "vulnerabilities": 2, ...
#     }
#   }
#
#   If no matches are found, outputs an empty array [].
#
# Examples:
#   # Search tenant-wide
#   ./utils/checkmarx.search-packages.sh --package "axios"
#
#   # Search for exact version
#   ./utils/checkmarx.search-packages.sh --package "axios" --version "1.14.4"
#
#   # Search within an application, direct deps only
#   ./utils/checkmarx.search-packages.sh --package "log4j" --application-id "uuid" --direct-only
#
#   # Get just project names that use lodash
#   ./utils/checkmarx.search-packages.sh --package "lodash" \
#     | jq '[.[].projectName] | unique'
#
#   # CSV report of all axios usage
#   ./utils/checkmarx.search-packages.sh --package "axios" \
#     | jq '[.[] | {project: .projectName, name: .package.name,
#            version: .package.version, vulns: .package.vulnerabilities}]' \
#     | cx_format_csv .project .name .version .vulns
#
# Composability:
#   # Pipe into sca-packages for full details on a specific match
#   SID=$(./utils/checkmarx.search-packages.sh --package "axios" \
#     | jq -r '.[0].scanId')
#   ./utils/checkmarx.sca-packages.sh --scan-id "$SID" --package "axios"
#
# Exit codes:
#   0  Success (even if no matches found)
#   1  Missing --package, conflicting scope, or API error
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
PACKAGE=""
VERSION=""
PROJECT_ID=""
APPLICATION_ID=""
DIRECT_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --package)         PACKAGE="$2"; shift 2 ;;
    --version)         VERSION="$2"; shift 2 ;;
    --project-id)      PROJECT_ID="$2"; shift 2 ;;
    --application-id)  APPLICATION_ID="$2"; shift 2 ;;
    --direct-only)     DIRECT_ONLY=1; shift ;;
    *)                 echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${PACKAGE}" ]; then
  echo "Usage: $0 [-v|--verbose] --package NAME [--version VER] [--project-id ID | --application-id ID] [--direct-only]" >&2
  exit 1
fi

if [ -n "${PROJECT_ID}" ] && [ -n "${APPLICATION_ID}" ]; then
  echo "ERROR: Cannot specify both --project-id and --application-id" >&2
  exit 1
fi

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Resolve projects with their latest scan IDs ---
cx_log "Resolving projects..."

if [ -n "${PROJECT_ID}" ]; then
  # Single project — get its latest completed scan
  SCAN_DATA=$(cx_get "${BASE}/api/scans?project-id=${PROJECT_ID}&limit=1&sort=-created_at&statuses=Completed" \
    | jq -r '.scans[0].id // empty')
  if [ -z "${SCAN_DATA}" ]; then
    cx_log "No completed scans found for project ${PROJECT_ID}"
    echo "[]"
    exit 0
  fi
  # Get project name
  PROJECT_NAME=$(cx_get "${BASE}/api/projects/${PROJECT_ID}" | jq -r '.name // "unknown"')
  # Build a synthetic projects array for the loop below
  PROJECTS=$(jq -n --arg pid "${PROJECT_ID}" --arg pname "${PROJECT_NAME}" --arg sid "${SCAN_DATA}" \
    '[{projectId: $pid, projectName: $pname, scanId: $sid}]')
else
  # Use list-projects-last-scan.sh to efficiently get all projects + scan IDs
  DELEGATE_FLAGS=("--scan-status" "Completed")
  [ -n "${APPLICATION_ID}" ] && DELEGATE_FLAGS+=("--application-id" "${APPLICATION_ID}")
  [ "${VERBOSE}" -eq 1 ] && DELEGATE_FLAGS+=("-v")

  RAW_PROJECTS=$("${SCRIPT_DIR}/checkmarx.list-projects-last-scan.sh" "${DELEGATE_FLAGS[@]}")

  # Extract project ID, name, and the embedded scan ID
  PROJECTS=$(echo "${RAW_PROJECTS}" | jq '
    [.[] |
      {
        projectId:   (.id // .projectId),
        projectName: (.name // .projectName // "unknown"),
        scanId:      (.lastCompletedScanId // .lastScanInfo.id // .lastScan.id // null)
      }
      | select(.scanId != null)
    ]
  ')

  PROJECT_COUNT=$(echo "${PROJECTS}" | jq 'length')
  cx_log "Found ${PROJECT_COUNT} projects with completed scans"

  if [ "${PROJECT_COUNT}" -eq 0 ]; then
    echo "[]"
    exit 0
  fi
fi

# --- Search each project's SCA packages ---
TOTAL=$(echo "${PROJECTS}" | jq 'length')
MATCHES="[]"
CHECKED=0
SKIPPED=0

while IFS= read -r project_json; do
  PID=$(echo "${project_json}" | jq -r '.projectId')
  PNAME=$(echo "${project_json}" | jq -r '.projectName')
  SID=$(echo "${project_json}" | jq -r '.scanId')
  CHECKED=$((CHECKED + 1))

  cx_vlog "[$CHECKED/$TOTAL] Checking ${PNAME} (scan ${SID:0:8}...)"

  # Fetch SCA risk report for this scan
  REPORT=$(cx_get "${BASE}/api/sca/risk-management/risk-reports/${SID}/export?format=Json" 2>/dev/null) || {
    cx_vlog "WARN: Failed to fetch SCA report for scan ${SID:0:8} (project ${PNAME})"
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  # Extract packages and search for matches
  PKG_MATCHES=$(echo "${REPORT}" | jq \
    --arg pkg "${PACKAGE}" \
    --arg ver "${VERSION}" \
    --argjson directOnly "${DIRECT_ONLY}" \
    --arg pid "${PID}" \
    --arg pname "${PNAME}" \
    --arg sid "${SID}" '
    # Extract packages from known locations
    (if .packages then .packages
     elif .riskReportData.packages then .riskReportData.packages
     elif type == "array" then .
     else [] end) as $pkgs |

    [$pkgs[] |
      # Normalise
      {
        name:                  (.name // .packageName // .id // "unknown"),
        version:               (.version // .packageVersion // "unknown"),
        packageManager:        (.packageManager // .type // "unknown"),
        isDirect:              (.isDirect // (.relation == "Direct") // false),
        isOutdated:            (.isOutdated // .outdated // false),
        vulnerabilities:       ((.vulnerabilities // .totalVulnerabilities // 0) | if type == "array" then length else . end),
        highVulnerabilities:   (.highVulnerabilities // 0),
        mediumVulnerabilities: (.mediumVulnerabilities // 0),
        lowVulnerabilities:    (.lowVulnerabilities // 0)
      } |
      # Filter by package name (case-insensitive substring)
      select(.name | ascii_downcase | contains($pkg | ascii_downcase)) |
      # Filter by version if specified (exact match)
      (if $ver != "" then select(.version == $ver) else . end) |
      # Filter direct-only if requested
      (if $directOnly == 1 then select(.isDirect == true) else . end) |
      # Wrap in project context
      {
        projectId:   $pid,
        projectName: $pname,
        scanId:      $sid,
        package:     .
      }
    ]
  ')

  # Merge matches
  MATCH_COUNT=$(echo "${PKG_MATCHES}" | jq 'length')
  if [ "${MATCH_COUNT}" -gt 0 ]; then
    cx_log "  Found ${MATCH_COUNT} match(es) in ${PNAME}"
    MATCHES=$(echo "${MATCHES}" "${PKG_MATCHES}" | jq -s '.[0] + .[1]')
  fi

done < <(echo "${PROJECTS}" | jq -c '.[]')

# --- Summary ---
TOTAL_MATCHES=$(echo "${MATCHES}" | jq 'length')
UNIQUE_PROJECTS=$(echo "${MATCHES}" | jq '[.[].projectId] | unique | length')
cx_log "Search complete: ${TOTAL_MATCHES} match(es) across ${UNIQUE_PROJECTS} project(s) (checked ${CHECKED}, skipped ${SKIPPED})"

# --- Output ---
echo "${MATCHES}" | jq '.'
