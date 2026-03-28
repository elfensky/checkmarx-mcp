/**
 * Checkmarx One API Client
 *
 * Handles authentication (API key or OAuth2 client credentials),
 * in-memory token caching, pagination, and authenticated HTTP requests.
 *
 * This is a TypeScript port of the patterns in lib.sh from checkmarx-cli.
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
  // API methods (matching utils/ scripts)
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

  /** Get scan results summary for one or more scans. */
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

  /** List vulnerability results for a scan. */
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

  /** List projects with their last scan information. */
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

  /** Get aggregated SAST results grouped by category. */
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

  /** Compare SAST results between two scans. */
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

  /** Get latest triage predicates for a SAST finding. */
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

  /** List SAST-specific results with rich filtering. */
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
