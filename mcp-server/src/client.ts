/**
 * Checkmarx One API Client
 *
 * Handles authentication (API key or OAuth2 client credentials),
 * in-memory token caching, pagination, and authenticated HTTP requests.
 * This is a TypeScript port of the patterns in lib.sh.
 *
 * API methods are organized to match the utils/ bash scripts:
 *
 *   Projects:   listProjects, getProject, listProjectsLastScan
 *   Scans:      listScans, getScan, scanSummary
 *   Results:    listResults, listSastResults
 *   SAST:       sastAggregate, sastCompare, getSastPredicates
 *   Org:        listApplications, listGroups, listPresets
 *   Reports:    getReport
 *
 * All methods are read-only (GET requests), except getReport which
 * uses POST to create a report request and then polls with GET.
 *
 * @see lib.sh for the bash equivalent
 * @see docs/rest-api-reference.md for full API documentation
 */

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

export interface CheckmarxConfig {
  /** Checkmarx tenant name (e.g., "mycompany") */
  tenant: string;
  /** API base URL (e.g., "https://ast.checkmarx.net" or regional) */
  baseUri: string;
  /** API key for refresh_token auth flow */
  apiKey?: string;
  /** OAuth2 client ID for client_credentials flow */
  clientId?: string;
  /** OAuth2 client secret for client_credentials flow */
  clientSecret?: string;
}

/**
 * Reads configuration from environment variables.
 * Throws if required variables (CHECKMARX_TENANT, CHECKMARX_BASE_URI) are missing.
 */
export function configFromEnv(): CheckmarxConfig {
  const tenant = process.env.CHECKMARX_TENANT;
  const baseUri = process.env.CHECKMARX_BASE_URI;

  if (!tenant || !baseUri) {
    throw new Error(
      "Missing required environment variables: CHECKMARX_TENANT and CHECKMARX_BASE_URI. " +
        "Also set CHECKMARX_API_KEY or CHECKMARX_CLIENT_ID + CHECKMARX_CLIENT_SECRET."
    );
  }

  return {
    tenant,
    baseUri: baseUri.replace(/\/+$/, ""), // strip trailing slash
    apiKey: process.env.CHECKMARX_API_KEY,
    clientId: process.env.CHECKMARX_CLIENT_ID,
    clientSecret: process.env.CHECKMARX_CLIENT_SECRET,
  };
}

// ---------------------------------------------------------------------------
// Token cache (in-memory, per-process)
// ---------------------------------------------------------------------------

interface CachedToken {
  accessToken: string;
  /** Unix timestamp (seconds) when the token expires, with a 60s safety buffer */
  expiresAt: number;
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

export class CheckmarxClient {
  private readonly config: CheckmarxConfig;
  private readonly base: string;
  private readonly iamUrl: string;
  private cachedToken: CachedToken | null = null;

  constructor(config: CheckmarxConfig) {
    this.config = config;
    this.base = config.baseUri;

    // Derive IAM URL: replace "ast" with "iam" in the hostname
    this.iamUrl =
      this.base.replace("ast.checkmarx.net", "iam.checkmarx.net") +
      `/auth/realms/${config.tenant}/protocol/openid-connect/token`;
  }

  // -------------------------------------------------------------------------
  // Authentication
  // -------------------------------------------------------------------------

  /**
   * Obtains a JWT access token, reusing the cached token if still valid.
   * Auto-detects auth flow: client_credentials if clientId+clientSecret are
   * set, otherwise refresh_token with apiKey.
   */
  private async authenticate(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);

    if (this.cachedToken && now < this.cachedToken.expiresAt) {
      return this.cachedToken.accessToken;
    }

    const body = new URLSearchParams();

    if (this.config.clientId && this.config.clientSecret) {
      body.set("grant_type", "client_credentials");
      body.set("client_id", this.config.clientId);
      body.set("client_secret", this.config.clientSecret);
    } else if (this.config.apiKey) {
      body.set("grant_type", "refresh_token");
      body.set("client_id", "ast-app");
      body.set("refresh_token", this.config.apiKey);
    } else {
      throw new Error(
        "No credentials configured. Set CHECKMARX_API_KEY or CHECKMARX_CLIENT_ID + CHECKMARX_CLIENT_SECRET."
      );
    }

