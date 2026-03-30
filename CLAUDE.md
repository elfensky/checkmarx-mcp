# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Two interfaces for pulling data from the Checkmarx One REST API:

1. **MCP server** (TypeScript) — 15 tools that Claude calls directly for conversational, ad-hoc queries. Returns JSON; Claude formats the output for the audience.
2. **CLI scripts** (Bash) — 15 composable utilities that output JSON to stdout. Pipe with `jq` or use built-in `cx_format_csv`/`cx_format_table` formatters. For repeatable reports, cron jobs, and scripted pipelines.

Both share the same API surface and authentication layer (token caching across invocations). The repo also includes standalone demo scripts for auth flows and a CSV report generator.

## Repository Layout

```
.
├── lib.sh                          # Shared library (auth, HTTP, pagination, logging)
├── .env                            # Credentials and tenant config (not committed)
├── checkmarx.api.sh                # Demo: API Key auth flow → list projects
├── checkmarx.oauth.sh              # Demo: OAuth2 client credentials → list projects
├── checkmarx.report.sh             # CSV report: projects by application
├── utils/                          # Composable utility scripts (JSON to stdout)
│   ├── checkmarx.list-projects.sh
│   ├── checkmarx.get-project.sh
│   ├── checkmarx.list-projects-last-scan.sh  # Project inventory with last scan info
│   ├── checkmarx.list-scans.sh
│   ├── checkmarx.get-scan.sh
│   ├── checkmarx.scan-summary.sh
│   ├── checkmarx.list-results.sh
│   ├── checkmarx.list-sast-results.sh        # SAST-specific results with rich filters
│   ├── checkmarx.sast-aggregate.sh           # SAST counts by category
│   ├── checkmarx.sast-compare.sh             # Compare two scans (new/fixed/recurrent)
│   ├── checkmarx.get-sast-predicates.sh      # Triage history for findings
│   ├── checkmarx.scan-timeline.sh            # Timeline: one scan per period (building block)
│   ├── checkmarx.trend-severity.sh           # Trend: severity counts over time
│   ├── checkmarx.trend-new-vs-fixed.sh       # Trend: period-over-period net change
│   ├── checkmarx.list-applications.sh
│   ├── checkmarx.list-groups.sh
│   ├── checkmarx.list-presets.sh
│   └── checkmarx.get-report.sh
└── docs/                           # API and CLI reference documentation
```

## Running Scripts

### Top-level scripts (standalone demos)

```bash
# API Key authentication flow (uses APIKEY from .env)
./checkmarx.api.sh
./checkmarx.api.sh --verbose       # prints curl commands and URLs

# OAuth2 client credentials flow (uses CLIENT_ID + CLIENT_SECRET from .env)
./checkmarx.oauth.sh

# CSV report of projects by application (uses APIKEY from .env)
./checkmarx.report.sh              # defaults to "OneApp"
./checkmarx.report.sh "MyApp"      # custom application name
./checkmarx.report.sh -v "MyApp"   # verbose mode
```

### Utility scripts (`utils/`)

Composable, single-purpose scripts that output clean JSON to stdout. All support `-v`/`--verbose`. They use `lib.sh` shared functions for authentication (with token caching), pagination, and HTTP.

