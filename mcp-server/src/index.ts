#!/usr/bin/env node

/**
 * Checkmarx One MCP Server
 *
 * Exposes the Checkmarx One REST API as MCP tools for use with
 * Claude Code, Claude Desktop, or any MCP client.
 *
 * Configuration via environment variables:
 *   CHECKMARX_TENANT     - Tenant name (required)
 *   CHECKMARX_BASE_URI   - API base URL (required, e.g., https://ast.checkmarx.net)
 *   CHECKMARX_API_KEY    - API key (refresh_token flow)
 *   CHECKMARX_CLIENT_ID  - OAuth2 client ID (client_credentials flow)
 *   CHECKMARX_CLIENT_SECRET - OAuth2 client secret
 *
 * If both CLIENT_ID+CLIENT_SECRET and API_KEY are set, client_credentials takes priority.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { CheckmarxClient, configFromEnv } from "./client.js";

// ---------------------------------------------------------------------------
// Initialize
// ---------------------------------------------------------------------------

const server = new McpServer({
  name: "checkmarx",
  version: "0.1.0",
});

let client: CheckmarxClient;

try {
  client = new CheckmarxClient(configFromEnv());
} catch (err) {
  // Defer the error to tool invocation time so the server can still start
  // and report the configuration error via tool responses
  client = null as unknown as CheckmarxClient;
  const configError = (err as Error).message;

  // We'll check for this in each tool handler
  const originalConfigFromEnv = configFromEnv;
  // Override to provide a helpful error
  Object.defineProperty(globalThis, "__checkmarxConfigError", {
    value: configError,
  });
}

/**
 * Helper: wraps a tool handler to catch errors and return them as text content.
 * Also checks for configuration errors.
 */
function toolResult(text: string, isError = false) {
  return {
    content: [{ type: "text" as const, text }],
    isError,
  };
}

async function handleTool<T>(fn: () => Promise<T>): Promise<{
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
}> {
  const configError = (globalThis as Record<string, unknown>)
    .__checkmarxConfigError as string | undefined;
  if (configError) {
    return toolResult(`Configuration error: ${configError}`, true);
  }

  try {
    const result = await fn();
    return toolResult(JSON.stringify(result, null, 2));
  } catch (err) {
    return toolResult(`Error: ${(err as Error).message}`, true);
  }
}

// ---------------------------------------------------------------------------
// Tool: list_projects
// ---------------------------------------------------------------------------

server.tool(
  "list_projects",
  "List all projects in the Checkmarx One tenant. Returns a JSON array of project objects (id, name, mainBranch, tags, etc.). Use the 'name' parameter for substring filtering.",
  {
    name: z.string().optional().describe("Filter projects by name (substring match)"),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Maximum number of projects to return. Omit to get all (auto-paginated)."),
  },
  async ({ name, limit }) => handleTool(() => client.listProjects({ name, limit }))
);

// ---------------------------------------------------------------------------
// Tool: get_project
// ---------------------------------------------------------------------------

server.tool(
  "get_project",
  "Get a single project by UUID or exact name. Returns the full project JSON object. If a name is provided, performs an exact-match search (the API does substring matching, but this tool filters to exact matches).",
  {
    identifier: z
      .string()
      .describe("Project UUID (e.g., 'a1b2c3d4-...') or exact project name"),
  },
  async ({ identifier }) => handleTool(() => client.getProject(identifier))
);

// ---------------------------------------------------------------------------
// Tool: list_scans
// ---------------------------------------------------------------------------

server.tool(
  "list_scans",
  "List scans, optionally filtered by project and/or status. Returns a JSON array of scan objects (id, status, branch, createdAt, engines, etc.). Results are sorted most-recent-first when limit is specified.",
  {
    project_id: z.string().optional().describe("Filter by project UUID"),
    statuses: z
      .string()
      .optional()
      .describe(
        "Comma-separated status filter. Values: Queued, Running, Completed, Failed, Partial, Canceled"
      ),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe(
        "Maximum number of scans to return (most recent first). Omit to get all."
      ),
  },
  async ({ project_id, statuses, limit }) =>
    handleTool(() =>
      client.listScans({ projectId: project_id, statuses, limit })
    )
);

