# Checkmarx One REST API - Comprehensive Reference

## Table of Contents

1. [Authentication](#1-authentication)
2. [Regional Base URLs](#2-regional-base-urls)
3. [Scans API](#3-scans-api)
4. [Uploads API](#4-uploads-api)
5. [Reports API](#5-reports-api)
6. [Results API (Scanners Results)](#6-results-api-scanners-results)
7. [SAST Results API](#7-sast-results-api)
8. [SAST Results Summary API](#8-sast-results-summary-api)
9. [SAST Results Predicates API](#9-sast-results-predicates-api)
10. [KICS (IaC) Results API](#10-kics-iac-results-api)
11. [Results Summary API](#11-results-summary-api)
12. [Applications API](#12-applications-api)
13. [Projects API](#13-projects-api)
14. [Groups & Access Management API](#14-groups--access-management-api)
15. [Queries API (SAST Queries)](#15-queries-api-sast-queries)
16. [Scan Configuration API](#16-scan-configuration-api)
17. [Audit Trail API](#17-audit-trail-api)
18. [SCA APIs](#18-sca-apis)
19. [Webhooks API](#19-webhooks-api)
20. [Common Patterns](#20-common-patterns)

---

## 1. Authentication

Checkmarx One uses **OAuth 2.0 / OpenID Connect** via Keycloak for authentication. All API calls require a `Bearer` token in the `Authorization` header.

### Token Endpoint

```
POST https://{iam-base-url}/auth/realms/{tenant-name}/protocol/openid-connect/token
```

### IAM Base URLs by Region

| Region | IAM URL |
|--------|---------|
| US (Multi-Tenant) | `https://iam.checkmarx.net` |
| US2 | `https://us.iam.checkmarx.net` |
| EU | `https://eu.iam.checkmarx.net` |
| EU2 | `https://eu-2.iam.checkmarx.net` |
| DEU | `https://deu.iam.checkmarx.net` |
| ANZ (Australia/NZ) | `https://anz.iam.checkmarx.net` |
| India | `https://ind.iam.checkmarx.net` |
| Singapore | `https://sng.iam.checkmarx.net` |
| UAE | `https://mea.iam.checkmarx.net` |

### Grant Type: client_credentials (OAuth Client)

```bash
curl -X POST \
  "https://iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id={client_id}" \
  -d "client_secret={client_secret}"
```

### Grant Type: refresh_token (API Key)

```bash
curl -X POST \
  "https://iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=ast-app" \
  -d "refresh_token={api_key}"
```

### Response

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "expires_in": 3600,
  "refresh_expires_in": 36000,
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "Bearer",
  "not-before-policy": 0,
  "session_state": "...",
  "scope": "..."
}
```

### Common Headers for All API Calls

```
Authorization: Bearer {access_token}
Content-Type: application/json
Accept: application/json
```

---

## 2. Regional Base URLs

All API endpoints use `{base-url}` as a prefix. Select the base URL for your region:

| Region | API Base URL |
|--------|-------------|
| US | `https://ast.checkmarx.net` |
| US2 | `https://us.ast.checkmarx.net` |
| EU | `https://eu.ast.checkmarx.net` |
| EU2 | `https://eu-2.ast.checkmarx.net` |
| DEU | `https://deu.ast.checkmarx.net` |
| ANZ | `https://anz.ast.checkmarx.net` |
| India | `https://ind.ast.checkmarx.net` |
| Singapore | `https://sng.ast.checkmarx.net` |
| UAE | `https://mea.ast.checkmarx.net` |

### SCA-Specific Base URLs

| Region | SCA API URL |
|--------|-------------|
| US | `https://api-sca.checkmarx.net` |
| EU | `https://eu.api-sca.checkmarx.net` |

### Swagger / OpenAPI Specs

Available at `{base-url}/spec/v1/` -- select the desired API definition from the dropdown.

---

## 3. Scans API

**Base Path:** `/api/scans`

### 3.1 Create Scan

```
POST /api/scans
```

**Request Body (ScanInput):**

```json
{
  "type": "upload",
  "handler": {
    "url": "https://uploads.checkmarx.net/..."
  },
  "project": {
    "id": "project-uuid"
  },
  "configs": [
    {
      "type": "sast",
      "value": {
        "incremental": "true",
        "presetName": "Checkmarx Default"
      }
    },
    {
      "type": "sca",
      "value": {}
    },
    {
      "type": "kics",
      "value": {}
    }
  ],
  "tags": {
    "env": "production",
    "team": "security"
  }
}
```

**ScanInput Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | `"upload"` or `"git"` |
| `handler` | object | Yes | Contains `url` (upload link or git repo URL). For git: `{ "repoUrl": "...", "branch": "main" }` |
| `project` | object | No | `{ "id": "project-uuid" }` |
| `configs` | array | No | Array of `ScanConfig` objects. Types: `sast`, `sca`, `kics`, `apisec`, `system` |
| `tags` | object | No | Key-value pairs for scan tagging |

**ScanConfig value (for SAST):**

| Key | Type | Description |
|-----|------|-------------|
| `incremental` | string | `"true"` or `"false"` |
| `presetName` | string | SAST preset name (e.g., `"Checkmarx Default"`) |

**Response (201 Created) -- Scan object:**

```json
{
  "id": "scan-uuid",
  "status": "Queued",
  "statusDetails": [],
  "positionInQueue": 5,
  "projectId": "project-uuid",
  "projectName": "my-project",
  "branch": "main",
  "commitId": "abc123",
  "commitTag": "",
  "uploadUrl": "",
  "createdAt": "2025-01-15T10:30:00Z",
  "updatedAt": "2025-01-15T10:30:00Z",
  "userAgent": "ast-cli",
  "initiator": "user@example.com",
  "tags": { "env": "production" },
  "metadata": {},
  "engines": ["sast", "sca"],
  "sourceType": "zip",
  "sourceOrigin": "API"
}
```

**Scan Status Values:** `Queued`, `Running`, `Completed`, `Failed`, `Partial`, `Canceled`

**curl Example:**

```bash
curl -X POST "{base-url}/api/scans" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "git",
    "handler": { "repoUrl": "https://github.com/org/repo", "branch": "main" },
    "project": { "id": "project-uuid" },
    "configs": [
      { "type": "sast", "value": { "presetName": "Checkmarx Default" } },
      { "type": "sca" },
      { "type": "kics" }
    ],
    "tags": { "pipeline": "ci" }
  }'
```

### 3.2 List Scans

```
GET /api/scans
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `offset` | int | 0 | Items to skip |
| `limit` | int | 20 | Max items to return |
| `scan-ids` | string | | Comma-separated scan IDs |
| `project-id` | string | | Filter by single project ID |
| `project-ids` | string | | Comma-separated project IDs |
| `project-names` | string | | Filter by project names |
| `statuses` | string | | Filter by statuses (comma-separated) |
| `source-type` | string | | Filter by source type |
| `source-origin` | string | | Filter by source origin |
| `tags-keys` | string | | Filter by tag keys |
| `tags-values` | string | | Filter by tag values |
| `groups` | string | | Filter by groups |
| `from-date` | string | | Start date filter |
| `to-date` | string | | End date filter |
| `sort` | string | | Sort field with +/- prefix |
| `field` | string | | Field filter |
| `search` | string | | Search term |
| `initiators` | string | | Filter by scan initiators |
| `branch` | string | | Filter by branch |
| `branches` | string | | Filter by multiple branches |

**Response (200 OK) -- ScansCollection:**

```json
{
  "totalCount": 150,
  "filteredTotalCount": 25,
  "scans": [
    {
      "id": "scan-uuid",
      "status": "Completed",
      "statusDetails": [...],
      "projectId": "...",
      "projectName": "...",
      "branch": "main",
      "createdAt": "...",
      "updatedAt": "...",
      "engines": ["sast", "sca"],
      "tags": {}
    }
  ]
}
```

### 3.3 Get Scan by ID

```
GET /api/scans/{id}
```

**Response:** Single Scan object (same schema as create response).

### 3.4 Cancel Scan

```
PATCH /api/scans/{id}
```

**Request Body:**

```json
{
  "status": "Canceled"
}
```

**Response:** `204 No Content`

### 3.5 Delete Scan

```
DELETE /api/scans/{id}
```

**Response:** `204 No Content`

### 3.6 Get Scan Workflow

```
GET /api/scans/{id}/workflow
```

**Response (200 OK):** Array of `TaskInfo` objects showing detailed step-by-step scan progress.

### 3.7 Get All Scan Tags

```
GET /api/scans/tags
```

**Response:** Dictionary of all tags used across scans.

### 3.8 Get Scans Status Summary

```
GET /api/scans/summary
```

**Response:** Summary counts by scan status.

### 3.9 List Config-as-Code Templates

```
GET /api/scans/templates
```

**Response:** Dictionary of available config-as-code template files.

### 3.10 Get Config-as-Code Template File

```
GET /api/scans/templates/{file_name}
```

**Response:** Template file content (text/plain).

### 3.11 Get Scans by Filters (POST)

```
POST /api/scans/byFilters
```

**Request Body:**

```json
{
  "offset": 0,
  "limit": 20,
  "sortBy": "+created_at",
  "scan-ids": [],
  "tags-keys": [],
  "tags-values": [],
  "statuses": ["Completed"],
  "projectIDs": ["project-uuid"],
  "project-names": [],
  "branches": ["main"],
  "initiators": [],
  "source-origins": [],
  "source-types": [],
  "searchID": ""
}
```

### 3.12 SCA Recalculate

```
POST /api/scans/recalculate
```

**Request Body:**

```json
{
  "project_id": "project-uuid",
  "branch": "main",
  "engines": ["sca"],
  "config": [...]
}
```

---

## 4. Uploads API

**Base Path:** `/api/uploads`

### 4.1 Generate Pre-Signed Upload URL

```
POST /api/uploads
```

**Request Body:** None

**Response (200 OK):**

```json
{
  "url": "https://uploads.checkmarx.net/presigned-upload-url..."
}
```

### 4.2 Upload ZIP Content

```
PUT {pre-signed-url}
```

**Request:** Multipart form data with field `zippedSource` (content-type: `application/zip`).

**Response:** `200 OK`

**curl Example (full upload + scan flow):**

```bash
# Step 1: Get upload URL
UPLOAD_URL=$(curl -s -X POST "{base-url}/api/uploads" \
  -H "Authorization: Bearer {token}" | jq -r '.url')

# Step 2: Upload ZIP
curl -X PUT "$UPLOAD_URL" \
  -H "Content-Type: application/zip" \
  --data-binary @source.zip

# Step 3: Create scan with upload URL
curl -X POST "{base-url}/api/scans" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"upload\",
    \"handler\": { \"url\": \"$UPLOAD_URL\" },
    \"project\": { \"id\": \"project-uuid\" },
    \"configs\": [{ \"type\": \"sast\" }, { \"type\": \"sca\" }]
  }"
```

---

## 5. Reports API

**Base Path:** `/api/reports`

### 5.1 Create Report (Standard / v1)

```
POST /api/reports
```

**Request Body:**

```json
{
  "reportName": "scan-report",
  "reportType": "cli",
  "fileFormat": "pdf",
  "data": {
    "scanId": "scan-uuid",
    "projectId": "project-uuid",
    "branchName": "main",
    "sections": ["ScanSummary", "ExecutiveSummary", "ScanResults"],
    "scanners": ["SAST", "SCA", "KICS"],
    "host": ""
  }
}
```

**Request Body Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reportName` | string | Yes | Report name/identifier: `"scan-report"`, `"application-list"`, etc. |
| `reportType` | string | Yes | Distribution type: `"cli"`, `"ui"`, `"email"` |
| `fileFormat` | string | Yes | Output format: `"pdf"`, `"json"`, `"csv"`, `"sarif"` |
| `data` | object | Yes | Report-specific data payload |
| `data.scanId` | string | Yes* | Scan ID for scan reports |
| `data.projectId` | string | Yes* | Project ID |
| `data.branchName` | string | No | Branch name filter |
| `data.sections` | array | No | Report sections to include |
| `data.scanners` | array | No | Scanner types to include: `"SAST"`, `"SCA"`, `"KICS"`, `"API_SECURITY"` |
| `data.host` | string | No | Base URL for links in report |
| `data.email` | array | No | Email recipients (when reportType is `"email"`) |

**Response (202 Accepted):**

```json
{
  "reportId": "report-uuid"
}
```

### 5.2 Create Report (Improved / v2)

```
POST /api/reports/v2
```

**Request Body:**

```json
{
  "fileFormat": "pdf",
  "reportName": "improved-scan-report",
  "reportFilename": "my-report",
  "sections": ["ScanSummary", "ScanResults"],
  "entities": [
    {
      "entity": {
        "id": "scan-uuid",
        "type": "scan"
      }
    }
  ],
  "filters": {
    "severity": ["HIGH", "MEDIUM"],
    "status": ["NEW", "RECURRENT"],
    "state": ["TO_VERIFY", "CONFIRMED"]
  },
  "reportType": "cli",
  "emails": []
}
```

**Response (202 Accepted):**

```json
{
  "reportId": "report-uuid"
}
```

### 5.3 Get Report Status

```
GET /api/reports/{reportId}?returnUrl=true
```

**Response (200 OK):**

```json
{
  "reportId": "report-uuid",
  "status": "completed",
  "reportUrl": "https://..."
}
```

**Report Status Values:** `requested`, `started`, `completed`, `failed`

### 5.4 Download Report

```
GET /api/reports/{reportId}/download
```

**Response:** Binary file content with appropriate Content-Type header.

**curl Example:**

```bash
# Step 1: Create report
REPORT_ID=$(curl -s -X POST "{base-url}/api/reports" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{
    "reportName": "scan-report",
    "reportType": "cli",
    "fileFormat": "pdf",
    "data": {
      "scanId": "scan-uuid",
      "projectId": "project-uuid",
      "branchName": "main",
      "sections": ["ScanSummary", "ExecutiveSummary", "ScanResults"],
      "scanners": ["SAST", "SCA", "KICS"]
    }
  }' | jq -r '.reportId')

# Step 2: Poll for completion
STATUS="requested"
while [ "$STATUS" != "completed" ]; do
  sleep 5
  STATUS=$(curl -s "{base-url}/api/reports/${REPORT_ID}?returnUrl=true" \
    -H "Authorization: Bearer {token}" | jq -r '.status')
done

# Step 3: Download
curl -o report.pdf "{base-url}/api/reports/${REPORT_ID}/download" \
  -H "Authorization: Bearer {token}"
```

---

## 6. Results API (Scanners Results)

**Base Path:** `/api/results`

### 6.1 Get All Scanner Results by Scan ID

```
GET /api/results
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `scan-id` | string | **Required** | Scan ID to fetch results for |
| `severity` | string[] | | Filter: `HIGH`, `MEDIUM`, `LOW`, `INFO` |
| `state` | string[] | | Filter: `TO_VERIFY`, `NOT_EXPLOITABLE`, `PROPOSED_NOT_EXPLOITABLE`, `CONFIRMED`, `URGENT` |
| `status` | string[] | | Filter: `NEW`, `RECURRENT`, `FIXED` |
| `offset` | int | 0 | Pagination offset |
| `limit` | int | 20 | Max results (use `0` for all) |
| `sort` | string[] | `["+status", "+severity"]` | Sort order. Pattern: `[-+]field`. `-` = ASC, `+` = DESC |

**Response (200 OK):**

```json
{
  "totalCount": 42,
  "results": [
    {
      "type": "sast",
      "id": "result-uuid",
      "similarityId": 123456789,
      "status": "NEW",
      "state": "TO_VERIFY",
      "severity": "HIGH",
      "confidenceLevel": 3,
      "created": "2025-01-15T10:30:00Z",
      "firstFoundAt": "2025-01-10T08:00:00Z",
      "foundAt": "2025-01-15T10:30:00Z",
      "updateAt": "2025-01-15T10:30:00Z",
      "firstScanId": "scan-uuid",
      "description": "SQL Injection vulnerability found",
      "data": { ... },
      "comments": "",
      "vulnerabilityDetails": { ... }
    }
  ]
}
```

**Result Object Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Engine type: `sast`, `sca`, `kics`, `apisec` |
| `id` | string | Unique result identifier |
| `similarityId` | int | Similarity-based grouping ID |
| `status` | string | `NEW`, `RECURRENT`, `FIXED` |
| `state` | string | `TO_VERIFY`, `NOT_EXPLOITABLE`, `PROPOSED_NOT_EXPLOITABLE`, `CONFIRMED`, `URGENT` |
| `severity` | string | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO` |
| `confidenceLevel` | int | 0-5 confidence scale |
| `created` | string | Result creation timestamp |
| `firstFoundAt` | string | When first detected |
| `foundAt` | string | Detection timestamp |
| `updateAt` | string | Last update timestamp |
| `firstScanId` | string | Scan where first found |
| `description` | string | Vulnerability description |
| `data` | object | Engine-specific result data |
| `comments` | string | User annotations |
| `vulnerabilityDetails` | object | Detailed vulnerability info |

---

## 7. SAST Results API

**Base Path:** `/api/sast-results`

### 7.1 Get SAST Results by Scan ID

```
GET /api/sast-results
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `scan-id` | string | **Required** | Scan ID |
| `severity` | string[] | | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO` |
| `state` | string[] | | `TO_VERIFY`, `NOT_EXPLOITABLE`, `PROPOSED_NOT_EXPLOITABLE`, `CONFIRMED`, `URGENT` |
| `status` | string[] | | `NEW`, `RECURRENT`, `FIXED` |
| `group` | string | | Substring match on vulnerability group |
| `compliance` | string | | Exact case-insensitive compliance match |
| `query` | string | | Exact query name match |
| `language` | string[] | | Case-insensitive language filter |
| `query-ids` | string[] | | Filter by query IDs |
| `node-ids` | string[] | | Filter by node IDs |
| `source-file` | string | | Source file name filter |
| `source-file-operation` | string | | `CONTAINS`, `EQUAL`, `NOT_CONTAINS`, `NOT_EQUAL`, `START_WITH`, `LESS_THAN`, `GREATER_THAN` |
| `source-node` | string | | Source node filter |
| `source-node-operation` | string | | Same operations as source-file |
| `source-line` | int | | Source line number |
| `source-line-operation` | string | | `LESS_THAN`, `GREATER_THAN`, `EQUAL`, `NOT_EQUAL` |
| `sink-node` | string | | Sink node filter |
| `sink-node-operation` | string | | Same operations as source-file |
| `sink-file` | string | | Sink file filter |
| `sink-file-operation` | string | | Same operations as source-file |
| `sink-line` | int | | Sink line number |
| `sink-line-operation` | string | | Same operations as source-line |
| `number-of-nodes` | int | | Node count filter |
| `number-of-nodes-operation` | string | | `LESS_THAN`, `GREATER_THAN`, `EQUAL`, `NOT_EQUAL` |
| `notes` | string | | Notes content filter |
| `notes-operation` | string | | `CONTAINS`, `START_WITH` |
| `first-found-at` | string | | Timestamp filter |
| `first-found-at-operation` | string | | `LESS_THAN`, `GREATER_THAN` (default: GREATER_THAN) |
| `preset-id` | string | | Preset ID filter |
| `result-id` | string[] | | Result hash filter |
| `category` | string | | Category name filter |
| `search` | string | | Full-text search across source file, source node, sink node, sink file, notes |
| `include-nodes` | bool | true | Include ResultNode objects |
| `apply-predicates` | bool | true | Apply predicate changes |
| `offset` | int | 0 | Pagination offset |
| `limit` | int | 20 | Max results |
| `sort` | string[] | `["+status", "+severity", "-queryname"]` | Sort order |

**Sort Fields:** `severity`, `status`, `firstfoundat`, `foundat`, `queryname`, `firstscanid`

**Response (200 OK):**

```json
{
  "totalCount": 150,
  "results": [
    {
      "id": "result-uuid",
      "resultHash": "hash-string",
      "queryId": 12345,
      "queryIdStr": "12345",
      "queryName": "SQL_Injection",
      "languageName": "Java",
      "queryGroup": "Java_High_Risk",
      "cweId": 89,
      "severity": "HIGH",
      "similarityId": 987654321,
      "confidenceLevel": 3,
      "compliances": ["OWASP Top 10 2021", "PCI DSS"],
      "firstScanId": "scan-uuid",
      "firstFoundAt": "2025-01-10T08:00:00Z",
      "pathSystemIdBySimiAndFilesPaths": "computed-path-id",
      "status": "NEW",
      "foundAt": "2025-01-15T10:30:00Z",
      "state": "TO_VERIFY",
      "changeDetails": { ... },
      "nodes": [
        {
          "id": "node-uuid",
          "line": 42,
          "column": 15,
          "name": "executeQuery",
          "type": "",
          "domType": "",
          "fileName": "/src/main/java/UserDao.java",
          "fullName": "UserDao.executeQuery",
          "length": 12,
          "method": "getUserById",
          "methodLine": 38
        }
      ]
    }
  ]
}
```

---

## 8. SAST Results Summary API

**Base Path:** `/api/sast-scan-summary`

### 8.1 Get SAST Aggregate Results

```
GET /api/sast-scan-summary/aggregate
```

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scan-id` | string | Yes | Scan ID |
| `group-by-field` | string[] | Yes | `QUERY`, `SEVERITY`, `STATUS`, `SOURCE_NODE`, `SINK_NODE`, `SOURCE_FILE`, `SINK_FILE`, `LANGUAGE` |
| `language` | string[] | No | Filter by language |
| `status` | string[] | No | `NEW`, `RECURRENT` |
| `severity` | string[] | No | `HIGH`, `MEDIUM`, `LOW`, `INFO` |
| `source-file` | string | No | Source file filter |
| `source-file-operation` | string | No | `CONTAINS`, `EQUAL` |
| `source-node` | string | No | Source node filter |
| `source-node-operation` | string | No | `CONTAINS`, `EQUAL` |
| `sink-node` | string | No | Sink node filter |
| `sink-node-operation` | string | No | `CONTAINS`, `EQUAL` |
| `sink-file` | string | No | Sink file filter |
| `sink-file-operation` | string | No | `CONTAINS`, `EQUAL` |
| `query-ids` | int[] | No | Query ID filter |
| `apply-predicates` | bool | No | Default: true |
| `limit` | int | No | Default: 20 |
| `offset` | int | No | Default: 0 |

**Response:** Aggregated result counts grouped by the specified fields.

### 8.2 Compare SAST Aggregate Results

```
GET /api/sast-scan-summary/compare/aggregate
```

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scan-id` | string | Yes | Newer scan ID |
| `base-scan-id` | string | Yes | Older scan ID to compare against |
| `group-by-field` | string[] | Yes | `LANGUAGE`, `QUERY` |
| `language` | string[] | No | Language filter |
| `status` | string[] | No | `NEW`, `RECURRENT`, `FIXED` |
| `severity` | string[] | No | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO` |
| `query-ids` | int[] | No | Query ID filter |
| `limit` | int | No | Default: 20 |
| `offset` | int | No | Default: 0 |

---

## 9. SAST Results Predicates API

**Base Path:** `/api/sast-results-predicates`

### 9.1 Get All Predicates for Similarity ID

```
GET /api/sast-results-predicates/{similarity_id}
```

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `project-ids` | string[] | Filter by project IDs |
| `include-comment-json` | bool | Include comment JSON |
| `scan-id` | string | Filter by scan ID |

### 9.2 Get Latest Predicates

```
GET /api/sast-results-predicates/{similarity_id}/latest
```

**Query Parameters:** `project-ids`, `scan-id`

### 9.3 Create Predicate (Severity/State)

```
POST /api/sast-results-predicates
```

**Request Body:** Array of predicate objects.

**Response:** `201 Created`

### 9.4 Update Predicate Comment

```
PATCH /api/sast-results-predicates
```

**Request Body:** Array of predicate patch objects.

**Response:** `204 No Content`

### 9.5 Recalculate Summary Counters

```
POST /api/sast-results-predicates/recalculateSummaryCounters
```

**Response:** `200 OK`

### 9.6 Delete Predicate History

```
DELETE /api/sast-results-predicates/{similarity_id}/{project_id}/{predicate_id}
```

**Response:** `204 No Content`

---

## 10. KICS (IaC) Results API

**Base Path:** `/api/kics-results`

### 10.1 Get KICS Results by Scan ID

```
GET /api/kics-results
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `scan-id` | string | **Required** | Scan ID |
| `severity` | string[] | | `HIGH`, `MEDIUM`, `LOW`, `INFO` |
| `status` | string[] | | `NEW`, `RECURRENT`, `FIXED` |
| `source-file` | string | | Source file filter |
| `apply-predicates` | bool | true | Apply predicates |
| `offset` | int | 0 | Pagination offset |
| `limit` | int | 20 | Max results |
| `sort` | string[] | `["+status", "+severity"]` | Sort order |

**Response (200 OK):** `KicsResultCollection` with `results` array and `totalCount`.

---

## 11. Results Summary API

**Base Path:** `/api/scan-summary`

### 11.1 Get Summary for Multiple Scans

```
GET /api/scan-summary
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `scan-ids` | string[] | **Required** | Scan IDs |
| `include-severity-status` | bool | true | Include severity/status breakdown |
| `include-queries` | bool | false | Include query details |
| `include-files` | bool | false | Include source/sink file info |
| `apply-predicates` | bool | true | Apply predicates |
| `language` | string | | Filter by language |

**Response (200 OK):**

```json
{
  "scansSummaries": [
    {
      "scanId": "scan-uuid",
      "sastCounters": {
        "totalCounter": 100,
        "severityCounters": [
          { "severity": "HIGH", "counter": 10 },
          { "severity": "MEDIUM", "counter": 30 }
        ],
        "statusCounters": [
          { "status": "NEW", "counter": 25 },
          { "status": "RECURRENT", "counter": 75 }
        ],
        "stateCounters": [...]
      },
      "kicsCounters": { ... },
      "scaCounters": { ... },
      "scaPackagesCounters": { ... },
      "scaContainersCounters": { ... },
      "apiSecCounters": { ... }
    }
  ],
  "totalCount": 1
}
```

---

## 12. Applications API

**Base Path:** `/api/applications`

### 12.1 Create Application

```
POST /api/applications
```

**Request Body (ApplicationInput):**

```json
{
  "name": "My Application",
  "description": "Production web application",
  "criticality": 3,
  "rules": [
    { "type": "project.name.contains", "value": "web-app" }
  ],
  "tags": {
    "business-unit": "finance",
    "environment": "production"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Application name |
| `description` | string | No | Description |
| `criticality` | int | No | 1-5 scale (default: 3) |
| `rules` | array | No | Auto-assignment rules |
| `tags` | object | No | Key-value tags |

**Response (201 Created):** `CreatedApplication` object with generated ID.

### 12.2 List Applications

```
GET /api/applications
```

**Query Parameters:** `offset`, `limit`, `name`, `tags-keys`, `tags-values`

**Response:** `ApplicationsCollection` with `applications` array and `totalCount`.

### 12.3 Get Application by ID

```
GET /api/applications/{id}
```

### 12.4 Update Application

```
PUT /api/applications/{id}
```

**Request Body:** Same as create (ApplicationInput).

**Response:** `204 No Content`

### 12.5 Delete Application

```
DELETE /api/applications/{id}
```

**Response:** `204 No Content`

### 12.6 Get All Application Tags

```
GET /api/applications/tags
```

### 12.7 Application Rules

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/applications/{id}/project-rules` | Create rule |
| `GET` | `/api/applications/{id}/project-rules` | List rules |
| `GET` | `/api/applications/{id}/project-rules/{rule_id}` | Get rule |
| `PUT` | `/api/applications/{id}/project-rules/{rule_id}` | Update rule |
| `DELETE` | `/api/applications/{id}/project-rules/{rule_id}` | Delete rule |

---

## 13. Projects API

**Base Path:** `/api/projects`

### 13.1 Create Project

```
POST /api/projects
```

**Request Body (ProjectInput):**

```json
{
  "name": "my-project",
  "groups": ["group-uuid-1"],
  "repoUrl": "https://github.com/org/repo",
  "mainBranch": "main",
  "origin": "API",
  "tags": {
    "team": "security"
  },
  "criticality": 3
}
```

### 13.2 List Projects

```
GET /api/projects
```

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `offset` | int | Pagination offset |
| `limit` | int | Max results |
| `ids` | string | Comma-separated project IDs |
| `names` | string | Comma-separated names |
| `name` | string | Exact name match |
| `name_regex` | string | Regex name match |
| `groups` | string | Filter by group IDs |
| `tags_keys` | string | Filter by tag keys |
| `tags_values` | string | Filter by tag values |
| `repo_url` | string | Filter by repository URL |

### 13.3 Get Project by ID

```
GET /api/projects/{id}
```

### 13.4 Update Project

```
PUT /api/projects/{id}
```

### 13.5 Partial Update Project

```
PATCH /api/projects/{id}
```

### 13.6 Delete Project

```
DELETE /api/projects/{id}
```

**Response:** `204 No Content`

### 13.7 Get All Project Tags

```
GET /api/projects/tags
```

### 13.8 Get Last Scan Info

```
GET /api/projects/last-scan
```

**Query Parameters:** `offset`, `limit`, `project_ids`, `application_id`, `scan_status`, `branch`, `engine`, `sast_status`, `kics_status`, `sca_status`, `apisec_status`, `micro_engines_status`, `containers_status`, `use_main_branch`

### 13.9 Get Branches

```
GET /api/projects/branches
```

**Query Parameters:** `offset`, `limit`, `project_id`, `branch_name`

### 13.10 Get Projects for Application

```
GET /api/projects/app/{app_id}
```

---

## 14. Groups & Access Management API

**Base Path:** `/api/access-management`

### 14.1 Groups

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/access-management/groups` | List all groups. Params: `limit`, `offset`, `search`, `ids` |
| `GET` | `/api/access-management/groups-resources` | Groups with assigned resources. Params: `search`, `base-roles`, `name`, `empty-assignments`, `no-members`, `sort-by`, `created-from`, `created-to`, `order`, `limit`, `offset` |
| `GET` | `/api/access-management/my-groups` | Current user's groups. Params: `include-subgroups`, `search`, `limit`, `offset` |
| `GET` | `/api/access-management/available-groups` | Available groups. Params: `project-id`, `search`, `limit`, `offset` |
| `GET` | `/api/access-management/internal/groups` | Internal group store |

### 14.2 Users

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/access-management/users` | List users. Params: `limit`, `offset`, `search` |
| `GET` | `/api/access-management/users-resources` | Users with resources. Params: `search`, `base-roles`, `username`, `empty-assignments`, `no-groups`, `created-from`, `created-to`, `sort-by`, `order`, `limit`, `offset` |

### 14.3 Roles & Permissions

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/access-management/roles` | List all roles |
| `POST` | `/api/access-management/roles` | Create custom role |
| `GET` | `/api/access-management/roles/{id}` | Get role details |
| `PUT` | `/api/access-management/roles/{id}` | Update role |
| `DELETE` | `/api/access-management/roles/{id}` | Delete role |
| `GET` | `/api/access-management/permissions` | List all permissions |

### 14.4 Assignments

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/access-management` | Create assignment. Body: `AssignmentInput` |
| `GET` | `/api/access-management` | Get assignment. Params: `entity-id`, `resource-id` |
| `PUT` | `/api/access-management` | Update assignment roles. Params: `entity-id`, `resource-id`. Body: `EntityRolesRequest` |
| `DELETE` | `/api/access-management` | Delete assignment. Params: `entity-id`, `resource-id` |
| `POST` | `/api/access-management/assignments` | Batch create assignments |
| `POST` | `/api/access-management/assignments/roles` | Add roles to assignment |
| `GET` | `/api/access-management/resource-assignments` | Get resource assignments. Params: `resource-ids` |

### 14.5 Base Roles

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/access-management/base-roles/{entity_id}` | Get entity base roles |
| `PUT` | `/api/access-management/base-roles/{entity_id}` | Replace base roles |
| `POST` | `/api/access-management/base-roles/{entity_id}` | Add base roles |
| `DELETE` | `/api/access-management/base-roles/{entity_id}` | Delete all base roles |
| `POST` | `/api/access-management/base-roles/{entity_id}/by-name` | Add roles by name |
| `POST` | `/api/access-management/base-roles/{entity_id}/by-name/unassign` | Remove roles by name |

### 14.6 Access Checks

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/access-management/has-access` | Check access. Params: `resource-id`, `resource-type`, `action` |
| `GET` | `/api/access-management/has-access-to-groups` | Check group access. Params: `group-ids`, `project-id` |
| `GET` | `/api/access-management/entities-for` | Get entities for resource. Params: `resource-id`, `resource-type`, `entity-types` |
| `GET` | `/api/access-management/entities-for/extended` | Extended entity info with pagination |
| `GET` | `/api/access-management/resources-for` | Resources for entity. Params: `entity-id`, `resource-types` |
| `GET` | `/api/access-management/get-resources` | Accessible resources. Params: `resource-types`, `action` |
| `GET` | `/api/access-management/effective-permissions/{entity_id}` | Effective permissions |
| `GET` | `/api/access-management/applications` | Applications with action. Params: `action`, `offset`, `limit`, `name`, `tags-keys`, `tags-values` |
| `GET` | `/api/access-management/projects` | Projects with action. Same params |

### 14.7 Clients

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/access-management/clients` | List OAuth clients |
| `GET` | `/api/access-management/clients-resources` | Clients with resources |

---

## 15. Queries API (SAST Queries)

**Base Path:** `/api/queries`

### 15.1 List Query Repositories

```
GET /api/queries
```

**Response:** List of `QueriesResponse` objects containing query definitions.

### 15.2 Get SAST Query Presets

```
GET /api/queries/presets
```

**Response:** List of `Preset` objects.

### 15.3 Get Query Descriptions

```
GET /api/queries/descriptions?ids={id1}&ids={id2}
```

**Response:** List of `QueryDescription` objects with sample code.

### 15.4 Get AST-to-SAST Query ID Mappings

```
GET /api/queries/mappings
```

**Response:** Array of `{ "astId": "...", "sastId": "..." }` mappings.

### 15.5 Get Preset for a Specific Scan

```
GET /api/queries/preset/{scan_id}
```

**Response:** Preset ID (integer).

### 15.6 Get Query Categories

```
GET /api/queries/categories-types
```

**Response:** List of `CategoryType` objects.

---

## 16. Scan Configuration API

**Base Path:** `/api/configuration`

### 16.1 Tenant-Level Configuration

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/configuration/tenant` | Get all tenant parameters |
| `PATCH` | `/api/configuration/tenant` | Update tenant parameters. Body: `List[ScanParameter]` |
| `DELETE` | `/api/configuration/tenant` | Delete tenant parameters. Query: `config-keys` |

### 16.2 Project-Level Configuration

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/configuration/project` | Get project parameters. Query: `project-id` |
| `PATCH` | `/api/configuration/project` | Update project parameters. Query: `project-id`. Body: `List[ScanParameter]` |
| `DELETE` | `/api/configuration/project` | Delete project parameters. Query: `project-id`, `config-keys` |

### 16.3 Scan-Level Configuration (Read-Only)

```
GET /api/configuration/scan?project-id={id}&scan-id={id}
```

Returns the effective configuration for a specific scan (merged tenant + project + scan-level).

### 16.4 SAST Default Configurations

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/configuration/sast/default-config` | List all. Query: `name`, `exact-match`, `limit`, `offset` |
| `POST` | `/api/configuration/sast/default-config` | Create config. Body: `DefaultConfig` |
| `GET` | `/api/configuration/sast/default-config/{id}` | Get by ID |
| `PUT` | `/api/configuration/sast/default-config/{id}` | Update config |
| `DELETE` | `/api/configuration/sast/default-config/{id}` | Delete config |

### 16.5 ScanParameter Schema

```json
{
  "key": "scan.config.sast.presetName",
  "name": "presetName",
  "category": "sast",
  "originLevel": "tenant",
  "value": "Checkmarx Default",
  "valueType": "String",
  "valueTypeParams": "",
  "allowOverride": true
}
```

**Common Configuration Keys:**

| Key | Description |
|-----|-------------|
| `scan.config.sast.presetName` | SAST scan preset |
| `scan.config.sast.incremental` | Incremental scanning |
| `scan.config.sast.languageMode` | Language detection mode |
| `scan.config.sast.filter` | File filter patterns |
| `scan.handler.git.repository` | Git repository URL |
| `scan.handler.git.branch` | Default branch |
| `scan.handler.git.token` | Git auth token |

---

## 17. Audit Trail API

**Base Path:** `/api/audit`

### 17.1 Get Audit Events

```
GET /api/audit
```

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `offset` | int | 0 | Items to skip |
| `limit` | int | 200 | Max items to return |
| `from` | string | | Start date (YYYY-MM-DD). Max 365 days in the past |
| `to` | string | | End date (YYYY-MM-DD). Must be >= `from` |

**Response:** `AuditEvents` object containing audit event records. For historical dates, returns downloadable links to daily JSON files.

---

## 18. SCA APIs

SCA (Software Composition Analysis) has both integrated endpoints under the main API and dedicated SCA-specific endpoints.

### 18.1 SCA Export Service

**Base Path:** `/api/sca/export`

#### Create SCA Export

```
POST /api/sca/export/requests
```

**Request Body:**

```json
{
  "ScanId": "scan-uuid",
  "FileFormat": "json",
  "ExportParameters": {
    "hideDevAndTestDependencies": false,
    "showOnlyEffectiveLicenses": false,
    "excludePackages": false,
    "excludeLicenses": false,
    "excludeVulnerabilities": false,
    "excludePolicies": false
  }
}
```

**Response:**

```json
{
  "exportId": "export-uuid"
}
```

#### Check Export Status

```
GET /api/sca/export/requests?exportId={export_id}
```

**Response includes:** `exportStatus` field (`"Completed"`, `"Failed"`, `"InProgress"`)

#### Download Export

```
GET /api/sca/export/requests/{export_id}/download
```

### 18.2 SCA Risk Management

**Base Path:** `/api/sca/risk-management`

#### Get Risk Scan Report

```
GET /api/sca/risk-management/risk-reports/{scan_id}/export?format={format}
```

**Formats:** `json`, `xml`, `pdf`, `csv`

**Also available via SCA-specific base URLs:**
```
GET https://api-sca.checkmarx.net/risk-management/risk-reports/{scan_id}/export?format={format}
```

### 18.3 SCA Management of Risk

**Base Path:** `/api/sca/management-of-risk`

Endpoints for managing risk policies, severity overrides, and package-level risk decisions.

### 18.4 SCA Package License Management

**Base Path:** `/api/sca/management-of-risk` (license-related sub-endpoints)

Manage package license policies, allowed/denied licenses, and license risk settings.

### 18.5 SCA Scans (Direct SCA API)

For standalone SCA operations via SCA-specific base URLs:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/scans` | Create SCA scan (via SCA base URL) |
| `GET` | `/api/scans/{id}` | Get SCA scan status |
| `POST` | `/api/scans/generate-upload-link` | Generate upload link |
| `PUT` | `{upload-link}` | Upload source |

### 18.6 SCA Projects (Direct SCA API)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/projects` | Create SCA project |
| `PUT` | `/api/projects/{id}` | Update SCA project |

---

## 19. Webhooks API

**Base Path:** `/api/webhooks`

### 19.1 Tenant-Level Webhooks

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/webhooks/tenant` | Create tenant webhook. Body: `WebHookInput` |
| `GET` | `/api/webhooks/tenant` | List tenant webhooks. Params: `offset`, `limit` |

### 19.2 Project-Level Webhooks

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/webhooks/projects/{project_id}` | Create project webhook |
| `GET` | `/api/webhooks/projects/{project_id}` | List project webhooks |

### 19.3 Webhook Management

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/webhooks/{webhook_id}` | Get webhook by ID |
| `PATCH` | `/api/webhooks/{webhook_id}` | Update webhook |
| `DELETE` | `/api/webhooks/{webhook_id}` | Delete webhook |

---

## 20. Common Patterns

### Pagination

All list endpoints support pagination with `offset` and `limit` parameters:
- Default `offset`: 0
- Default `limit`: 20 (varies per endpoint)
- Use `offset=0&limit=0` to get all results (where supported)
- Responses include `totalCount` field

### Sorting

Sort parameters use the pattern `[+-]fieldName`:
- `+` prefix = descending order
- `-` prefix = ascending order
- Example: `sort=+severity&sort=-created`

### Error Responses

Standard HTTP error codes:

| Code | Description |
|------|-------------|
| 400 | Bad Request - Invalid parameters |
| 401 | Unauthorized - Invalid/expired token |
| 403 | Forbidden - Insufficient permissions |
| 404 | Not Found - Resource doesn't exist |
| 409 | Conflict - Resource already exists |
| 429 | Too Many Requests - Rate limited |
| 500 | Internal Server Error |

Error response body:

```json
{
  "code": 400,
  "message": "Invalid request body",
  "type": "bad_request"
}
```

### Tags

Tags are key-value pairs used across Projects, Applications, and Scans:

```json
{
  "tags": {
    "key1": "value1",
    "key2": "value2"
  }
}
```

### Available Scanner/Engine Types

| Engine | Config Type | Description |
|--------|-------------|-------------|
| `sast` | `sast` | Static Application Security Testing |
| `sca` | `sca` | Software Composition Analysis |
| `kics` | `kics` | Infrastructure as Code Security |
| `apisec` | `apisec` | API Security |
| `containers` | - | Container Security |

### Complete Scan Workflow (End-to-End)

```bash
# 1. Authenticate
TOKEN=$(curl -s -X POST \
  "https://iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token" \
  -d "grant_type=client_credentials&client_id={id}&client_secret={secret}" \
  | jq -r '.access_token')

# 2. Create project (if needed)
PROJECT_ID=$(curl -s -X POST "https://ast.checkmarx.net/api/projects" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-project", "groups": []}' \
  | jq -r '.id')

# 3. Get upload URL
UPLOAD_URL=$(curl -s -X POST "https://ast.checkmarx.net/api/uploads" \
  -H "Authorization: Bearer $TOKEN" \
  | jq -r '.url')

# 4. Upload source code
curl -X PUT "$UPLOAD_URL" \
  -H "Content-Type: application/zip" \
  --data-binary @source.zip

# 5. Start scan
SCAN_ID=$(curl -s -X POST "https://ast.checkmarx.net/api/scans" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"upload\",
    \"handler\": {\"url\": \"$UPLOAD_URL\"},
    \"project\": {\"id\": \"$PROJECT_ID\"},
    \"configs\": [
      {\"type\": \"sast\", \"value\": {\"presetName\": \"Checkmarx Default\"}},
      {\"type\": \"sca\"},
      {\"type\": \"kics\"}
    ]
  }" | jq -r '.id')

# 6. Poll scan status
while true; do
  STATUS=$(curl -s "https://ast.checkmarx.net/api/scans/$SCAN_ID" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.status')
  echo "Scan status: $STATUS"
  [ "$STATUS" = "Completed" ] || [ "$STATUS" = "Failed" ] && break
  sleep 10
done

# 7. Get results
curl -s "https://ast.checkmarx.net/api/results?scan-id=$SCAN_ID&limit=100" \
  -H "Authorization: Bearer $TOKEN" | jq .

# 8. Get results summary
curl -s "https://ast.checkmarx.net/api/scan-summary?scan-ids=$SCAN_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .

# 9. Generate PDF report
REPORT_ID=$(curl -s -X POST "https://ast.checkmarx.net/api/reports" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"reportName\": \"scan-report\",
    \"reportType\": \"cli\",
    \"fileFormat\": \"pdf\",
    \"data\": {
      \"scanId\": \"$SCAN_ID\",
      \"projectId\": \"$PROJECT_ID\",
      \"sections\": [\"ScanSummary\", \"ExecutiveSummary\", \"ScanResults\"],
      \"scanners\": [\"SAST\", \"SCA\", \"KICS\"]
    }
  }" | jq -r '.reportId')

# 10. Wait and download report
sleep 15
curl -o report.pdf "https://ast.checkmarx.net/api/reports/$REPORT_ID/download" \
  -H "Authorization: Bearer $TOKEN"
```

---

## Sources

- [Checkmarx One API Documentation](https://docs.checkmarx.com/en/34965-68772-checkmarx-one-api-documentation.html)
- [Checkmarx One API Endpoints](https://docs.checkmarx.com/en/34965-135033-checkmarx-one-api-endpoints.html)
- [Applications Service REST API (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/branches/main/szojm2v0j748d-applications-rest-api)
- [Reports Service REST API (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/branches/main/6e28f72109c9c-reports-service-rest-api)
- [SAST Results Service REST API (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/branches/main/9rbo0th5znj5e-sast-results-service-rest-api)
- [SAST Results Summary Service REST API (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/branches/main/gzxhtrhnfff35-sast-results-summary-service-rest-api)
- [Scan Configuration Service (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/branches/main/cs61sszap44td-scan-configuration-service)
- [Audit Trail Service REST API (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/branches/main/rpjl2gxdvxx0b-audit-trail-service-rest-api)
- [Retrieve List of Scans (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/cf4545476ab54-retrieve-list-of-scans)
- [Download a Report (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/623847b6ec200-download-a-report)
- [Create a Customized Report (Stoplight)](https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/branches/main/51flzmrawidq4-create-a-customized-report)
- [Checkmarx SCA REST API Documentation](https://docs.checkmarx.com/en/34965-19221-checkmarx-sca--rest--api-documentation.html)
- [Checkmarx Python SDK (GitHub)](https://github.com/checkmarx-ts/checkmarx-python-sdk)
- [Generating a Refresh Token / API Key](https://docs.checkmarx.com/en/34965-68775-generating-a-refresh-token--api-key-.html)
- [Working with Scan Result Reports](https://docs.checkmarx.com/en/34965-46589-working-with-scan-result-reports.html)
- [Checkmarx One Authentication API](https://checkmarx.com/resource/documents/en/34965-68774-checkmarx-one-authentication-api.html)
- [SAST Query Language APIs](https://docs.checkmarx.com/en/34965-270431-sast-query-language-apis.html)
- [SCA Export Service](https://docs.checkmarx.com/en/34965-145615-checkmarx-sca--rest--api---export-service.html)
- [SCA GET Scan Reports and SBOMs](https://docs.checkmarx.com/en/34965-95097-checkmarx-sca--rest--api---get-scan-reports-and-sboms.html)
