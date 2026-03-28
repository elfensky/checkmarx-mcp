# checkmarx-mcp

Shell scripts and an MCP server for the [Checkmarx One](https://checkmarx.com/product/application-security-platform/) REST API. Two interfaces to the same data: ask Claude in natural language (MCP), or run composable CLI scripts for repeatable reports and pipelines.

## What's in here

| Directory | What | Language |
|-----------|------|----------|
| `mcp-server/` | MCP server — gives Claude direct API access (15 tools) | TypeScript |
| `utils/` | Composable CLI utilities — JSON to stdout, pipe with `jq` (15 scripts) | Bash |
| `docs/` | Checkmarx One REST API & CLI reference docs | Markdown |
| Root (`*.sh`) | Standalone demo scripts (auth flows, CSV reports) | Bash |

## Quick start

### Option A: MCP server (use with Claude)

```bash
cd mcp-server && npm install && npm run build
```

Add to Claude Code settings (`.claude/settings.json`):

```json
{
  "mcpServers": {
    "checkmarx": {
      "command": "node",
      "args": ["/path/to/checkmarx-mcp/mcp-server/dist/index.js"],
      "env": {
        "CHECKMARX_TENANT": "your-tenant",
        "CHECKMARX_BASE_URI": "https://ast.checkmarx.net",
        "CHECKMARX_API_KEY": "your-api-key"
      }
    }
  }
}
```

Then ask Claude: *"What's the security posture across all my projects?"*

### Option B: CLI scripts

```bash
cp .env.example .env   # fill in your credentials
./utils/checkmarx.list-projects.sh | jq '.[].name'
```

See [CLAUDE.md](CLAUDE.md) for full CLI documentation.

## What you can do with this

### Project inventory and status reports

Get every project's last scan status in one call — no more clicking through the portal:

```bash
# Via CLI: all projects for an application with their last scan info
./utils/checkmarx.list-projects-last-scan.sh --application-id "$APP_ID"

# Via Claude: "Show me all projects in the OneApp application with their scan status"
```

### Vulnerability summaries and distribution

Break down findings by severity, language, query type, or file:

```bash
# Top 10 SAST vulnerability types for a scan
./utils/checkmarx.sast-aggregate.sh --scan-id "$SID" --group-by QUERY --limit 10

# Severity distribution
./utils/checkmarx.sast-aggregate.sh --scan-id "$SID" --group-by SEVERITY
```

### Scan comparisons ("what changed?")

Compare two scans to see new, fixed, and recurrent findings:

```bash
./utils/checkmarx.sast-compare.sh --scan-id "$NEW_SID" --base-scan-id "$OLD_SID" --group-by QUERY
```

### Triage and compliance status

Check triage history and filter by finding lifecycle:

```bash
# Only new (untriaged) findings
./utils/checkmarx.list-results.sh --scan-id "$SID" --status "NEW" --severity "HIGH,CRITICAL"

# Triage history for a specific finding
./utils/checkmarx.get-sast-predicates.sh --similarity-id "12345"
```

### Output formatting

Scripts output JSON by default. Use built-in formatters for CSV or markdown:

```bash
# CSV for spreadsheets
source lib.sh
./utils/checkmarx.sast-aggregate.sh --scan-id "$SID" --group-by SEVERITY \
  | cx_format_csv .severity .count > report.csv

# Markdown table for Slack/Confluence
./utils/checkmarx.list-projects-last-scan.sh --application-id "$APP_ID" \
  | cx_format_table .name .lastScanDate .status
```

MCP tools return JSON — Claude handles formatting conversationally ("make that a CSV", "summarize in a table").

## MCP server tools (15)

### Projects and inventory

| Tool | Description |
|------|-------------|
| `list_projects` | List/search projects in the tenant (substring name filter) |
| `get_project` | Get a project by UUID or exact name |
| `list_projects_last_scan` | Project inventory with last scan status per engine — single API call |

### Scans

| Tool | Description |
|------|-------------|
| `list_scans` | List scans with project/status filters, sorted most-recent-first |
| `get_scan` | Get a single scan by ID (status, engines, branch, metadata) |
| `scan_summary` | Severity/status counts for scan(s), with optional per-query/file breakdown |

### Results and findings

| Tool | Description |
|------|-------------|
| `list_results` | List unified findings from all engines (SAST/SCA/KICS/APISec). Supports severity, state, and status (NEW/RECURRENT/FIXED) filters |
| `list_sast_results` | SAST-specific results with rich filters: query name, language, CWE ID, source/sink files, compliance framework, category. Returns code-path context |

### SAST analysis

| Tool | Description |
|------|-------------|
| `sast_aggregate` | Aggregated SAST counts grouped by QUERY, SEVERITY, STATUS, LANGUAGE, SOURCE_FILE, or SINK_FILE. For distribution reports and top-N lists |
| `sast_compare` | Compare two scans: NEW, RECURRENT, and FIXED counts grouped by LANGUAGE or QUERY. The "what changed" report |
| `get_sast_predicates` | Triage history for a finding by similarity ID — severity overrides, state changes, comments. For compliance reporting |

### Organization

| Tool | Description |
|------|-------------|
| `list_applications` | List application groupings (name, criticality, project IDs) |
| `list_groups` | List access management groups |
| `list_presets` | List SAST query presets (Checkmarx Default, OWASP Top 10, etc.) |

### Reports

| Tool | Description |
|------|-------------|
| `get_report` | Generate a scan report (PDF/JSON/CSV/SARIF), poll for completion, return download URL |

## CLI scripts (15)

Each script outputs JSON to stdout, logs to stderr, and supports `-v`/`--verbose`.

| Script | Description | Key Flags |
|--------|-------------|-----------|
| `list-projects.sh` | List/search projects | `--name`, `--limit` |
| `get-project.sh` | Get project by UUID or name | positional arg |
| `list-projects-last-scan.sh` | Project inventory with last scan info | `--application-id`, `--scan-status`, `--sast-status`, `--sca-status`, `--kics-status`, `--use-main-branch` |
| `list-scans.sh` | List scans | `--project-id`, `--statuses`, `--limit` |
| `get-scan.sh` | Get single scan | positional UUID |
| `scan-summary.sh` | Severity/status counts | `--scan-id` (repeatable), `--include-queries`, `--include-files` |
| `list-results.sh` | Unified findings | `--scan-id`, `--severity`, `--state`, `--status`, `--limit` |
| `list-sast-results.sh` | SAST-specific findings | `--scan-id`, `--query`, `--language`, `--cwe-id`, `--source-file`, `--sink-file`, `--compliance`, `--include-nodes` |
| `sast-aggregate.sh` | SAST counts by category | `--scan-id`, `--group-by` (repeatable), `--severity`, `--status`, `--language` |
| `sast-compare.sh` | Diff two scans | `--scan-id`, `--base-scan-id`, `--group-by`, `--severity`, `--status` |
| `get-sast-predicates.sh` | Triage history | `--similarity-id`, `--project-ids`, `--scan-id` |
| `list-applications.sh` | List applications | `--name` |
| `list-groups.sh` | List groups | `--search` |
| `list-presets.sh` | List SAST presets | (none) |
| `get-report.sh` | Generate + download report | `--scan-id`, `--project-id`, `--format`, `--output` |

All script names are prefixed with `checkmarx.` (e.g., `./utils/checkmarx.list-projects.sh`).

## Configuration

Both the CLI scripts and MCP server need Checkmarx One credentials:

| Variable | CLI (`.env`) | MCP server | Required |
|----------|-------------|------------|----------|
| Tenant | `TENANT` | `CHECKMARX_TENANT` | Yes |
| Base URL | `BASE_URI` | `CHECKMARX_BASE_URI` | Yes |
| API Key | `APIKEY` | `CHECKMARX_API_KEY` | * |
| Client ID | `CLIENT_ID` | `CHECKMARX_CLIENT_ID` | * |
| Client Secret | `CLIENT_SECRET` | `CHECKMARX_CLIENT_SECRET` | * |

\* Provide either API Key **or** Client ID + Secret.

### Regional base URLs

| Region | URL |
|--------|-----|
| US | `https://ast.checkmarx.net` |
| EU | `https://eu.ast.checkmarx.net` |
| US2 | `https://us.ast.checkmarx.net` |
| DEU | `https://deu.ast.checkmarx.net` |
| ANZ | `https://anz.ast.checkmarx.net` |
| India | `https://ind.ast.checkmarx.net` |
| Singapore | `https://sng.ast.checkmarx.net` |

## Prerequisites

- **CLI scripts:** `curl`, `jq`, bash
- **MCP server:** Node.js >= 18

## License

MIT