    const response = await fetch(this.iamUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body,
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Authentication failed (${response.status}): ${text}`);
    }

    const data = (await response.json()) as {
      access_token: string;
      expires_in: number;
    };

    if (!data.access_token) {
      throw new Error("Authentication response missing access_token");
    }

    // Cache with 60-second safety buffer
    this.cachedToken = {
      accessToken: data.access_token,
      expiresAt: now + (data.expires_in ?? 1800) - 60,
    };

    return this.cachedToken.accessToken;
  }

  // -------------------------------------------------------------------------
  // HTTP helpers
  // -------------------------------------------------------------------------

  /** Authenticated GET request. Returns parsed JSON. */
  async get<T = unknown>(path: string): Promise<T> {
    const token = await this.authenticate();
    const url = path.startsWith("http") ? path : `${this.base}${path}`;

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json; version=1.0",
      },
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`GET ${path} failed (${response.status}): ${text}`);
    }

    return response.json() as Promise<T>;
  }

  /** Authenticated POST request with JSON body. Returns parsed JSON. */
  async post<T = unknown>(path: string, body: unknown): Promise<T> {
    const token = await this.authenticate();
    const url = path.startsWith("http") ? path : `${this.base}${path}`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`POST ${path} failed (${response.status}): ${text}`);
    }

    return response.json() as Promise<T>;
  }

  // -------------------------------------------------------------------------
  // Pagination
  // -------------------------------------------------------------------------

  /**
   * Fetches all pages from a list endpoint and returns a merged array.
   *
   * @param path    - API path with optional query params (e.g., "/api/projects?name=foo")
   * @param arrayKey - JSON key containing the array (e.g., "projects")
   * @param pageSize - Items per page (default: 100)
   * @returns Merged array of all items across pages
   */
  async paginate<T = unknown>(
    path: string,
    arrayKey: string,
    pageSize = 100
  ): Promise<T[]> {
    const separator = path.includes("?") ? "&" : "?";
    let offset = 0;
    const allItems: T[] = [];
    const maxPages = 100; // safety cap

    for (let page = 0; page < maxPages; page++) {
      const url = `${path}${separator}offset=${offset}&limit=${pageSize}`;
      const response = await this.get<Record<string, unknown>>(url);

      const items = (response[arrayKey] ?? []) as T[];
      allItems.push(...items);

      const total =
        (response.filteredTotalCount as number) ??
        (response.totalCount as number) ??
        undefined;

      offset += pageSize;

      if (items.length === 0) break;
      if (total !== undefined && offset >= total) break;
    }

    return allItems;
  }

  // -------------------------------------------------------------------------
  // API methods — Projects & Inventory
  // -------------------------------------------------------------------------

  /** List projects, optionally filtered by name. */
  async listProjects(params?: { name?: string; limit?: number }) {
    const query = new URLSearchParams();
    if (params?.name) query.set("name", params.name);

    const qs = query.toString();
    const path = `/api/projects${qs ? `?${qs}` : ""}`;

    if (params?.limit) {
      const data = await this.get<{ projects: unknown[] }>(
        `${path}${qs ? "&" : "?"}offset=0&limit=${params.limit}`
      );
      return data.projects ?? [];
    }
    return this.paginate(path, "projects");
  }

  /** Get a single project by UUID or exact name. */
  async getProject(identifier: string) {
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

    if (uuidRegex.test(identifier)) {
      return this.get(`/api/projects/${identifier}`);
    }

    // Search by name, then exact-match filter
    const encoded = encodeURIComponent(identifier);
    const data = await this.get<{ projects: Array<{ name: string }> }>(
      `/api/projects?name=${encoded}&limit=100`
    );
    const match = data.projects?.find((p) => p.name === identifier);
    if (!match) {
      const similar = data.projects?.map((p) => p.name).slice(0, 10) ?? [];
      throw new Error(
        `Project "${identifier}" not found.${similar.length ? ` Similar: ${similar.join(", ")}` : ""}`
      );
    }
    return match;
  }

  // -------------------------------------------------------------------------
  // API methods — Scans
  // -------------------------------------------------------------------------

  /** List scans with optional filters. */
  async listScans(params?: {
    projectId?: string;
    statuses?: string;
    limit?: number;
  }) {
    const query = new URLSearchParams();
    if (params?.projectId) query.set("project-id", params.projectId);
    if (params?.statuses) query.set("statuses", params.statuses);

    const qs = query.toString();
    const path = `/api/scans${qs ? `?${qs}` : ""}`;

    if (params?.limit) {
      const data = await this.get<{ scans: unknown[] }>(
        `${path}${qs ? "&" : "?"}offset=0&limit=${params.limit}&sort=%2Bcreated_at`
      );
      return data.scans ?? [];
    }
    return this.paginate(path, "scans");
  }

  /** Get a single scan by ID. */
  async getScan(scanId: string) {
    return this.get(`/api/scans/${scanId}`);
  }

  /**
   * Get scan results summary for one or more scans.
   *
   * Returns aggregated vulnerability counts broken down by scanner type
   * (SAST, SCA, KICS, API Security), severity, status, and state. Much
   * faster than fetching individual results when you only need counts.
   *
   * @param scanIds - Array of scan UUIDs to summarize
   * @param options.includeQueries - Include per-query breakdown (query name + count)
   * @param options.includeFiles - Include per-file breakdown (file path + count)
   * @see docs/rest-api-reference.md § 11 (Results Summary API)
   */
  async scanSummary(
    scanIds: string[],
    options?: { includeQueries?: boolean; includeFiles?: boolean }
  ) {
    const params = scanIds.map((id) => `scan-ids=${id}`).join("&");
    let qs = `${params}&include-severity-status=true`;
    if (options?.includeQueries) qs += "&include-queries=true";
    if (options?.includeFiles) qs += "&include-files=true";
    return this.get(`/api/scan-summary?${qs}`);
  }

  // -------------------------------------------------------------------------
  // API methods — Results & Findings
  // -------------------------------------------------------------------------

  /**
   * List vulnerability results for a scan.
   *
   * Returns unified findings from all scanner engines (SAST, SCA, KICS,
   * API Security). Each result includes type, severity, status, state,
   * description, and scanner-specific data.
   *
   * @param params.scanId - Scan UUID to fetch results for
   * @param params.severity - Comma-separated: CRITICAL, HIGH, MEDIUM, LOW, INFO
   * @param params.state - Comma-separated triage state: TO_VERIFY, NOT_EXPLOITABLE, CONFIRMED, URGENT
   * @param params.status - Comma-separated finding lifecycle: NEW, RECURRENT, FIXED
   * @param params.limit - Max results (omit to auto-paginate all)
   * @see docs/rest-api-reference.md § 6 (Results API)
   */
  async listResults(params: {
    scanId: string;
    severity?: string;
    state?: string;
    status?: string;
    limit?: number;
  }) {
    const query = new URLSearchParams();
    query.set("scan-id", params.scanId);
    if (params.severity) query.set("severity", params.severity);
    if (params.state) query.set("state", params.state);
    if (params.status) query.set("status", params.status);

    const path = `/api/results?${query.toString()}`;

    if (params.limit) {
      const data = await this.get<{ results: unknown[] }>(
        `${path}&offset=0&limit=${params.limit}`
      );
      return data.results ?? [];
    }
    return this.paginate(path, "results");
  }

  /**
   * List projects with their last scan information in a single API call.
   *
   * Wraps GET /api/projects/last-scan which returns project details plus
   * the latest scan metadata (status, engines, dates, per-engine status).
   * Far more efficient than fetching scans per-project — replaces the N+1
   * pattern used by checkmarx.report.sh.
   *
   * @param params.applicationId - Filter to projects in this application
   * @param params.scanStatus - Filter by overall scan status (e.g., "Completed")
   * @param params.sastStatus - Filter by SAST engine status
   * @param params.scaStatus - Filter by SCA engine status
   * @param params.kicsStatus - Filter by KICS engine status
   * @param params.apisecStatus - Filter by API Security engine status
   * @param params.branch - Filter by branch name
   * @param params.useMainBranch - Only include scans from the project's main branch
   * @param params.limit - Max results to return
   * @see docs/rest-api-reference.md § 13.8
   */
  async listProjectsLastScan(params?: {
    applicationId?: string;
    scanStatus?: string;
    sastStatus?: string;
    scaStatus?: string;
    kicsStatus?: string;
    apisecStatus?: string;
    branch?: string;
    useMainBranch?: boolean;
    limit?: number;
  }) {
    const query = new URLSearchParams();
    if (params?.applicationId) query.set("application_id", params.applicationId);
    if (params?.scanStatus) query.set("scan_status", params.scanStatus);
    if (params?.sastStatus) query.set("sast_status", params.sastStatus);
    if (params?.scaStatus) query.set("sca_status", params.scaStatus);
    if (params?.kicsStatus) query.set("kics_status", params.kicsStatus);
    if (params?.apisecStatus) query.set("apisec_status", params.apisecStatus);
    if (params?.branch) query.set("branch", params.branch);
    if (params?.useMainBranch) query.set("use_main_branch", "true");

    if (params?.limit) query.set("limit", String(params.limit));
    query.set("offset", "0");

    const qs = query.toString();
    const path = `/api/projects/last-scan?${qs}`;

    const data = await this.get<Record<string, unknown>>(path);

    // Response shape may vary — handle array or wrapped object
    if (Array.isArray(data)) return data;
    for (const key of ["projects", "items"]) {
      if (Array.isArray((data as Record<string, unknown>)[key])) {
        return (data as Record<string, unknown>)[key];
      }
    }
    return data;
  }

  // -------------------------------------------------------------------------
  // API methods — SAST Analysis
  // -------------------------------------------------------------------------

  /**
   * Get aggregated SAST finding counts grouped by category.
   *
   * Wraps GET /api/sast-scan-summary/aggregate. Returns SAST counts
   * grouped by one or more fields: QUERY, SEVERITY, STATUS, SOURCE_FILE,
   * SINK_FILE, SOURCE_NODE, SINK_NODE, or LANGUAGE. Use this for
   * vulnerability distribution reports and top-N query type lists.
   *
   * @param params.scanId - Scan UUID to aggregate
   * @param params.groupByFields - One or more grouping fields
   * @param params.severity - Comma-separated severity filter (HIGH, MEDIUM, LOW, INFO)
   * @param params.status - Comma-separated status filter (NEW, RECURRENT)
   * @param params.language - Comma-separated language filter
   * @param params.limit - Max results per page (API default: 20)
   * @see docs/rest-api-reference.md § 8.1
   */
  async sastAggregate(params: {
    scanId: string;
    groupByFields: string[];
    severity?: string;
    status?: string;
    language?: string;
    limit?: number;
  }) {
    const query = new URLSearchParams();
    query.set("scan-id", params.scanId);
    for (const field of params.groupByFields) {
      query.append("group-by-field", field);
    }
    if (params.severity) query.set("severity", params.severity);
    if (params.status) query.set("status", params.status);
    if (params.language) query.set("language", params.language);
    if (params.limit) query.set("limit", String(params.limit));

    return this.get(`/api/sast-scan-summary/aggregate?${query.toString()}`);
  }

  /**
   * Compare SAST results between two scans.
   *
   * Wraps GET /api/sast-scan-summary/compare/aggregate. Shows the diff
   * between two scans: NEW findings (appeared in newer scan), RECURRENT
   * findings (present in both), and FIXED findings (resolved). Results
   * are grouped by LANGUAGE or QUERY.
   *
   * @param params.scanId - UUID of the newer scan
   * @param params.baseScanId - UUID of the older scan to compare against
   * @param params.groupByFields - Grouping: LANGUAGE and/or QUERY
   * @param params.severity - Comma-separated severity filter
   * @param params.status - Comma-separated status filter (NEW, RECURRENT, FIXED)
   * @param params.language - Comma-separated language filter
   * @param params.limit - Max results per page (API default: 20)
   * @see docs/rest-api-reference.md § 8.2
   */
  async sastCompare(params: {
    scanId: string;
    baseScanId: string;
    groupByFields: string[];
    severity?: string;
    status?: string;
    language?: string;
    limit?: number;
  }) {
    const query = new URLSearchParams();
    query.set("scan-id", params.scanId);
    query.set("base-scan-id", params.baseScanId);
    for (const field of params.groupByFields) {
      query.append("group-by-field", field);
    }
    if (params.severity) query.set("severity", params.severity);
    if (params.status) query.set("status", params.status);
    if (params.language) query.set("language", params.language);
    if (params.limit) query.set("limit", String(params.limit));

    return this.get(
      `/api/sast-scan-summary/compare/aggregate?${query.toString()}`
    );
  }

  // -------------------------------------------------------------------------
  // API methods — Organization
  // -------------------------------------------------------------------------

  /** List applications, optionally filtered by name. */
  async listApplications(params?: { name?: string }) {
    const path = params?.name
      ? `/api/applications?name=${encodeURIComponent(params.name)}`
      : "/api/applications";
    return this.paginate(path, "applications");
  }

  /** List access management groups. */
  async listGroups(params?: { search?: string }) {
    const path = params?.search
      ? `/api/access-management/groups?search=${encodeURIComponent(params.search)}`
      : "/api/access-management/groups";

    const data = await this.get<unknown>(path);

    // The groups endpoint may return a flat array or { groups: [...] }
    if (Array.isArray(data)) return data;
    if (typeof data === "object" && data !== null && "groups" in data) {
      return (data as { groups: unknown[] }).groups;
    }
    return data;
  }

  // -------------------------------------------------------------------------
  // API methods — SAST Triage & Detailed Results
  // -------------------------------------------------------------------------

  /**
   * Get the latest triage predicates for a SAST finding.
   *
   * Wraps GET /api/sast-results-predicates/{similarity_id}/latest.
   * Returns the current triage state for a finding: severity overrides,
   * state changes (TO_VERIFY → CONFIRMED, etc.), and analyst comments.
   * Use this for compliance reporting and understanding triage decisions.
   *
   * @param params.similarityId - Similarity ID of the SAST finding (from result objects)
   * @param params.projectIds - Comma-separated project UUIDs to scope the query
   * @param params.scanId - Scope to a specific scan
   * @see docs/rest-api-reference.md § 9.2
   */
  async getSastPredicates(params: {
    similarityId: string;
    projectIds?: string;
    scanId?: string;
  }) {
    const query = new URLSearchParams();
    if (params.projectIds) query.set("project-ids", params.projectIds);
    if (params.scanId) query.set("scan-id", params.scanId);

    const qs = query.toString();
    return this.get(
      `/api/sast-results-predicates/${params.similarityId}/latest${qs ? `?${qs}` : ""}`
    );
  }

  /**
   * List SAST-specific results with rich filtering.
   *
   * Wraps GET /api/sast-results which provides much richer filtering
   * than the generic /api/results endpoint: filter by SAST query name,
   * programming language, CWE ID, source/sink file paths, compliance
   * framework, and vulnerability category. Also supports including
   * full source-to-sink node details in each result.
   *
   * @param params.scanId - Scan UUID
   * @param params.severity - Comma-separated: CRITICAL, HIGH, MEDIUM, LOW, INFO
   * @param params.status - Comma-separated: NEW, RECURRENT
   * @param params.state - Comma-separated: TO_VERIFY, NOT_EXPLOITABLE, CONFIRMED, etc.
   * @param params.query - Filter by SAST query name (e.g., "SQL_Injection")
   * @param params.language - Comma-separated language filter (e.g., "JavaScript,TypeScript")
   * @param params.cweId - Filter by CWE ID (e.g., "79" for XSS)
   * @param params.sourceFile - Filter by source file path (substring)
   * @param params.sinkFile - Filter by sink file path (substring)
   * @param params.compliance - Filter by compliance framework
   * @param params.category - Filter by vulnerability category
   * @param params.applyPredicates - Apply triage predicates to results (default: true)
   * @param params.includeNodes - Include source-to-sink node details
   * @param params.limit - Max results (omit to auto-paginate all)
   * @see docs/rest-api-reference.md § 7 (SAST Results API)
   */
  async listSastResults(params: {
    scanId: string;
    severity?: string;
    status?: string;
    state?: string;
    query?: string;
    language?: string;
    cweId?: string;
    sourceFile?: string;
    sinkFile?: string;
    compliance?: string;
    category?: string;
    applyPredicates?: boolean;
    includeNodes?: boolean;
    limit?: number;
  }) {
    const q = new URLSearchParams();
    q.set("scan-id", params.scanId);
    if (params.severity) q.set("severity", params.severity);
    if (params.status) q.set("status", params.status);
    if (params.state) q.set("state", params.state);
    if (params.query) q.set("query", params.query);
    if (params.language) q.set("language", params.language);
    if (params.cweId) q.set("cweId", params.cweId);
    if (params.sourceFile) q.set("source-file", params.sourceFile);
    if (params.sinkFile) q.set("sink-file", params.sinkFile);
    if (params.compliance) q.set("compliance", params.compliance);
    if (params.category) q.set("category", params.category);
    if (params.applyPredicates !== undefined)
      q.set("apply-predicates", String(params.applyPredicates));
    if (params.includeNodes) q.set("include-nodes", "true");

    const path = `/api/sast-results?${q.toString()}`;

    if (params.limit) {
      const data = await this.get<{ results: unknown[] }>(
        `${path}&offset=0&limit=${params.limit}`
      );
      return data.results ?? [];
    }
    return this.paginate(path, "results");
  }

  /** List SAST query presets. */
  async listPresets() {
    return this.get("/api/queries/presets");
  }

  // -------------------------------------------------------------------------
  // API methods — Trend Analysis
  // -------------------------------------------------------------------------

  /** Engine name → scan-summary counter key mapping. */
  private static readonly ENGINE_MAP: Record<string, string> = {
    sast: "sastCounters",
    sca: "scaCounters",
    kics: "kicsCounters",
    containers: "scaContainersCounters",
    apisec: "apiSecCounters",
  };

  private static readonly ALL_ENGINES = ["sast", "sca", "kics", "containers", "apisec"];

  /**
   * Resolve scope to an array of project IDs.
   * Exactly one of projectId, applicationId, or neither (tenant-wide).
   */
  private async resolveProjectIds(params: {
    projectId?: string;
    applicationId?: string;
  }): Promise<string[]> {
    if (params.projectId && params.applicationId) {
      throw new Error("Cannot specify both project_id and application_id");
    }
    if (params.projectId) return [params.projectId];

    if (params.applicationId) {
      const apps = await this.paginate<{ id: string; projectIds?: string[] }>(
        "/api/applications",
        "applications"
      );
      const app = apps.find((a) => a.id === params.applicationId);
      if (!app || !app.projectIds?.length) {
        throw new Error(
          `Application ${params.applicationId} not found or has no projects`
        );
      }
      return app.projectIds;
    }

    // Tenant-wide
    const projects = await this.paginate<{ id: string }>(
      "/api/projects",
      "projects"
    );
    return projects.map((p) => p.id);
  }

  /**
   * Generate time buckets for a given period and range.
   * Returns array of {period, start, end} ordered most-recent-first.
   */
  private generateDateRange(
    periodType: string,
    range: number
  ): Array<{ period: string; start: string; end: string }> {
    const now = new Date();
    const buckets: Array<{ period: string; start: string; end: string }> = [];

    for (let i = 0; i < range; i++) {
      let start: Date;
      let end: Date;
      let label: string;

      if (periodType === "monthly") {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        start = new Date(d.getFullYear(), d.getMonth(), 1);
        end = new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59);
        label = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      } else if (periodType === "quarterly") {
        const curQ = Math.floor(now.getMonth() / 3);
        const qIdx = curQ - i;
        const year = now.getFullYear() + Math.floor(qIdx / 4);
        const q = ((qIdx % 4) + 4) % 4;
        start = new Date(year, q * 3, 1);
        end = new Date(year, q * 3 + 3, 0, 23, 59, 59);
        label = `${year}-Q${q + 1}`;
      } else {
        // yearly
        const year = now.getFullYear() - i;
        start = new Date(year, 0, 1);
        end = new Date(year, 11, 31, 23, 59, 59);
        label = `${year}`;
      }

      buckets.push({
        period: label,
        start: start.toISOString(),
        end: end.toISOString(),
      });
    }

    return buckets;
  }

  /**
   * Build a scan timeline: one representative scan per project per period.
   * Accepts pre-computed buckets to avoid clock-skew between calls.
   */
  private async buildTimeline(params: {
    projectId?: string;
    applicationId?: string;
    period: string;
    range: number;
    buckets?: Array<{ period: string; start: string; end: string }>;
  }): Promise<
    Array<{ period: string; scanId: string | null; projectId: string }>
  > {
    const projectIds = await this.resolveProjectIds(params);
    const buckets = params.buckets ?? this.generateDateRange(params.period, params.range);
    const timeline: Array<{
      period: string;
      scanId: string | null;
      projectId: string;
    }> = [];

    for (const pid of projectIds) {
      // Fetch all completed scans for this project, sorted ascending
      const scans = await this.paginate<{
        id: string;
        createdAt: string;
      }>(`/api/scans?project-id=${pid}&statuses=Completed&sort=%2Bcreated_at`, "scans");

      for (const bucket of buckets) {
        const bucketStart = Date.parse(bucket.start);
        const bucketEnd = Date.parse(bucket.end) + 999; // include full final second
        const match = scans
          .filter((s) => {
            const t = Date.parse(s.createdAt);
            return t >= bucketStart && t <= bucketEnd;
          })
          .pop(); // latest in ascending order = last

        timeline.push({
          period: bucket.period,
          scanId: match?.id ?? null,
          projectId: pid,
        });
      }
    }

    return timeline;
  }

  /**
   * Extract severity counts from a scan-summary counter object.
   */
  private static extractSeverity(
    counter: Record<string, unknown> | null
  ): Record<string, number> | null {
    if (!counter) return null;
    const sevs = (counter.severityCounters ?? []) as Array<{
      severity: string;
      counter: number;
    }>;
    const counts: Record<string, number> = {
      critical: 0, high: 0, medium: 0, low: 0, info: 0,
    };
    for (const s of sevs) {
      const key = s.severity.toLowerCase();
      if (key in counts) counts[key] = s.counter;
    }
    counts.total = counts.critical + counts.high + counts.medium + counts.low + counts.info;
    return counts;
  }

  /**
   * Severity trend over time.
   *
   * Returns severity counts per engine per time period. Uses scan-summary
   * data batched across all timeline scan IDs.
   *
   * @param params.projectId - Single project scope
   * @param params.applicationId - Application scope (all projects in app)
   * @param params.period - monthly, quarterly, or yearly
   * @param params.range - Number of periods back (default: 6)
   * @param params.engines - Comma-separated engine filter (default: all)
   */
  async trendSeverity(params: {
    projectId?: string;
    applicationId?: string;
    period: string;
    range?: number;
    engines?: string;
  }) {
    const range = params.range ?? 6;
    const engineList = (params.engines ?? "sast,sca,kics,containers,apisec")
      .split(",")
      .map((e) => e.trim());

    // Generate buckets once to avoid clock-skew between buildTimeline and output
    const buckets = this.generateDateRange(params.period, range);

    const timeline = await this.buildTimeline({
      projectId: params.projectId,
      applicationId: params.applicationId,
      period: params.period,
      range,
      buckets,
    });

    // Collect unique non-null scan IDs
    const scanIds = [
      ...new Set(timeline.map((t) => t.scanId).filter((id): id is string => id !== null)),
    ];

    // Batch fetch summaries (chunked to avoid URL length limits)
    const summaryMap: Record<string, Record<string, unknown>> = {};
    const chunkSize = 50;
    for (let i = 0; i < scanIds.length; i += chunkSize) {
      const chunk = scanIds.slice(i, i + chunkSize);
      const qs = chunk.map((id) => `scan-ids=${id}`).join("&");
      const data = await this.get<{
        scansSummaries?: Array<{ scanId: string } & Record<string, unknown>>;
      }>(`/api/scan-summary?${qs}&include-severity-status=true`);
      for (const s of data.scansSummaries ?? []) {
        summaryMap[s.scanId] = s;
      }
    }

    // Group timeline by period
    const periodMap = new Map<
      string,
      Array<{ scanId: string | null; projectId: string }>
    >();
    for (const t of timeline) {
      if (!periodMap.has(t.period)) periodMap.set(t.period, []);
      periodMap.get(t.period)!.push(t);
    }

    // Build output: ordered by period descending (most recent first)
    return buckets.map((bucket) => {
      const entries = periodMap.get(bucket.period) ?? [];
      const result: Record<string, unknown> = { period: bucket.period };

      const totals: Record<string, number> = {
        critical: 0, high: 0, medium: 0, low: 0, info: 0, total: 0,
      };
      let hasData = false;

      for (const eng of engineList) {
        const counterKey = CheckmarxClient.ENGINE_MAP[eng];
        let engineTotals: Record<string, number> | null = null;

        for (const entry of entries) {
          if (!entry.scanId) continue;
          const summary = summaryMap[entry.scanId];
          if (!summary) continue;
          const sev = CheckmarxClient.extractSeverity(
            (summary[counterKey] as Record<string, unknown>) ?? null
          );
          if (!sev) continue;
          hasData = true;
          if (!engineTotals) {
            engineTotals = { ...sev };
          } else {
            for (const k of Object.keys(sev)) engineTotals[k] += sev[k];
          }
        }

        result[eng] = engineTotals;
        if (engineTotals) {
          for (const k of Object.keys(engineTotals)) totals[k] += engineTotals[k];
        }
      }

      result.total = hasData ? totals : null;
      return result;
    });
  }

  /**
   * New-vs-fixed trend over time (period-over-period deltas).
   *
   * Returns the change in severity counts between consecutive periods.
   * Negative net_change = improvement. Positive = regression.
   *
   * @param params.projectId - Single project scope
   * @param params.applicationId - Application scope
   * @param params.period - monthly, quarterly, or yearly
   * @param params.range - Number of periods back (default: 6)
   * @param params.engines - Comma-separated engine filter (default: all)
   */
  async trendNewVsFixed(params: {
    projectId?: string;
    applicationId?: string;
    period: string;
    range?: number;
    engines?: string;
  }) {
    // Get the severity snapshots first
    const snapshots = (await this.trendSeverity(params)) as Array<
      Record<string, unknown>
    >;

    const engineList = (params.engines ?? "sast,sca,kics,containers,apisec")
      .split(",")
      .map((e) => e.trim());

    return snapshots.map((current, i) => {
      if (i === snapshots.length - 1) {
        // Oldest period: no prior to diff
        const result: Record<string, unknown> = { period: current.period };
        for (const eng of engineList) result[eng] = null;
        result.total = null;
        return result;
      }

      const prev = snapshots[i + 1];
      const result: Record<string, unknown> = { period: current.period };
      const totalDelta: Record<string, number> = {
        critical: 0, high: 0, medium: 0, low: 0, info: 0, net_change: 0,
      };
      let hasData = false;

      for (const eng of engineList) {
        const cur = current[eng] as Record<string, number> | null;
        const prv = prev[eng] as Record<string, number> | null;

        if (!cur || !prv) {
          result[eng] = null;
          continue;
        }

        hasData = true;
        const delta: Record<string, number> = {};
        for (const sev of ["critical", "high", "medium", "low", "info"]) {
          delta[sev] = (cur[sev] ?? 0) - (prv[sev] ?? 0);
        }
        delta.net_change =
          delta.critical + delta.high + delta.medium + delta.low + delta.info;

        result[eng] = delta;
        for (const k of Object.keys(delta)) totalDelta[k] += delta[k];
      }

      result.total = hasData ? totalDelta : null;
      return result;
    });
  }

  // -------------------------------------------------------------------------
  // API methods — Reports
  // -------------------------------------------------------------------------

  /**
   * Generate and wait for a scan report.
   * Returns the report status response (with download URL if returnUrl=true).
   * Note: actual file download is not practical in MCP context, so we return
   * the status + URL for the caller to use.
   */
  async getReport(params: {
    scanId: string;
    projectId: string;
    format?: string;
  }) {
    const format = params.format ?? "pdf";

    // Step 1: Create report
    const createResponse = await this.post<{ reportId: string }>(
      "/api/reports",
      {
        reportName: "scan-report",
        reportType: "cli",
        fileFormat: format,
        data: {
          scanId: params.scanId,
          projectId: params.projectId,
          sections: ["ScanSummary", "ExecutiveSummary", "ScanResults"],
          scanners: ["SAST", "SCA", "KICS"],
        },
      }
    );

    const reportId = createResponse.reportId;
    if (!reportId) {
      throw new Error(
        `Failed to create report: ${JSON.stringify(createResponse)}`
      );
    }

    // Step 2: Poll for completion (max 5 minutes)
    const maxAttempts = 60;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      await new Promise((resolve) => setTimeout(resolve, 5000));

      const status = await this.get<{
        reportId: string;
        status: string;
        reportUrl?: string;
      }>(`/api/reports/${reportId}?returnUrl=true`);

      if (status.status === "completed") {
        return {
          reportId,
          status: "completed",
          format,
          reportUrl: status.reportUrl,
          downloadPath: `/api/reports/${reportId}/download`,
        };
      }

      if (status.status === "failed") {
        throw new Error(`Report generation failed: ${JSON.stringify(status)}`);
      }
    }

    throw new Error(`Report generation timed out after ${maxAttempts * 5}s`);
  }
}
