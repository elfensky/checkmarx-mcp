# Visualization & Chart Generation — Decision Record

**Date:** 2026-03-30
**Status:** Decided — Power BI CSV Data Pack + template
**Context:** After building trend metrics tooling, evaluated how to visualize the data for manager-facing reports.

## Decision

Build a **CSV data pack generator** and pair it with a **Power BI template (.pbit)**. Power BI is the org's standard reporting tool. Managers receive shareable Power BI links rather than static chart attachments.

## What We're Building

1. **`checkmarx.generate-report-data.sh`** — orchestrator script that calls existing trend scripts and outputs structured CSVs for all 20 data views (5 engines x 4 granularities) to `report-data/YYYY-MM-DD/`
2. **Power BI template (`.pbit`)** — pre-configured charts (severity trend lines, net-change bars, engine comparison) that consume the CSV directory
3. **MCP tool (`generate_report_data`)** — so Claude can produce the data pack on demand

## Delivery Model

- **Slack/email:** Share a Power BI link (not static charts)
- **Slide decks:** Export charts from Power BI into PowerPoint (Power BI has native PPT export)
- **Ad-hoc questions:** Claude answers via MCP tools, formats conversationally

## Alternatives Evaluated (Multi-AI Debate)

Three approaches were debated adversarially by GPT-5.4, Gemini 2.5, and Claude Sonnet:

### A) Power BI CSV Data Pack (chosen)
- **Pros:** Aligns with org standard, CSV is portable, Power BI handles all visualization, template encodes semantic modeling (measures, slicers, drill-down)
- **Cons:** `.pbit` maintenance burden, requires Power BI Desktop (Windows) to edit template
- **Advocate:** Codex (GPT-5.4)

### B) Self-contained HTML + Chart.js
- **Pros:** Universally portable (email, Slack, any OS), zero infrastructure, trivial implementation, version-controlled templates
- **Cons:** Becomes a parallel BI product if scope creeps, adds web technology dependency to bash-only repo
- **Advocate:** Gemini 2.5
- **Why rejected:** Power BI links solve the Slack/email delivery problem. Building a second visualization system when the org already has one is wasteful.

### C) Do nothing — current JSON/CSV pipeline is enough
- **Pros:** Zero maintenance, YAGNI, the orchestrator is trivial glue code
- **Cons:** Manual CSV-to-chart friction is real for recurring reports
- **Advocate:** Claude Sonnet
- **Why rejected:** The recurring monthly/quarterly report cadence justifies automating the data preparation step, even if the visualization is handled by Power BI.

## Key Insight from Debate

Gemini's strongest argument — "you can't attach a Power BI dashboard to Slack" — was addressed by the user's note that Power BI links are the standard sharing mechanism in the org. The portability concern doesn't apply when the org has standardized on a tool with its own sharing model.

Sonnet's YAGNI argument is partially valid: the orchestrator script is indeed trivial glue. But standardizing the CSV output schema and having a single command to produce all 20 data views has value beyond the script's complexity — it creates a stable contract for the Power BI template.

## Risk: Template Maintenance

The `.pbit` file encodes column names, data types, and visual layout. Schema changes in the trend scripts can break the template. Mitigations:
- Keep the CSV schema stable (treat it as a public API)
- Document the schema in this spec
- If the template breaks, the CSVs are still independently useful in Excel

## CSV Schema (contract)

Each CSV file follows this structure:

**Severity trend (`severity-{engine}-{period}.csv`):**
```
period,critical,high,medium,low,info,total
2026-03,5,42,120,300,15,482
2026-02,8,55,130,310,18,521
```

**New-vs-fixed (`new-vs-fixed-{engine}-{period}.csv`):**
```
period,critical,high,medium,low,info,net_change
2026-03,-2,-5,3,-1,0,-5
2026-02,1,3,-2,0,1,3
```

Engine values: `sast`, `sca`, `kics`, `containers`, `apisec`, `total`
Period values: `monthly`, `quarterly`, `yearly`, `weekly`
