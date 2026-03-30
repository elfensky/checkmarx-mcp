# Report Output Directory Safety

**Date:** 2026-03-30
**Status:** Approved

## Problem

Three scripts write report files to disk and all default to writing inside (or relative to) the repository directory. This creates a risk of accidentally committing sensitive scan data (PII, vulnerability details) to git. The `.gitignore` only partially covers output files (`report_*.csv`), missing `report-data/` and `*.pdf`.

## Decision

Reports must never be saved inside any repository. All scripts that write files will default to a user-local directory outside the repo, with a consistent override flag.

## Default Output Directory

A shared function `cx_output_dir` in `lib.sh` implements a two-step fallback:

1. If `~/Downloads` exists -> `~/Downloads/checkmarx-reports/`
2. Otherwise -> `~/checkmarx-reports/`

The function creates the directory (`mkdir -p`) on first use and prints the path to stdout.

### Cross-platform rationale

| Platform | `~/Downloads` exists? | Result |
|----------|----------------------|--------|
| macOS | Always | `~/Downloads/checkmarx-reports/` |
| Windows (Git Bash) | Always | `~/Downloads/checkmarx-reports/` |
| Desktop Linux | Usually | `~/Downloads/checkmarx-reports/` |
| Headless Linux / containers | No | `~/checkmarx-reports/` |

This avoids the complexity of `xdg-user-dir` parsing while covering all common environments.

## Script Changes

### `lib.sh` -- new function

```
cx_output_dir [SUBDIR]
```

- Returns the base output directory, optionally with a subdirectory appended
- Creates the directory if it doesn't exist
- Prints the resolved path to stdout

### `checkmarx.report.sh`

| Aspect | Before | After |
|--------|--------|-------|
| Default output | `./report_<APP>_<DATE>.csv` | `$(cx_output_dir)/report_<APP>_<DATE>.csv` |
| Override | None | `--output-dir DIR` |

### `utils/checkmarx.generate-report-data.sh`

| Aspect | Before | After |
|--------|--------|-------|
| Default output | `./report-data/YYYY-MM-DD/` | `$(cx_output_dir YYYY-MM-DD)/` |
| Override | `--output-dir DIR` (already exists) | No change to flag behavior |

### `utils/checkmarx.get-report.sh`

| Aspect | Before | After |
|--------|--------|-------|
| Default output | `./report-<SCAN_ID>.pdf` | `$(cx_output_dir)/report-<SCAN_ID>.<FORMAT>` |
| Override | `--output FILE` (already exists, full path) | No change to flag behavior |

All scripts log the final output path to stderr so the user knows where files were written.

## Safety Nets

### `.gitignore` additions

```
report-data/
*.pdf
report-*.csv
```

The existing `report_*.csv` entry stays. The new `report-*.csv` catches hyphenated naming. `*.pdf` is broad but appropriate -- no PDF source files exist in this repo.

### `CLAUDE.md` addition

A new "Report Output" section documents:
- The convention that reports are never saved in the repo
- The default output directory and fallback chain
- The `--output-dir` override pattern

## What Stays the Same

- **Token caching** in `$TMPDIR` -- not report data, no change
- **MCP server** -- returns JSON in-memory, never writes files to disk
- **All other utility scripts** -- output JSON to stdout, no file writes
- **`reports/` directory** -- contains documentation only (README.md, powerbi-setup.md), not generated output

## Testing

- Run each of the 3 scripts and verify output lands in the expected directory
- Test with `--output-dir /tmp/test` override
- Test on a system without `~/Downloads` to verify fallback to `~/checkmarx-reports/`
- Verify `.gitignore` patterns catch all generated file names
