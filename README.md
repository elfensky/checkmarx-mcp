# checkmarx-mcp

Shell scripts and an MCP server for the [Checkmarx One](https://checkmarx.com/product/application-security-platform/) REST API.

## What's in here

| Directory | What | Language |
|-----------|------|----------|
| `utils/` | Composable CLI utilities (projects, scans, results, reports) | Bash |
| `mcp-server/` | MCP server — gives Claude direct API access | TypeScript |
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

## MCP server tools

| Tool | Description |
|------|-------------|
| `list_projects` | List/search projects in the tenant |
| `get_project` | Get a project by UUID or exact name |
| `list_scans` | List scans with project/status filters |
| `get_scan` | Get a single scan by ID |
| `scan_summary` | Severity/status counts for scan(s) |
| `list_results` | List vulnerability findings |
| `list_applications` | List application groupings |
| `list_groups` | List access management groups |
| `list_presets` | List SAST query presets |
| `get_report` | Generate + poll + return report URL |

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