```bash
# Projects
./utils/checkmarx.list-projects.sh                          # all projects
./utils/checkmarx.list-projects.sh --name "my-project"      # filter by name
./utils/checkmarx.list-projects.sh --limit 10               # first 10 only
./utils/checkmarx.get-project.sh "my-project"               # by name (exact match)
./utils/checkmarx.get-project.sh "a1b2c3d4-..."             # by UUID

# Scans
./utils/checkmarx.list-scans.sh --project-id "uuid"                     # all scans
./utils/checkmarx.list-scans.sh --project-id "uuid" --statuses Completed --limit 1  # latest
./utils/checkmarx.get-scan.sh "scan-uuid"                               # single scan

# Results & summaries
./utils/checkmarx.scan-summary.sh --scan-id "uuid"                      # severity counts
./utils/checkmarx.scan-summary.sh --scan-id "uuid" --include-queries    # per-query breakdown
./utils/checkmarx.list-results.sh --scan-id "uuid" --severity "HIGH,CRITICAL"  # vulns
./utils/checkmarx.list-results.sh --scan-id "uuid" --status "NEW"       # new findings only

# SAST-specific analysis
./utils/checkmarx.list-sast-results.sh --scan-id "uuid" --language "JavaScript" --query "SQL_Injection"
./utils/checkmarx.sast-aggregate.sh --scan-id "uuid" --group-by SEVERITY            # severity distribution
./utils/checkmarx.sast-aggregate.sh --scan-id "uuid" --group-by QUERY --limit 10    # top 10 query types
./utils/checkmarx.sast-compare.sh --scan-id "new" --base-scan-id "old" --group-by QUERY  # scan diff
./utils/checkmarx.get-sast-predicates.sh --similarity-id "12345"        # triage history

# Trend metrics
./utils/checkmarx.trend-severity.sh --project-id "uuid" --period monthly --range 6
./utils/checkmarx.trend-severity.sh --application-id "uuid" --period quarterly --range 4 --engines sast,sca
./utils/checkmarx.trend-new-vs-fixed.sh --project-id "uuid" --period monthly --range 6
./utils/checkmarx.scan-timeline.sh --project-id "uuid" --period monthly --range 6  # building block

# Project inventory
./utils/checkmarx.list-projects-last-scan.sh                            # all projects with last scan
./utils/checkmarx.list-projects-last-scan.sh --application-id "uuid"    # filter by app

# Applications, groups, presets
./utils/checkmarx.list-applications.sh                      # all apps
./utils/checkmarx.list-groups.sh --search "security"        # search groups
./utils/checkmarx.list-presets.sh                           # SAST presets

# Reports (create + poll + download)
./utils/checkmarx.get-report.sh --scan-id "uuid" --project-id "uuid" --format pdf
```

#### Composability (piping scripts together)

Utility scripts output JSON to stdout and log to stderr, so they compose with `jq`:

```bash
# Get severity counts for latest scan of a project
PID=$(./utils/checkmarx.get-project.sh "my-project" | jq -r '.id')
SID=$(./utils/checkmarx.list-scans.sh --project-id "$PID" --statuses Completed --limit 1 \
  | jq -r '.[0].id')
./utils/checkmarx.scan-summary.sh --scan-id "$SID" \
  | jq '.scansSummaries[0].sastCounters.severityCounters'

# Download PDF report for latest scan
./utils/checkmarx.get-report.sh --scan-id "$SID" --project-id "$PID"

# Compare last two scans for a project (what changed?)
SCANS=$(./utils/checkmarx.list-scans.sh --project-id "$PID" --statuses Completed --limit 2)
NEW_SID=$(echo "$SCANS" | jq -r '.[0].id')
OLD_SID=$(echo "$SCANS" | jq -r '.[1].id')
./utils/checkmarx.sast-compare.sh --scan-id "$NEW_SID" --base-scan-id "$OLD_SID" --group-by QUERY

# SAST severity distribution as CSV
./utils/checkmarx.sast-aggregate.sh --scan-id "$SID" --group-by SEVERITY \
  | cx_format_csv .severity .count

# Project inventory as markdown table
./utils/checkmarx.list-projects-last-scan.sh --application-id "$APP_ID" \
  | cx_format_table .name .lastScanDate .status

# Severity trend as CSV for Excel charting
./utils/checkmarx.trend-severity.sh --project-id "$PID" --period monthly --range 12 \
  | jq '[.[] | {period, critical: .total.critical, high: .total.high, medium: .total.medium}]' \
  | cx_format_csv .period .critical .high .medium > severity-trend.csv
```

Token caching means only the first script in a pipeline authenticates; subsequent scripts reuse the cached token from `$TMPDIR`.

Prerequisites: `curl`, `jq`, and a configured `.env` file.

## Configuration

All scripts source `.env` from the repo root. Required variables depend on the auth flow:

- **Both flows:** `TENANT`, `BASE_URI`
- **API Key flow:** `APIKEY`
- **OAuth2 flow:** `CLIENT_ID`, `CLIENT_SECRET`

The `BASE_URI` uses `ast.checkmarx.net`; the scripts automatically derive the IAM URL by replacing `ast` → `iam` in the hostname.

## Architecture

### Common pattern

All tools (both MCP and CLI) follow a two-step pattern:
1. **Authenticate** — POST to Checkmarx IAM to get a JWT access token (30-min validity)
2. **Call API** — Use the bearer token against `{BASE_URI}/api/...` endpoints

