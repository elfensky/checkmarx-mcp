# Report Output Directory Safety — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure report files are never written inside the repository by defaulting output to a user-local directory (`~/Downloads/checkmarx-reports/` or `~/checkmarx-reports/`).

**Architecture:** A single shared function `cx_output_dir` in `lib.sh` implements the cross-platform fallback chain. Three report-writing scripts are updated to call it for their default output path. Safety nets are added to `.gitignore` and conventions documented in `CLAUDE.md`.

**Tech Stack:** Bash, jq (existing dependencies only)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib.sh:501+` | Modify | Add `cx_output_dir` function |
| `checkmarx.report.sh:14-19` | Modify | Parse `--output-dir`, use `cx_output_dir` for default |
| `utils/checkmarx.generate-report-data.sh:82-84` | Modify | Replace hardcoded default with `cx_output_dir` |
| `utils/checkmarx.get-report.sh:88-91` | Modify | Use `cx_output_dir` for default output path |
| `.gitignore` | Modify | Add `report-data/`, `*.pdf`, `report-*.csv` |
| `CLAUDE.md:240+` | Modify | Add "Report Output" section documenting the convention |

---

### Task 1: Add `cx_output_dir` to `lib.sh`

**Files:**
- Modify: `lib.sh:500` (append after `cx_format_table`)

- [ ] **Step 1: Add the `cx_output_dir` function**

Append to the end of `lib.sh`, after the `cx_format_table` function (after line 500):

```bash
# ---------------------------------------------------------------------------
# cx_output_dir [SUBDIR]
# Returns an output directory path outside any repository.
# Fallback chain:
#   1. ~/Downloads/checkmarx-reports/  (if ~/Downloads exists)
#   2. ~/checkmarx-reports/            (otherwise)
# If SUBDIR is provided, it is appended (e.g., cx_output_dir "2026-03-30").
# Creates the directory if it doesn't exist. Prints the path to stdout.
# ---------------------------------------------------------------------------
cx_output_dir() {
  local base
  if [ -d "${HOME}/Downloads" ]; then
    base="${HOME}/Downloads/checkmarx-reports"
  else
    base="${HOME}/checkmarx-reports"
  fi

  if [ -n "${1:-}" ]; then
    base="${base}/$1"
  fi

  mkdir -p "${base}"
  echo "${base}"
}
```

- [ ] **Step 2: Verify the function works**

Run from the repo root:

```bash
source ./lib.sh && cx_output_dir
```

Expected: prints a path like `/Users/<you>/Downloads/checkmarx-reports` (macOS/desktop Linux) or `/Users/<you>/checkmarx-reports` (headless). The directory should now exist on disk.

Then test with a subdirectory argument:

```bash
source ./lib.sh && cx_output_dir "2026-03-30"
```

Expected: prints `/Users/<you>/Downloads/checkmarx-reports/2026-03-30` and creates it.

Clean up test directories:

```bash
rmdir ~/Downloads/checkmarx-reports/2026-03-30 2>/dev/null; rmdir ~/Downloads/checkmarx-reports 2>/dev/null || true
```

- [ ] **Step 3: Commit**

```bash
git add lib.sh
git commit -m "feat: add cx_output_dir function to lib.sh

Cross-platform output directory resolver. Falls back from
~/Downloads/checkmarx-reports/ to ~/checkmarx-reports/ when
~/Downloads doesn't exist (headless Linux, containers)."
```

---

### Task 2: Update `checkmarx.report.sh` to use `cx_output_dir`

**Files:**
- Modify: `checkmarx.report.sh:14-19,37-38,153-155,182`

This script currently writes `report_<APP>_<DATE>.csv` to the current working directory. It also does its own inline auth rather than using `cx_authenticate`, but that's out of scope — we only change the output path.

- [ ] **Step 1: Add `--output-dir` flag parsing**

The script currently restores positional args on line 14 and sets config on lines 17-19. Replace lines 14-19 with:

```bash
set -- "${CX_POSITIONAL_ARGS[@]+"${CX_POSITIONAL_ARGS[@]}"}"

