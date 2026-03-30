# Trend Metrics Tooling — Design Spec

## Problem

Managers need trend-based security reports at monthly, quarterly, and yearly granularity. They ask questions like "are HIGH findings going up or down?" and "are we fixing faster than we're introducing?" These requests cover individual projects, entire applications, or the whole tenant.

Currently, assembling a trend requires manually running multiple scripts, picking scan IDs by hand, and doing the math. There is no automated way to produce a time-series view of security posture.

## Decision Record

Three approaches were evaluated via multi-AI adversarial debate (Claude Opus, GPT-5.4, Gemini 2.5, Claude Sonnet):

- **A) Two standalone scripts** — one per metric, each with its own MCP tool
- **B) One unified trend script** — single script with `--metric` flag
- **C) Pipeline building blocks** — a `scan-timeline.sh` primitive piped into existing tools

**Winner: A+C hybrid.** Extract the timeline primitive (C) to avoid duplication, but wrap each metric in a purpose-built script (A) for stable MCP-consumable output. B was rejected as a "god-script" that violates the repo's one-script-per-concern convention.

An additional design decision was made to use `net_change` (scan-summary diffs) uniformly across all engines rather than relying on the SAST-only `sast-compare` endpoint. This ensures consistent output structure regardless of engine type.

## Architecture

```
lib.sh
  cx_resolve_project_ids()   ← scope → [project IDs]
  cx_date_range()            ← period + range → [{start, end}, ...]

scan-timeline.sh             ← scope + period + range → [{period, scanId, projectId, createdAt}]
  uses: cx_resolve_project_ids, cx_date_range, list-scans (via cx_get)

trend-severity.sh            ← scope + period + range + engines → [{period, sast: {...}, sca: {...}, total: {...}}]
  uses: scan-timeline.sh, scan-summary (via cx_get)

trend-new-vs-fixed.sh        ← scope + period + range + engines → [{period, sast: {...}, sca: {...}, total: {...}}]
  uses: scan-timeline.sh, scan-summary (via cx_get)
```

Both trend scripts share the same data pipeline: `scan-timeline` for scan IDs, `scan-summary` for counts. They differ only in output shape (absolute counts vs period-over-period deltas).

**Engine name mapping** (user-facing flag → API counter key):
- `sast` → `sastCounters`
- `sca` → `scaCounters`
- `kics` → `kicsCounters`
- `containers` → `scaContainersCounters`
- `apisec` → `apiSecCounters`

## Components

### 1. `lib.sh` additions

#### `cx_resolve_project_ids`

Resolves scope flags to an array of project IDs.

- `--project-id` → single-element array
- `--application-id` → fetches application, extracts `projectIds[]`
- Neither → fetches all projects, extracts IDs
- Both → error: "Cannot specify both --project-id and --application-id"

No API calls when `--project-id` is given. Uses existing `cx_get` and `cx_paginate` for the other two cases.

#### `cx_date_range`

Pure function (no API calls). Given `--period` and `--range`, outputs a JSON array of time buckets:

```json
[
  {"period": "2026-03", "start": "2026-03-01T00:00:00Z", "end": "2026-03-31T23:59:59Z"},
  {"period": "2026-02", "start": "2026-02-01T00:00:00Z", "end": "2026-02-28T23:59:59Z"}
]
```

Period formats:
- `monthly` → `YYYY-MM`
- `quarterly` → `YYYY-Q1` / `YYYY-Q2` / `YYYY-Q3` / `YYYY-Q4`
- `yearly` → `YYYY`

Ordered most-recent-first (consistent with how scans are returned).

### 2. `utils/checkmarx.scan-timeline.sh`

The reusable primitive. Returns one representative scan per project per time period.

**Flags:**
- `--project-id ID` — single project scope
- `--application-id ID` — application scope
- (neither) — tenant scope
- `--period monthly|quarterly|yearly` — time granularity (required)
- `--range N` — how many periods back, default: 6
- `--branch B` — optional branch filter
- `--engines E` — optional comma-separated engine filter (for future use)
- `-v, --verbose`

**Scope validation:** errors if both `--project-id` and `--application-id` are provided.

**Selection policy:** For each project + period bucket, pick the latest Completed scan whose `createdAt` falls within the bucket's date range.

**Output:**
```json
[
  {"period": "2026-03", "scanId": "abc-123", "projectId": "p1", "projectName": "my-proj", "createdAt": "2026-03-27T21:07:04Z"},
  {"period": "2026-02", "scanId": "def-456", "projectId": "p1", "projectName": "my-proj", "createdAt": "2026-02-15T10:30:00Z"},
  {"period": "2026-01", "scanId": null, "projectId": "p1", "projectName": "my-proj", "createdAt": null}
]
```

`null` scanId/createdAt for periods with no completed scan.

For multi-project scopes (app/tenant), returns entries for every project in every period. Downstream scripts aggregate across projects.

**Implementation approach:**
1. `cx_resolve_project_ids` to get project list
2. `cx_date_range` to get period buckets
3. For each project: `cx_get` list-scans with `project-id`, `statuses=Completed`, sorted ascending by `created_at`
4. Walk the scan list and assign each to its period bucket (latest wins)
5. Output the merged JSON array

**No MCP tool.** This is an internal building block, not an end-user report.

### 3. `utils/checkmarx.trend-severity.sh` + MCP tool `trend_severity`

Produces severity counts per engine per time period.

**Flags (bash):**
- `--project-id ID` / `--application-id ID` / neither — scope
- `--period monthly|quarterly|yearly` — required
- `--range N` — default: 6
- `--engines sast,sca,kics,containers,apisec` — comma-separated, default: all