Two auth methods exist because they use different OAuth2 grant types:
- `grant_type=refresh_token` — with a long-lived API key (simpler, per-user)
- `grant_type=client_credentials` — with client ID/secret (for service accounts)

### MCP server (`mcp-server/`)

The MCP server is a TypeScript process (`@modelcontextprotocol/sdk`) that communicates over stdio. It exposes 15 tools organized into five categories: projects/inventory, scans, results/findings, SAST analysis, and organization/reports.

- `mcp-server/src/index.ts` — Tool registrations (Zod schemas, descriptions, handler wiring)
- `mcp-server/src/client.ts` — `CheckmarxClient` class: auth, HTTP helpers, pagination, and all API methods

The client uses in-memory token caching (60s safety buffer). Configuration errors are deferred to tool invocation time so the server starts cleanly and reports errors through tool responses.

### CLI scripts (`utils/`)

Each script is a standalone executable that sources `lib.sh` for shared functions. Scripts output JSON to stdout and log to stderr, making them composable via pipes:

```
get-project → list-scans → scan-summary → cx_format_csv → file.csv
```

Token caching via `$TMPDIR` means only the first script in a pipeline authenticates.

### API coverage

The tools cover five Checkmarx One API areas:

| API | Endpoints wrapped | Scripts/Tools |
|-----|-------------------|---------------|
| Projects | `/api/projects`, `/api/projects/last-scan` | `list_projects`, `get_project`, `list_projects_last_scan` |
| Scans | `/api/scans`, `/api/scan-summary` | `list_scans`, `get_scan`, `scan_summary` |
| Results | `/api/results`, `/api/sast-results` | `list_results`, `list_sast_results` |
| SAST Analysis | `/api/sast-scan-summary/aggregate`, `/compare/aggregate`, `/api/sast-results-predicates` | `sast_aggregate`, `sast_compare`, `get_sast_predicates` |
| Organization | `/api/applications`, `/api/access-management/groups`, `/api/queries/presets`, `/api/reports` | `list_applications`, `list_groups`, `list_presets`, `get_report` |

All operations are **read-only** (GET requests only). No write/mutate operations are exposed.

## Shared Library (`lib.sh`)

All scripts source `lib.sh` from the repo root for shared functionality:

### Core (used by all scripts)
- **Flag parsing:** `cx_parse_flags "$@"` — handles `--verbose`/`-v`, `--dry-run`, `--execute`/`--confirm`, `--format csv|json|md`
- **Logging:** `cx_log "msg"` (always), `cx_vlog "msg"` (verbose only)
- **Curl wrapper:** `cx_curl ...` — prints the full curl command in verbose mode with secrets redacted

### Extended (used by `utils/` scripts)
- **`cx_authenticate`** — Obtains a JWT access token, auto-detecting the auth flow (API key vs OAuth2). Caches the token in `$TMPDIR/cx-token-<TENANT>.json` with a 60-second expiry buffer. Reuses cached tokens across script invocations.
- **`cx_get URL`** — Authenticated GET request with standard `Accept: application/json; version=1.0` header.
- **`cx_paginate URL ARRAY_KEY [LIMIT]`** — Fetches all pages from a list endpoint and outputs a merged JSON array. Handles `filteredTotalCount`/`totalCount` and has a 100-page safety cap.
- **`cx_require_vars VAR1 VAR2...`** — Validates that listed environment variables are set and non-empty.
- **`cx_base_urls`** — Derives `BASE` and `IAM_URL` from `BASE_URI` and `TENANT`.
- **`cx_urlencode STRING`** — Portable percent-encoding via `jq`.
- **`cx_format_csv FIELD1 FIELD2...`** — Reads JSON array from stdin, outputs RFC 4180 CSV. Fields are jq expressions (e.g., `.name`, `.severity`).
- **`cx_format_table FIELD1 FIELD2...`** — Reads JSON array from stdin, outputs a markdown table. Same field syntax.

After calling `cx_parse_flags`, restore positional args with:
```bash
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"
```

### Token caching

`cx_authenticate` caches tokens in `$TMPDIR/cx-token-<TENANT>.json` (per-user, restricted permissions via `umask 077`, atomic writes via `mktemp`+`mv`). This means running multiple utility scripts in sequence or a pipeline makes only one auth round-trip. The cache is invalidated 60 seconds before the token actually expires.