# --- Parse script-specific flags ---
OUTPUT_DIR=""
REMAINING_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *)            REMAINING_ARGS+=("$1"); shift ;;
  esac
done
set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"

# --- Configuration ---
APP_NAME="${1:-OneApp}"
REPORT_DATE="$(date +%Y-%m-%d)"
if [ -z "${OUTPUT_DIR}" ]; then
  OUTPUT_DIR="$(cx_output_dir)"
fi
mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/report_${APP_NAME}_${REPORT_DATE}.csv"
```

- [ ] **Step 2: Update the verbose log**

Replace line 38 (`cx_vlog "OUTPUT_FILE=${OUTPUT_FILE}"`) — no change needed, it already references `OUTPUT_FILE` which now includes the full path. Verify the log on line 37 still reads correctly:

```bash
cx_vlog "OUTPUT_FILE=${OUTPUT_FILE}"
```

This is correct as-is.

- [ ] **Step 3: Update the final log message**

Line 182 currently says:
```bash
cx_log "Done! Report saved to ${OUTPUT_FILE} (${TOTAL_FETCHED} projects)"
```

This already uses `${OUTPUT_FILE}` which now contains the full path. No change needed — the user will see the absolute path in output.

- [ ] **Step 4: Verify the script parses flags correctly**

Dry-run test (won't actually call the API, just verifies parsing doesn't error):

```bash
bash -n checkmarx.report.sh
```

Expected: no output (syntax OK).

- [ ] **Step 5: Commit**

```bash
git add checkmarx.report.sh
git commit -m "feat: checkmarx.report.sh outputs to cx_output_dir by default

Adds --output-dir flag. Default changed from CWD to
~/Downloads/checkmarx-reports/ (or ~/checkmarx-reports/)."
```

---

### Task 3: Update `utils/checkmarx.generate-report-data.sh` to use `cx_output_dir`

**Files:**
- Modify: `utils/checkmarx.generate-report-data.sh:82-84`

This script already has `--output-dir` flag parsing (line 76). Only the default needs to change.

- [ ] **Step 1: Replace the hardcoded default**

Replace lines 82-84:

```bash
# --- Defaults ---
if [ -z "${OUTPUT_DIR}" ]; then
  OUTPUT_DIR="report-data/$(date +%Y-%m-%d)"
fi
```

With:

```bash
# --- Defaults ---
if [ -z "${OUTPUT_DIR}" ]; then
  OUTPUT_DIR="$(cx_output_dir "$(date +%Y-%m-%d)")"
fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n utils/checkmarx.generate-report-data.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Commit**

```bash
git add utils/checkmarx.generate-report-data.sh
git commit -m "feat: generate-report-data.sh outputs to cx_output_dir by default

Default changed from ./report-data/YYYY-MM-DD/ to
~/Downloads/checkmarx-reports/YYYY-MM-DD/. --output-dir override
still works as before."
```

---

### Task 4: Update `utils/checkmarx.get-report.sh` to use `cx_output_dir`

**Files:**
- Modify: `utils/checkmarx.get-report.sh:88-91`

This script already has `--output` flag for full file path override. Only the default needs to change.

- [ ] **Step 1: Replace the default output path**

Replace lines 88-91:

```bash
# --- Default output filename (first 8 chars of scan UUID for brevity) ---
if [ -z "${OUTPUT}" ]; then
  OUTPUT="report-${SCAN_ID:0:8}.${FORMAT}"
fi
```

With:

```bash
# --- Default output filename (first 8 chars of scan UUID for brevity) ---
if [ -z "${OUTPUT}" ]; then
  OUTPUT="$(cx_output_dir)/report-${SCAN_ID:0:8}.${FORMAT}"
fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n utils/checkmarx.get-report.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Commit**

```bash
git add utils/checkmarx.get-report.sh
git commit -m "feat: get-report.sh outputs to cx_output_dir by default

