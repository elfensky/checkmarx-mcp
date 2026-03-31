#!/usr/bin/env bash
#
# checkmarx.sca-packages.sh
# ==========================
# List open-source packages (SCA inventory) for a scan.
#
# Fetches the SCA risk report for a scan and extracts the package
# inventory. Returns every package (direct and transitive) with its
# version, package manager, vulnerabilities, and license info.
#
# This wraps the Checkmarx One SCA Risk Management endpoint which
# returns the full risk report in JSON. The script extracts and
# normalises the packages section into a clean JSON array.
#
# API Reference:
#   Endpoint:   GET {BASE_URI}/api/sca/risk-management/risk-reports/{scan_id}/export
#   Params:     format=Json (required)
#   Auth:       Bearer token (obtained via cx_authenticate)
#   See also:   docs/rest-api-reference.md § 18.2
#
# Usage:
#   ./utils/checkmarx.sca-packages.sh [-v|--verbose] --scan-id ID [OPTIONS]
#
# Required:
#   --scan-id ID        UUID of a completed scan with SCA results
#
# Options:
#   -v, --verbose       Print curl commands and derived URLs to stderr
#   --direct-only       Only show direct dependencies (exclude transitive)
#   --package NAME      Filter packages by name (case-insensitive substring)
#   --outdated-only     Only show packages that are outdated
#
# Output:
#   A JSON array of package objects to stdout. Each object includes:
#   name, version, packageManager, isDirect, isOutdated, licenses[],
#   vulnerabilities (count), highVulnerabilities, mediumVulnerabilities,
#   lowVulnerabilities, and the raw riskScore when available.
#
#   If the risk report has no packages section, outputs an empty array [].
#
# Examples:
#   ./utils/checkmarx.sca-packages.sh --scan-id "uuid"
#   ./utils/checkmarx.sca-packages.sh --scan-id "uuid" --direct-only
#   ./utils/checkmarx.sca-packages.sh --scan-id "uuid" --package "axios"
#   ./utils/checkmarx.sca-packages.sh --scan-id "uuid" --outdated-only
#   ./utils/checkmarx.sca-packages.sh --scan-id "uuid" | jq '.[].name' -r
#   ./utils/checkmarx.sca-packages.sh --scan-id "uuid" \
#     | jq '[.[] | select(.vulnerabilities > 0)]'
#
# Composability:
#   # List vulnerable direct packages for latest scan
#   SID=$(./utils/checkmarx.list-scans.sh --project-id "$PID" --statuses Completed --limit 1 \
#     | jq -r '.[0].id')
#   ./utils/checkmarx.sca-packages.sh --scan-id "$SID" --direct-only \
#     | jq '[.[] | select(.vulnerabilities > 0)] | sort_by(-.vulnerabilities)'
#
#   # Package inventory as CSV
#   ./utils/checkmarx.sca-packages.sh --scan-id "$SID" \
#     | cx_format_csv .name .version .packageManager .isDirect .vulnerabilities
#
# Exit codes:
#   0  Success
#   1  Missing --scan-id, API error, or no SCA data in scan
#
set -euo pipefail

# --- Bootstrap ---
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib.sh"
cx_parse_flags "$@"
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
SCAN_ID=""
DIRECT_ONLY=0
PACKAGE_FILTER=""
OUTDATED_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-id)       SCAN_ID="$2"; shift 2 ;;
    --direct-only)   DIRECT_ONLY=1; shift ;;
    --package)       PACKAGE_FILTER="$2"; shift 2 ;;
    --outdated-only) OUTDATED_ONLY=1; shift ;;
    *)               echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${SCAN_ID}" ]; then
  echo "Usage: $0 [-v|--verbose] --scan-id ID [--direct-only] [--package NAME] [--outdated-only]" >&2
  exit 1
fi

# --- Load credentials and authenticate ---
source "${SCRIPT_DIR}/../.env"
cx_authenticate

# --- Fetch risk report ---
cx_vlog "Fetching SCA risk report for scan ${SCAN_ID}..."
REPORT=$(cx_get "${BASE}/api/sca/risk-management/risk-reports/${SCAN_ID}/export?format=Json")

# --- Extract and normalise packages ---
# The risk report JSON structure varies but typically has a "packages" array
# at the top level or under "riskReportData". We try several known shapes.
PACKAGES=$(echo "${REPORT}" | jq '
  # Try known locations for the packages array
  if .packages then .packages
  elif .riskReportData.packages then .riskReportData.packages
  elif type == "array" then .
  else []
  end
  # Normalise each package into a consistent shape
  | [.[] | {
      name:                   (.name // .packageName // .id // "unknown"),
      version:                (.version // .packageVersion // "unknown"),
      packageManager:         (.packageManager // .type // "unknown"),
      isDirect:               (.isDirect // (.relation == "Direct") // false),
      isOutdated:             (.isOutdated // .outdated // false),
      newestVersion:          (.newestVersion // .latestVersion // null),
      licenses:               ([(.licenses // .effectiveLicenses // [])[] | .name // .] // []),
      vulnerabilities:        ((.vulnerabilities // .totalVulnerabilities // .numberOfVulnerabilities // 0) | if type == "array" then length else . end),
      highVulnerabilities:    (.highVulnerabilities // 0),
      mediumVulnerabilities:  (.mediumVulnerabilities // 0),
      lowVulnerabilities:     (.lowVulnerabilities // 0),
      riskScore:              (.riskScore // null)
    }]
')

# --- Apply filters ---
if [ "${DIRECT_ONLY}" -eq 1 ]; then
  PACKAGES=$(echo "${PACKAGES}" | jq '[.[] | select(.isDirect == true)]')
fi

if [ -n "${PACKAGE_FILTER}" ]; then
  PACKAGES=$(echo "${PACKAGES}" | jq --arg pkg "${PACKAGE_FILTER}" \
    '[.[] | select(.name | ascii_downcase | contains($pkg | ascii_downcase))]')
fi

if [ "${OUTDATED_ONLY}" -eq 1 ]; then
  PACKAGES=$(echo "${PACKAGES}" | jq '[.[] | select(.isOutdated == true)]')
fi

# --- Output ---
echo "${PACKAGES}"