// ---------------------------------------------------------------------------
// Tool: get_scan
// ---------------------------------------------------------------------------

server.tool(
  "get_scan",
  "Get a single scan by its UUID. Returns the full scan JSON object including status, statusDetails (per-engine), branch, engines, tags, and metadata.",
  {
    scan_id: z.string().describe("Scan UUID"),
  },
  async ({ scan_id }) => handleTool(() => client.getScan(scan_id))
);

// ---------------------------------------------------------------------------
// Tool: scan_summary
// ---------------------------------------------------------------------------

server.tool(
  "scan_summary",
  "Get aggregated vulnerability counts for one or more scans. Returns severity/status breakdowns for each scanner (SAST, SCA, KICS, API Security). Much faster than fetching individual results when you only need counts.",
  {
    scan_ids: z
      .array(z.string())
      .min(1)
      .describe("Array of scan UUIDs to summarize"),
  },
  async ({ scan_ids }) => handleTool(() => client.scanSummary(scan_ids))
);

// ---------------------------------------------------------------------------
// Tool: list_results
// ---------------------------------------------------------------------------

server.tool(
  "list_results",
  "List vulnerability findings for a scan. Returns results from all scanner engines (SAST, SCA, KICS, API Security) in a unified format. Each result includes type, severity, status, state, and description.",
  {
    scan_id: z.string().describe("Scan UUID to fetch results for"),
    severity: z
      .string()
      .optional()
      .describe(
        "Comma-separated severity filter. Values: CRITICAL, HIGH, MEDIUM, LOW, INFO"
      ),
    state: z
      .string()
      .optional()
      .describe(
        "Comma-separated state filter. Values: TO_VERIFY, NOT_EXPLOITABLE, PROPOSED_NOT_EXPLOITABLE, CONFIRMED, URGENT"
      ),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Maximum number of results to return. Omit to get all."),
  },
  async ({ scan_id, severity, state, limit }) =>
    handleTool(() =>
      client.listResults({ scanId: scan_id, severity, state, limit })
    )
);

// ---------------------------------------------------------------------------
// Tool: list_applications
// ---------------------------------------------------------------------------

server.tool(
  "list_applications",
  "List all applications in the Checkmarx One tenant. Applications are logical groupings of projects. Returns id, name, description, criticality, projectIds, and tags.",
  {
    name: z
      .string()
      .optional()
      .describe("Filter applications by name (substring match)"),
  },
  async ({ name }) => handleTool(() => client.listApplications({ name }))
);

// ---------------------------------------------------------------------------
// Tool: list_groups
// ---------------------------------------------------------------------------

server.tool(
  "list_groups",
  "List access management groups in the tenant. Groups control project access and role assignments. Returns id, name, and briefName.",
  {
    search: z.string().optional().describe("Search groups by name (substring match)"),
  },
  async ({ search }) => handleTool(() => client.listGroups({ search }))
);

// ---------------------------------------------------------------------------
// Tool: list_presets
// ---------------------------------------------------------------------------

server.tool(
  "list_presets",
  "List SAST query presets available in the tenant. Presets define which vulnerability rules are included in a scan (e.g., 'Checkmarx Default', 'OWASP Top 10'). Returns id and name for each preset.",
  {},
  async () => handleTool(() => client.listPresets())
);

// ---------------------------------------------------------------------------
// Tool: get_report
// ---------------------------------------------------------------------------

server.tool(
  "get_report",
  "Generate a scan report and wait for it to complete. Returns the report status and download URL. The report includes findings from all scanners (SAST, SCA, KICS). Note: this tool polls for completion and may take 30-60 seconds.",
  {
    scan_id: z.string().describe("Scan UUID to generate the report for"),
    project_id: z.string().describe("Project UUID (required by the Reports API)"),
    format: z
      .enum(["pdf", "json", "csv", "sarif"])
      .optional()
      .describe("Report output format (default: pdf)"),
  },
  async ({ scan_id, project_id, format }) =>
    handleTool(() =>
      client.getReport({ scanId: scan_id, projectId: project_id, format })
    )
);

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