**MCP tool params:** `project_id?`, `application_id?`, `period`, `range?`, `engines?`

**Output:**
```json
[
  {
    "period": "2026-03",
    "sast": {"critical": 5, "high": 42, "medium": 120, "low": 300, "info": 15, "total": 482},
    "sca": {"critical": 1, "high": 12, "medium": 30, "low": 50, "info": 0, "total": 93},
    "kics": {"critical": 0, "high": 3, "medium": 15, "low": 8, "info": 2, "total": 28},
    "containers": {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0, "total": 0},
    "apisec": {"critical": 0, "high": 1, "medium": 2, "low": 0, "info": 0, "total": 3},
    "total": {"critical": 6, "high": 58, "medium": 167, "low": 358, "info": 17, "total": 606}
  },
  {
    "period": "2026-02",
    "sast": {"critical": 8, "high": 55, "medium": 130, "low": 310, "info": 18, "total": 521},
    ...
  }
]
```

When `--engines sast` is specified, only `sast` and `total` keys appear.

Periods with no scan get `null` values for all engines.

**Implementation:**
1. Call `scan-timeline.sh` with scope + period + range flags
2. Collect all non-null scan IDs
3. Batch call `scan-summary` with all scan IDs (the API accepts multiple `scan-ids` in one request)
4. For each period: extract severity counters from the matching scan's summary, filtered to requested engines
5. For multi-project scopes: sum severity counts across all projects within each period
6. Output the assembled JSON array

### 4. `utils/checkmarx.trend-new-vs-fixed.sh` + MCP tool `trend_new_vs_fixed`

Produces period-over-period net change in severity counts per engine.

**Flags:** Same as `trend-severity.sh`.

**MCP tool params:** Same as `trend_severity`.

**Output:**
```json
[
  {
    "period": "2026-03",
    "sast": {"critical": -2, "high": -5, "medium": 3, "low": -1, "info": 0, "net_change": -5},
    "sca": {"critical": 0, "high": -3, "medium": 1, "low": 0, "info": 0, "net_change": -2},
    "kics": {"critical": 0, "high": 0, "medium": -4, "low": 2, "info": 0, "net_change": -2},
    "containers": {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0, "net_change": 0},
    "apisec": {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0, "net_change": 0},
    "total": {"critical": -2, "high": -8, "medium": 0, "low": 1, "info": 0, "net_change": -9}
  },
  {
    "period": "2026-02",
    ...
  },
  {
    "period": "2025-10",
    "sast": null, "sca": null, "total": null
  }
]
```

The oldest period in the range has `null` values (no prior period to diff against). Negative `net_change` = improvement (fewer findings). Positive = regression.

**Implementation:**
1. Call `scan-timeline.sh` with scope + period + range flags
2. Batch call `scan-summary` for all non-null scan IDs
3. For each consecutive period pair (newer, older): subtract older severity counts from newer
4. For multi-project scopes: sum deltas across all projects within each period
5. Output the assembled JSON array

## Files to create or modify

| Action | File | What |
|--------|------|------|
| Modify | `lib.sh` | Add `cx_resolve_project_ids`, `cx_date_range` |
| Create | `utils/checkmarx.scan-timeline.sh` | Timeline primitive |
| Create | `utils/checkmarx.trend-severity.sh` | Severity trend script |
| Create | `utils/checkmarx.trend-new-vs-fixed.sh` | New vs fixed trend script |
| Modify | `mcp-server/src/client.ts` | Add `trendSeverity()`, `trendNewVsFixed()` methods |
| Modify | `mcp-server/src/index.ts` | Register `trend_severity`, `trend_new_vs_fixed` tools |
| Update | `CLAUDE.md` | Document new scripts and tools |
| Update | `README.md` | Add trend metrics section |

## Output Format

All trend scripts output **raw JSON** to stdout. They do not produce visual charts, graphs, or Excel files. The JSON is structured data intended to be consumed by:

- **Claude (MCP)** — the `trend_severity` and `trend_new_vs_fixed` tools return JSON that Claude formats conversationally (tables, summaries, comparisons) based on what the manager asks for
- **CSV (Excel/Google Sheets)** — pipe output through `jq` (to select fields) then `cx_format_csv` to produce spreadsheet-ready files. Managers build their own pivot tables and charts in Excel
- **Markdown (Slack/Confluence)** — pipe through `cx_format_table` for copy-paste into messaging and wikis
- **Dashboards (Grafana/Power BI)** — consume the JSON directly or convert to CSV for import

The formatting layer is deliberately external to the scripts — separating data production from presentation keeps the scripts composable and the output format flexible.

## Verification

1. **scan-timeline.sh:** Run with `--project-id` + `--period monthly --range 3 -v`. Verify it returns one scan per month, most-recent-first, with correct period labels. Test with `--application-id` to verify multi-project expansion. Test with both flags to verify error.

2. **trend-severity.sh:** Run for a known project. Compare output against manually running `scan-summary` for the same scans. Verify severity counts match. Test `--engines sast` to verify filtering.

3. **trend-new-vs-fixed.sh:** Run for a known project. Verify that `net_change` values equal the difference in total counts between consecutive periods from `trend-severity.sh` output.

4. **MCP tools:** Build (`cd mcp-server && npm run build`). Test via Claude: "Show me the severity trend for project X over the last 6 months."

5. **Formatting:** Pipe trend output through `cx_format_csv` and `cx_format_table` to verify clean tabular output.

6. **Edge cases:** Project with no scans in some months (expect nulls). Application with mixed scan cadences across projects. Tenant-wide with hundreds of projects (verify pagination works).
