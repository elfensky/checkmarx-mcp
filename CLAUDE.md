# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Shell scripts that interact with the Checkmarx One REST API to generate reports and perform administrative tasks. Each script is a standalone bash tool — there is no build system, package manager, or test framework.

## Running Scripts

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

# All read-only scripts support -v / --verbose
```

Prerequisites: `curl`, `jq`, and a configured `.env` file.

## Configuration

All scripts source `.env` from the repo root. Required variables depend on the auth flow:

- **Both flows:** `TENANT`, `BASE_URI`
- **API Key flow:** `APIKEY`
- **OAuth2 flow:** `CLIENT_ID`, `CLIENT_SECRET`

The `BASE_URI` uses `ast.checkmarx.net`; the scripts automatically derive the IAM URL by replacing `ast` → `iam` in the hostname.

## Architecture

Scripts follow a two-step pattern:
1. **Authenticate** — POST to Checkmarx IAM to get a JWT access token (30-min validity)
2. **Call API** — Use the bearer token against `{BASE_URI}/api/...` endpoints

Two auth methods exist as separate scripts because they use different OAuth2 grant types:
- `checkmarx.api.sh` — `grant_type=refresh_token` with a long-lived API key
- `checkmarx.oauth.sh` — `grant_type=client_credentials` with client ID/secret

## Shared Library (`lib.sh`)

All scripts source `lib.sh` from the repo root for shared functionality:
- **Flag parsing:** `cx_parse_flags "$@"` — handles `--verbose`/`-v`, `--dry-run`, `--execute`/`--confirm`
- **Logging:** `cx_log "msg"` (always), `cx_vlog "msg"` (verbose only)
- **Curl wrapper:** `cx_curl ...` — prints the full curl command in verbose mode with secrets redacted

After calling `cx_parse_flags`, restore positional args with:
```bash
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"
```

## Safe Execution Conventions

Scripts are classified by whether they mutate data on Checkmarx:

### Read-only scripts (GET only)

Support `--verbose` / `-v` to print curl commands and derived URLs before executing them. No dry-run flag — reads are inherently safe.

```bash
./checkmarx.api.sh --verbose
./checkmarx.report.sh -v "MyApp"
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

When adding a new script, follow the existing conventions:
- `set -euo pipefail` at the top
- Source `lib.sh`, call `cx_parse_flags "$@"`, then source `.env`
- Validate required env vars before use
- Derive API URLs from `BASE_URI` (don't hardcode regions)
- Use `cx_curl` (not bare `curl`) for all HTTP requests
- Classify as read-only or write and follow the safe execution pattern above

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