## Safe Execution Conventions

Scripts are classified by whether they mutate data on Checkmarx:

### Read-only scripts (GET only)

All utility scripts in `utils/` and the top-level demo scripts are read-only. They support `--verbose` / `-v` to print curl commands and derived URLs before executing them. No dry-run flag — reads are inherently safe.

```bash
./checkmarx.api.sh --verbose
./checkmarx.report.sh -v "MyApp"
./utils/checkmarx.list-projects.sh -v
```

### Write scripts (POST/PUT/DELETE that mutate data)

**Safe by default.** Write scripts run in dry-run mode unless `--execute` (or `--confirm`) is passed. Without the flag, they authenticate and print what *would* happen without making mutating API calls.

```bash
./checkmarx.delete-projects.sh --app MyApp            # dry-run: prints what would be deleted
./checkmarx.delete-projects.sh --app MyApp --execute   # actually deletes
```

Implementation pattern for write scripts:
```bash
source "${SCRIPT_DIR}/lib.sh"
cx_parse_flags "$@"

# Default to dry-run for write scripts
if [[ "${EXECUTE}" -eq 0 ]]; then
  DRY_RUN=1
fi

# Guard mutating calls
if [[ "${DRY_RUN}" -eq 1 ]]; then
  cx_log "[DRY RUN] Would DELETE project ${PROJECT_ID}"
else
  cx_curl --silent --fail --request DELETE "${API_URL}/projects/${PROJECT_ID}" ...
fi
```

## Adding New Scripts

### Top-level scripts

When adding a new top-level script, follow the existing conventions:
- `set -euo pipefail` at the top
- Source `lib.sh`, call `cx_parse_flags "$@"`, then source `.env`
- Validate required env vars before use
- Derive API URLs from `BASE_URI` (don't hardcode regions)
- Use `cx_curl` (not bare `curl`) for all HTTP requests
- Classify as read-only or write and follow the safe execution pattern above

### Utility scripts (`utils/`)

When adding a new utility script in `utils/`:
- Use the naming convention `checkmarx.<verb>-<resource>.sh`
- Source lib.sh with the relative path: `source "${SCRIPT_DIR}/../lib.sh"`
- Source .env with the relative path: `source "${SCRIPT_DIR}/../.env"`
- Use `cx_authenticate` instead of inline auth (enables token caching)
- Use `cx_get` for authenticated GET requests
- Use `cx_paginate` for list endpoints with pagination
- Output clean JSON to stdout; log to stderr via `cx_log`/`cx_vlog`
- Add extensive header comments: description, API reference, usage, options, output format, examples, composability hints, and exit codes

## Documentation (`docs/`)

### REST API Reference
- `docs/rest-api-reference.md` — **Comprehensive** Checkmarx One REST API reference covering 20 API areas: authentication, scans, uploads, reports (v1 & v2), results (all scanners, SAST, KICS), applications, projects, groups/access management, queries, scan configuration, audit trail, SCA, and webhooks. Includes regional URLs, request/response schemas, and curl examples.
- `docs/authentication-api.md` — Quick reference for the token endpoint (subset of the full API reference)
- `docs/projects-api.md` — Quick reference for the projects listing endpoint (subset of the full API reference)

### CLI Reference (`cx` tool)
- `docs/cx-cli-reference.md` — Installation (all platforms + Docker + Homebrew), authentication methods, `cx configure`, 20+ global flags, 70+ environment variables, and utilities (`cx utils`)
- `docs/scan-cli-reference.md` — `cx scan` command: 8 subcommands, 50+ flags for `scan create` (scan types, source options, SAST/SCA/IaC/container/API security/SCS-specific flags, report generation, thresholds), plus real-time scan subcommands
- `docs/cli-commands-reference.md` — `cx results` (12 report formats, PDF/SBOM options, filtering), `cx triage` (show/update with state and severity values), `cx project` (CRUD, tags, branches, filtering)

### External Links
- Full REST API docs: https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide
- CLI docs: https://docs.checkmarx.com/en/34965-68625-checkmarx-one-cli-commands.html
- CLI source: https://github.com/Checkmarx/ast-cli
