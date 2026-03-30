#!/usr/bin/env node

/**
 * Checkmarx One MCP Server
 *
 * Exposes the Checkmarx One REST API as MCP tools for use with
 * Claude Code, Claude Desktop, or any MCP client.
 *
 * 17 read-only tools organized into six categories:
 *
 *   Projects & Inventory (3):
 *     list_projects, get_project, list_projects_last_scan
 *
 *   Scans (3):
 *     list_scans, get_scan, scan_summary
 *
 *   Results & Findings (2):
 *     list_results, list_sast_results
 *
 *   SAST Analysis (3):
 *     sast_aggregate, sast_compare, get_sast_predicates
 *
 *   Trends (2):
 *     trend_severity, trend_new_vs_fixed
 *
 *   Organization & Reports (4):
 *     list_applications, list_groups, list_presets, get_report
 *
 * Configuration via environment variables:
 *   CHECKMARX_TENANT       - Tenant name (required)
 *   CHECKMARX_BASE_URI     - API base URL (required, e.g., https://ast.checkmarx.net)
 *   CHECKMARX_API_KEY      - API key (refresh_token flow)
 *   CHECKMARX_CLIENT_ID    - OAuth2 client ID (client_credentials flow)
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
    include_queries: z
      .boolean()
      .optional()
      .describe("Include per-query breakdown in the response"),
    include_files: z
      .boolean()
      .optional()
      .describe("Include per-file breakdown in the response"),
  },
  async ({ scan_ids, include_queries, include_files }) =>
    handleTool(() =>
      client.scanSummary(scan_ids, {
        includeQueries: include_queries,
        includeFiles: include_files,
      })
    )
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
    status: z
      .string()
      .optional()
      .describe(
        "Comma-separated status filter (finding lifecycle). Values: NEW, RECURRENT, FIXED"
      ),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Maximum number of results to return. Omit to get all."),
  },
  async ({ scan_id, severity, state, status, limit }) =>
    handleTool(() =>
      client.listResults({ scanId: scan_id, severity, state, status, limit })
    )
);

// ---------------------------------------------------------------------------
// Tool: list_projects_last_scan
// ---------------------------------------------------------------------------

server.tool(
  "list_projects_last_scan",
  "List projects with their last scan information in a single call. Returns project details plus latest scan metadata (status, engines, dates). Far more efficient than fetching scans per-project. Useful for project inventory and status reports.",
  {
    application_id: z
      .string()
      .optional()
      .describe("Filter by application UUID"),
    scan_status: z
      .string()
      .optional()
      .describe("Filter by overall scan status (e.g., Completed, Failed)"),
    sast_status: z.string().optional().describe("Filter by SAST engine status"),
    sca_status: z.string().optional().describe("Filter by SCA engine status"),
    kics_status: z.string().optional().describe("Filter by KICS engine status"),
    apisec_status: z
      .string()
      .optional()
      .describe("Filter by API Security engine status"),
    branch: z.string().optional().describe("Filter by branch name"),
    use_main_branch: z
      .boolean()
      .optional()
      .describe("Only include scans from the project's main branch"),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Maximum number of results to return"),
  },
  async ({
    application_id,
    scan_status,
    sast_status,
    sca_status,
    kics_status,
    apisec_status,
    branch,
    use_main_branch,
    limit,
  }) =>
    handleTool(() =>
      client.listProjectsLastScan({
        applicationId: application_id,
        scanStatus: scan_status,
        sastStatus: sast_status,
        scaStatus: sca_status,
        kicsStatus: kics_status,
        apisecStatus: apisec_status,
        branch,
        useMainBranch: use_main_branch,
        limit,
      })
    )
);

// ---------------------------------------------------------------------------
// Tool: sast_aggregate
// ---------------------------------------------------------------------------

server.tool(
  "sast_aggregate",
  "Get aggregated SAST finding counts grouped by category (QUERY, SEVERITY, STATUS, SOURCE_FILE, SINK_FILE, LANGUAGE). Powers vulnerability distribution reports, top-N query lists, and severity breakdowns for a scan.",
  {
    scan_id: z.string().describe("Scan UUID to aggregate"),
    group_by_fields: z
      .array(
        z.enum([
          "QUERY",
          "SEVERITY",
          "STATUS",
          "SOURCE_FILE",
          "SINK_FILE",
          "SOURCE_NODE",
          "SINK_NODE",
          "LANGUAGE",
        ])
      )
      .min(1)
      .describe("Fields to group results by"),
    severity: z
      .string()
      .optional()
      .describe("Comma-separated severity filter (HIGH, MEDIUM, LOW, INFO)"),
    status: z
      .string()
      .optional()
      .describe("Comma-separated status filter (NEW, RECURRENT)"),
    language: z
      .string()
      .optional()
      .describe("Comma-separated language filter"),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Max results per page"),
  },
  async ({ scan_id, group_by_fields, severity, status, language, limit }) =>
    handleTool(() =>
      client.sastAggregate({
        scanId: scan_id,
        groupByFields: group_by_fields,
        severity,
        status,
        language,
        limit,
      })
    )
);

// ---------------------------------------------------------------------------
// Tool: sast_compare
// ---------------------------------------------------------------------------

server.tool(
  "sast_compare",
  "Compare SAST results between two scans, showing NEW, RECURRENT, and FIXED finding counts grouped by LANGUAGE or QUERY. Use this for 'what changed' reports between scan runs.",
  {
    scan_id: z.string().describe("UUID of the newer scan"),
    base_scan_id: z
      .string()
      .describe("UUID of the older scan to compare against"),
    group_by_fields: z
      .array(z.enum(["LANGUAGE", "QUERY"]))
      .min(1)
      .describe("Fields to group comparison by"),
    severity: z
      .string()
      .optional()
      .describe(
        "Comma-separated severity filter (CRITICAL, HIGH, MEDIUM, LOW, INFO)"
      ),
    status: z
      .string()
      .optional()
      .describe("Comma-separated status filter (NEW, RECURRENT, FIXED)"),
    language: z
      .string()
      .optional()
      .describe("Comma-separated language filter"),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Max results per page"),
  },
  async ({
    scan_id,
    base_scan_id,
    group_by_fields,
    severity,
    status,
    language,
    limit,
  }) =>
    handleTool(() =>
      client.sastCompare({
        scanId: scan_id,
        baseScanId: base_scan_id,
        groupByFields: group_by_fields,
        severity,
        status,
        language,
        limit,
      })
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
// Tool: get_sast_predicates
// ---------------------------------------------------------------------------

server.tool(
  "get_sast_predicates",
  "Get the latest triage predicates for a SAST finding by its similarity ID. Returns severity overrides, state changes, and comments. Use this for compliance reporting and understanding triage decisions.",
  {
    similarity_id: z
      .string()
      .describe("Similarity ID of the SAST finding"),
    project_ids: z
      .string()
      .optional()
      .describe("Comma-separated project UUIDs to filter by"),
    scan_id: z.string().optional().describe("Filter by scan UUID"),
  },
  async ({ similarity_id, project_ids, scan_id }) =>
    handleTool(() =>
      client.getSastPredicates({
        similarityId: similarity_id,
        projectIds: project_ids,
        scanId: scan_id,
      })
    )
);

// ---------------------------------------------------------------------------
// Tool: list_sast_results
// ---------------------------------------------------------------------------

server.tool(
  "list_sast_results",
  "List SAST-specific scan results with rich filtering. Unlike the generic list_results tool, this supports filtering by query name, language, CWE ID, source/sink files, compliance framework, and category. Returns SAST findings with full code-path context.",
  {
    scan_id: z.string().describe("Scan UUID"),
    severity: z
      .string()
      .optional()
      .describe(
        "Comma-separated severity filter (CRITICAL, HIGH, MEDIUM, LOW, INFO)"
      ),
    status: z
      .string()
      .optional()
      .describe("Comma-separated status filter (NEW, RECURRENT)"),
    state: z
      .string()
      .optional()
      .describe(
        "Comma-separated state filter (TO_VERIFY, NOT_EXPLOITABLE, CONFIRMED, etc.)"
      ),
    query: z
      .string()
      .optional()
      .describe("Filter by SAST query name (e.g., SQL_Injection)"),
    language: z
      .string()
      .optional()
      .describe("Comma-separated language filter"),
    cwe_id: z.string().optional().describe("Filter by CWE ID"),
    source_file: z
      .string()
      .optional()
      .describe("Filter by source file path"),
    sink_file: z.string().optional().describe("Filter by sink file path"),
    compliance: z
      .string()
      .optional()
      .describe("Filter by compliance framework"),
    category: z.string().optional().describe("Filter by category"),
    apply_predicates: z
      .boolean()
      .optional()
      .describe("Apply triage predicates (default: true)"),
    include_nodes: z
      .boolean()
      .optional()
      .describe("Include source/sink node details"),
    limit: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Maximum results to return. Omit to get all."),
  },
  async ({
    scan_id,
    severity,
    status,
    state,
    query,
    language,
    cwe_id,
    source_file,
    sink_file,
    compliance,
    category,
    apply_predicates,
    include_nodes,
    limit,
  }) =>
    handleTool(() =>
      client.listSastResults({
        scanId: scan_id,
        severity,
        status,
        state,
        query,
        language,
        cweId: cwe_id,
        sourceFile: source_file,
        sinkFile: sink_file,
        compliance,
        category,
        applyPredicates: apply_predicates,
        includeNodes: include_nodes,
        limit,
      })
    )
);

// ---------------------------------------------------------------------------
// Tool: trend_severity
// ---------------------------------------------------------------------------

server.tool(
  "trend_severity",
  "Get severity counts over time — the 'are we getting better or worse?' trend. Returns severity breakdown per engine per time period at monthly, quarterly, or yearly granularity. Supports project, application, or tenant-wide scope. Counts are summed across projects for multi-project scopes.",
  {
    project_id: z
      .string()
      .optional()
      .describe("Single project UUID (mutually exclusive with application_id)"),
    application_id: z
      .string()
      .optional()
      .describe("Application UUID — includes all projects in the app"),
    period: z
      .enum(["monthly", "quarterly", "yearly"])
      .describe("Time granularity for the trend"),
    range: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Number of periods back (default: 6)"),
    engines: z
      .string()
      .optional()
      .describe(
        "Comma-separated engine filter. Values: sast, sca, kics, containers, apisec. Default: all"
      ),
  },
  async ({ project_id, application_id, period, range, engines }) =>
    handleTool(() =>
      client.trendSeverity({
        projectId: project_id,
        applicationId: application_id,
        period,
        range,
        engines,
      })
    )
);

// ---------------------------------------------------------------------------
// Tool: trend_new_vs_fixed
// ---------------------------------------------------------------------------

server.tool(
  "trend_new_vs_fixed",
  "Get period-over-period net change in findings — the 'are we introducing faster than fixing?' trend. Returns the delta in severity counts between consecutive periods per engine. Negative net_change means improvement (fewer findings). Positive means regression.",
  {
    project_id: z
      .string()
      .optional()
      .describe("Single project UUID (mutually exclusive with application_id)"),
    application_id: z
      .string()
      .optional()
      .describe("Application UUID — includes all projects in the app"),
    period: z
      .enum(["monthly", "quarterly", "yearly"])
      .describe("Time granularity for the trend"),
    range: z
      .number()
      .int()
      .positive()
      .optional()
      .describe("Number of periods back (default: 6)"),
    engines: z
      .string()
      .optional()
      .describe(
        "Comma-separated engine filter. Values: sast, sca, kics, containers, apisec. Default: all"
      ),
  },
  async ({ project_id, application_id, period, range, engines }) =>
    handleTool(() =>
      client.trendNewVsFixed({
        projectId: project_id,
        applicationId: application_id,
        period,
        range,
        engines,
      })
    )
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