Default changed from CWD to ~/Downloads/checkmarx-reports/.
--output flag still works for full path override."
```

---

### Task 5: Harden `.gitignore`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add safety-net patterns**

The current `.gitignore` is:

```
.env
report_*.csv
report-data
```

Replace with:

```
.env
report_*.csv
report-*.csv
report-data/
*.pdf
```

This adds:
- `report-*.csv` — catches hyphenated naming from `get-report.sh` CSV output
- `report-data/` — trailing slash makes the intent clearer (directory)
- `*.pdf` — no PDF source files exist in this repo; catches downloaded reports

- [ ] **Step 2: Verify patterns work**

```bash
echo "test" > report-test.csv && git check-ignore report-test.csv && rm report-test.csv
echo "test" > report_test.csv && git check-ignore report_test.csv && rm report_test.csv
echo "test" > test.pdf && git check-ignore test.pdf && rm test.pdf
mkdir -p report-data && touch report-data/test && git check-ignore report-data/test && rm -rf report-data
```

Expected: each `git check-ignore` command prints the filename (meaning it's ignored).

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: harden .gitignore for report output files

Add report-*.csv, *.pdf patterns and clarify report-data/ as
directory. Safety net in case reports are accidentally generated
inside the repo."
```

---

### Task 6: Document the convention in `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (insert after the "Safe Execution Conventions" section, before "Adding New Scripts")

- [ ] **Step 1: Add the "Report Output" section**

Insert after line 279 (end of "Write scripts" section) and before line 281 ("## Adding New Scripts"):

```markdown
## Report Output

**Reports must never be saved inside any repository.** Scripts that write files to disk default to a user-local directory:

1. `~/Downloads/checkmarx-reports/` — if `~/Downloads` exists (macOS, Windows Git Bash, desktop Linux)
2. `~/checkmarx-reports/` — fallback for headless Linux and containers

The shared function `cx_output_dir [SUBDIR]` in `lib.sh` implements this fallback, creates the directory, and prints the resolved path. All report-writing scripts use it for their default.

### Override

All three report scripts accept an explicit output path:

```bash
# checkmarx.report.sh
./checkmarx.report.sh --output-dir /tmp/reports "MyApp"

# checkmarx.generate-report-data.sh
./utils/checkmarx.generate-report-data.sh --output-dir /tmp/reports --project-id "uuid"

# checkmarx.get-report.sh (full file path, not directory)
./utils/checkmarx.get-report.sh --scan-id "uuid" --project-id "uuid" --output /tmp/my-report.pdf
```

When adding new scripts that write files, always use `cx_output_dir` for the default path. Never write output files relative to `${SCRIPT_DIR}` or the current working directory.
```

- [ ] **Step 2: Update the `lib.sh` documentation in CLAUDE.md**

In the "Shared Library (`lib.sh`)" section, in the "Extended" subsection (around line 222), add a bullet for `cx_output_dir` after the `cx_base_urls` bullet:

```markdown
- **`cx_output_dir [SUBDIR]`** — Returns a report output directory outside the repo (`~/Downloads/checkmarx-reports/` or `~/checkmarx-reports/`). Creates it if needed. Used as the default by all report-writing scripts.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document report output directory convention in CLAUDE.md

Add Report Output section with cross-platform fallback chain,
override examples, and guidance for new scripts. Add cx_output_dir
to the lib.sh function reference."
```

---

## Summary

| Task | Files | What changes |
|------|-------|-------------|
| 1 | `lib.sh` | Add `cx_output_dir` function |
| 2 | `checkmarx.report.sh` | Add `--output-dir` flag, use `cx_output_dir` default |
| 3 | `utils/checkmarx.generate-report-data.sh` | Replace hardcoded default with `cx_output_dir` |
| 4 | `utils/checkmarx.get-report.sh` | Use `cx_output_dir` for default output |
| 5 | `.gitignore` | Add `report-*.csv`, `*.pdf`, clarify `report-data/` |
| 6 | `CLAUDE.md` | Document convention, override patterns, `cx_output_dir` |

Tasks 1 must complete first (other scripts depend on `cx_output_dir`). Tasks 2-4 are independent of each other. Task 5 is independent. Task 6 should come last (documents the final state).
