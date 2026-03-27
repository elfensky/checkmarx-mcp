# Checkmarx One CLI - `scan` Command Reference

Comprehensive reference for the `cx scan` command and all its subcommands, flags, and options.

**Sources:**
- [Official scan command docs](https://docs.checkmarx.com/en/34965-68643-scan.html)
- [Running Scans via the CLI](https://docs.checkmarx.com/en/34965-350124-running-scans-via-the-cli.html)
- [Running Scans from the CLI](https://docs.checkmarx.com/en/34965-8152-running-scans-from-the-cli.html)
- [GitHub: Checkmarx/ast-cli](https://github.com/Checkmarx/ast-cli) (source code analysis)
- [Global Flags](https://docs.checkmarx.com/en/34965-68626-global-flags.html)
- [SAST Scanner Parameters](https://docs.checkmarx.com/en/34965-324305-sast-scanner-parameters.html)
- [SCA Scanner Parameters](https://docs.checkmarx.com/en/34965-324307-sca-scanner-parameters.html)
- [Container Security Scanner Parameters](https://docs.checkmarx.com/en/34965-324312-container-security-scanner-parameters.html)
- [Running SCS Scans](https://docs.checkmarx.com/en/34965-386862-running-scs-scans.html)
- [SBOM Reports](https://docs.checkmarx.com/en/34965-19159-sbom-reports.html)

---

## Overview

The `cx scan` command manages scans in Checkmarx One. Usage pattern:

```
cx scan <subcommand> [flags]
```

### Available Subcommands

| Subcommand | Description |
|---|---|
| `create` | Create and run a new scan in Checkmarx One |
| `list` | List all scans in Checkmarx One |
| `show` | Show information about a requested scan |
| `workflow` | Provide information about a scan workflow |
| `cancel` | Cancel one or more running scans |
| `delete` | Delete one or more scans |
| `tags` | List all available tags for filtering |
| `logs` | Download scan log for a selected scan type |

Additional subcommands (some hidden/internal):

| Subcommand | Description |
|---|---|
| `kics-realtime` | Create and run KICS scan using docker image |
| `sca-realtime` | Run SCA real-time scan |
| `asca` | Run ASCA scan (hidden) |
| `oss-realtime` | Run OSS-Realtime scan (hidden) |
| `iac-realtime` | Run IaC-Realtime scan (hidden) |
| `containers-realtime` | Run Containers-Realtime scan (hidden) |
| `secrets-realtime` | Run Secrets-Realtime scan (hidden) |

---

## 1. `cx scan create`

Create and run a new scan in Checkmarx One.

### Basic Usage

```bash
cx scan create --project-name <name> -s <source> --branch <branch> [flags]
```

### Source Types (`-s` / `--sources`)

The `-s` flag accepts three types of sources:

| Source Type | Example | Notes |
|---|---|---|
| **Local directory** | `-s /path/to/project` | Directory on local filesystem |
| **Zip file** | `-s /path/to/project.zip` | Zip archive of source code |
| **Git repository URL** | `-s https://github.com/org/repo` | HTTPS or SSH git URL |

For SSH git URLs, use `--ssh-key` to provide the path to an SSH private key.

### Scan Types (`--scan-types`)

Comma-separated list of scanners to run:

| Scan Type Value | Scanner |
|---|---|
| `sast` | Static Application Security Testing |
| `sca` | Software Composition Analysis |
| `iac-security` | Infrastructure as Code Security (formerly KICS) |
| `api-security` | API Security scanning |
| `container-security` | Container image security scanning |
| `scs` | Supply Chain Security |

Example: `--scan-types sast,sca,iac-security`

If omitted, the project's default configured scan types are used.

---

### Complete Flag Reference

#### Required Flags

| Flag | Short | Type | Description |
|---|---|---|---|
| `--project-name` | | string | Name of the project. Creates the project if it does not exist. **(Required)** |
| `--branch` | `-b` | string | Git branch to scan. Required even for zip archives (use `.unknown` if not applicable, shows as "N/A" in UI). **(Required)** |
| `--sources` | `-s` | string | Source to scan: directory path, zip file path, or git repository URL. **(Required)** |

#### Scan Execution Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--scan-types` | string | "" | Comma-separated scan types to run (sast, sca, iac-security, api-security, container-security, scs) |
| `--async` | bool | `false` | Do not wait for scan completion. Returns immediately with scan ID. |
| `--wait-delay` | int | (default) | Polling wait time in seconds to check scan status |
| `--scan-timeout` | int | `0` | Cancel the scan and fail after this timeout in minutes. 0 = no timeout. |
| `--scan-resubmit` | bool | `false` | Use the most recent scan configuration for this project |
| `--scan-enqueue-retries` | int | `0` | Number of retry attempts for scan enqueue failures |
| `--scan-enqueue-retry-delay` | int | `5` | Base delay in seconds between retry attempts |

#### Project Assignment Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--project-groups` | string | "" | Comma-separated list of groups to associate with project (e.g., `groupA,groupB`). Only works when creating a new project; does not update existing projects. |
| `--project-tags` | string | "" | Tags to associate with the project. Only works when creating a new project. |
| `--application-name` | string | "" | Application name to assign the project to. Works for both new and existing projects. Adding to an existing project requires `update-application` permission. |
| `--branch-primary` | bool | `false` | Set the branch specified in `--branch` as the PRIMARY branch for the project |

#### Scan Metadata Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--tag-list` | string | "" | Tags to associate with the scan (comma-separated key:value pairs) |

#### File Filtering Flags

Three levels of filtering are available:

**1. Entire Scan Filtering** (pre-scan, files not sent to any scanner):

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| `--source-dir-filter` | `-d` | string | "" | Source file filtering pattern for the entire scan |
| `--include-filter` | `-i` | string | "" | Extra file extensions to include (comma-separated) |
| `--git-ignore-file-filter` | | bool | `false` | Exclude files/directories based on `.gitignore` patterns |

**2. Scanner-Specific Filters** (applied per scanner during scan):

| Flag | Type | Default | Description |
|---|---|---|---|
| `--sast-filter` | string | "" | SAST-specific file filter. Use `!` prefix to exclude. Example: `--sast-filter "!*.test.js"` |
| `--sca-filter` | string | "" | SCA-specific file filter configuration |
| `--iac-security-filter` | string | "" | IaC Security file filter configuration |

**3. Container-Specific Filters:**

| Flag | Type | Default | Description |
|---|---|---|---|
| `--containers-file-folder-filter` | string | "" | Include/exclude files and folders for container scans. Use `!` prefix to exclude. Example: `'!**/Dockerfile'` |
| `--containers-package-filter` | string | "" | Exclude packages matching a regex pattern |
| `--containers-image-tag-filter` | string | "" | Exclude container images by tag or name |
| `--containers-exclude-non-final-stages` | bool | `false` | Scan only the final deployable image stage |

**Filter Syntax:**
- Filters are applied in the order they appear in the expression
- When both include and exclude filters are used, include filters must come first
- Use `!` prefix for exclusion patterns
- Use `,` to chain multiple filter patterns

#### SAST-Specific Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--incremental-sast` | bool | `false` | Perform an incremental SAST scan (only scans changed files). Requires at least one completed full scan on the project. |
| `--preset-name` | string | "" | SAST preset name to use for the scan |
| `--sast-fast-scan` | bool | `false` | Enable SAST Fast Scan mode |
| `--sast-light-queries` | bool | `false` | Enable SAST light query configuration |
| `--sast-recommended-exclusions` | bool | `false` | Enable recommended exclusions for SAST |
| `--sast-redundancy` | bool | `false` | Populate SAST redundancy data field |

#### SCA-Specific Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--sca-resolver` | string | "" | Path to SCA Resolver executable |
| `--sca-resolver-params` | string | "" | Additional parameters for SCA Resolver. If spaces/quotes needed, wrap in double quotes and use single quotes inside. |
| `--sca-hide-dev-and-test-deps` | bool | `false` | Hide development and test dependencies from results |
| `--sca-private-package-version` | string | "" | Private package version setting |
| `--exploitable-path` | string | "" | Enable/disable Exploitable Path feature (`true` or `false`) |
| `--last-sast-scan-time` | string | "" | Number of days that SAST scan results remain valid for Exploitable Path analysis |
| `--project-private-package` | string | "" | Designate the scan as a private package |
| `--sbom` | bool | `false` | Scan an SBOM file only (XML or JSON format). Only compatible with `sca` scan type. |

#### IaC Security Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--iacs-preset-id` | string | "" | Infrastructure-as-Code Security preset ID |
| `--iac-security-platforms` | string[] | [] | Specific IaC platforms to scan |

#### Container Security Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--container-images` | string | "" | Comma-separated list of container images to scan. Supports formats: `image:tag`, `.tar` files, and prefixes (`docker:`, `podman:`, `file:`) |
| `--container-resolve-locally` | bool | `false` | Execute container resolver locally |

#### API Security Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--api-documentation` | string | "" | Path to API documentation file (e.g., OpenAPI/Swagger spec) |

#### SCS (Supply Chain Security) Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--scs-engines` | string | "" | SCS engines to run: `scorecard`, `secret-detection` (comma-separated) |
| `--scs-repo-token` | string | "" | Repository token for scorecard scans |
| `--scs-repo-url` | string | "" | Repository URL for scorecard scans. `scorecard` engine requires GitHub Cloud URLs. |
| `--git-commit-history` | string | "" | Enable git commit history scanning (for SCS secret-detection scans only) |

#### Authentication for Git Sources

| Flag | Type | Default | Description |
|---|---|---|---|
| `--ssh-key` | string | "" | Path to SSH private key for git repository authentication |

#### Report Generation Flags

These flags generate reports as part of the scan create command:

| Flag | Type | Default | Description |
|---|---|---|---|
| `--report-format` | string | "" | Report format to generate. See supported formats below. |
| `--report-sbom-format` | string | "" | SBOM report format (e.g., `CycloneDxJson`, `CycloneDxXml`, `SpdxJson`) |
| `--report-pdf-email` | string | "" | Email address(es) for PDF report delivery |
| `--report-pdf-options` | string | "" | Sections to include in the PDF report |

**Supported Report Formats (`--report-format`):**

| Format | Description |
|---|---|
| `json` | Complete scan results in JSON format |
| `sarif` | SARIF format for IDE/tool integration |
| `sonar` | SonarQube-compatible format |
| `pdf` | PDF report (use with `--report-pdf-email` and `--report-pdf-options`) |
| `sbom` | SBOM report (use with `--report-sbom-format`) |
| `summaryHTML` | HTML scan summary report |
| `summaryJSON` | JSON scan summary report |
| `summaryConsole` | Console-printed scan summary |
| `summaryMarkdown` | Markdown scan summary report |

**SBOM Formats (`--report-sbom-format`):**
- `CycloneDxJson` - CycloneDX in JSON (v1.0-1.6 supported)
- `CycloneDxXml` - CycloneDX in XML
- `SpdxJson` - SPDX v2.3 in JSON

#### Result Output Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--target` | string | `"cx_result"` | Output file name for results |
| `--target-path` | string | `"."` | Output directory path for results |
| `--filter` | string[] | [] | Result filters (comma-separated). Example: `--filter "severity=HIGH,state=CONFIRMED"` |

#### Threshold and Policy Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--threshold` | string | "" | Vulnerability threshold for pass/fail. Format: `<engine>-<severity>=<limit>`. Example: `--threshold "sast-high=1;sca-medium=5"` |
| `--policy-timeout` | int | (default) | Policy evaluation timeout in minutes |
| `--ignore-policy` | bool | `false` | Skip policy evaluation entirely |

**Threshold format:** `<scanner>-<severity>=<count>` where severity is one of: `critical`, `high`, `medium`, `low`. Use `;` to separate multiple thresholds.

When a threshold is breached, Checkmarx One returns a failure exit code, enabling pipeline build-breaking.

---

### Examples

**Basic scan from local directory:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/source \
  --branch main
```

**Scan specific types from a git repo:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s https://github.com/org/repo.git \
  --branch develop \
  --scan-types sast,sca,iac-security
```

**Incremental SAST scan with threshold:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/source \
  --branch main \
  --scan-types sast \
  --incremental-sast \
  --threshold "sast-high=0;sast-medium=5"
```

**Async scan with report generation:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/project.zip \
  --branch .unknown \
  --async \
  --report-format summaryJSON
```

**Scan with PDF report via email:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/source \
  --branch main \
  --report-format pdf \
  --report-pdf-email "team@example.com" \
  --report-pdf-options "ScanSummary,ExecutiveSummary,ScanResults"
```

**SBOM report generation:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/source \
  --branch main \
  --report-format sbom \
  --report-sbom-format CycloneDxJson
```

**Container image scan:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/source \
  --branch main \
  --scan-types container-security \
  --container-images "myregistry/myimage:latest,myregistry/other:v2"
```

**SCS scan with secret detection:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s https://github.com/org/repo.git \
  --branch main \
  --scan-types scs \
  --scs-engines secret-detection \
  --scs-repo-token <token> \
  --scs-repo-url https://github.com/org/repo
```

**Scan with file filters:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/source \
  --branch main \
  --sast-filter "!*.test.js,!*.spec.ts" \
  --git-ignore-file-filter
```

**Scan with SCA Resolver:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/source \
  --branch main \
  --scan-types sca \
  --sca-resolver /path/to/ScaResolver \
  --sca-resolver-params "-r /path/to/requirements.txt"
```

**Scan with project assignment:**
```bash
cx scan create \
  --project-name "MyProject" \
  -s /path/to/source \
  --branch main \
  --application-name "MyApp" \
  --project-groups "teamA,teamB" \
  --project-tags "env:prod,team:backend" \
  --tag-list "release:v1.2,sprint:42"
```

---

## 2. `cx scan list`

List all scans in the Checkmarx One account.

### Usage

```bash
cx scan list [--filter <filters>] [--format <format>]
```

### Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--filter` | string[] | [] | Filter results. Use `;` as delimiter between values for same attribute; `,` between different filter attributes. |
| `--format` | string | `"table"` | Output format: `table`, `list`, or `json` |

### Supported Filter Attributes

| Filter | Description |
|---|---|
| `limit` | Maximum number of results to return (default: 20) |
| `offset` | Number of results to skip before returning (default: 0). Use `offset=0,limit=0` to get all results. |
| `branch` | Filter by branch name |
| `branches` | Filter by multiple branch names |
| `from-date` | Filter scans from this date |
| `to-date` | Filter scans up to this date |
| `groups` | Filter by project groups |
| `initiators` | Filter by scan initiator |
| `project-id` | Filter by single project ID |
| `project-ids` | Filter by multiple project IDs |
| `project-names` | Filter by project names |
| `scan-ids` | Filter by specific scan IDs |
| `search` | Free text search |
| `source-origins` | Filter by source origin |
| `source-types` | Filter by source type |
| `statuses` | Filter by scan status (e.g., `Completed`, `Running`, `Failed`, `Canceled`) |
| `tags-keys` | Filter by tag keys |
| `tags-values` | Filter by tag values |

**Filter logic:**
- Multiple filter attributes: AND operator
- Multiple values for same attribute: OR operator

### Examples

```bash
# List all scans (first 20)
cx scan list

# List scans for a specific project
cx scan list --filter "project-id=f761f24b-fbcc-4502-acef-7fa3f2de38ed"

# List completed scans in JSON format
cx scan list --filter "statuses=Completed" --format json

# List scans with pagination
cx scan list --filter "limit=50,offset=100"

# List all scans (no pagination limit)
cx scan list --filter "offset=0,limit=0"

# List scans by branch and status
cx scan list --filter "branch=main,statuses=Completed;Failed"

# List scans by date range
cx scan list --filter "from-date=2024-01-01,to-date=2024-12-31"
```

---

## 3. `cx scan show`

Show detailed information about a specific scan.

### Usage

```bash
cx scan show --scan-id <scan_id> [--format <format>]
```

### Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--scan-id` | string | "" | Scan ID to display. **(Required)** |
| `--format` | string | `"table"` | Output format: `table`, `list`, or `json` |

### Examples

```bash
# Show scan details in table format
cx scan show --scan-id a2f45c91-18ba-4d69-a748-972d0ecc1453

# Show scan details in JSON format
cx scan show --scan-id a2f45c91-18ba-4d69-a748-972d0ecc1453 --format json
```

---

## 4. `cx scan cancel`

Cancel one or more running scans.

### Usage

```bash
cx scan cancel --scan-id <scan_id1>[,<scan_id2>,...]
```

### Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--scan-id` | string | "" | One or more scan IDs to cancel (comma-separated). **(Required)** |

### Examples

```bash
# Cancel a single scan
cx scan cancel --scan-id a2f45c91-18ba-4d69-a748-972d0ecc1453

# Cancel multiple scans
cx scan cancel --scan-id a2f45c91-18ba-4d69-a748-972d0ecc1453,7eb83ed3-5734-4428-92a2-4819fc6c490f
```

---

## 5. `cx scan delete`

Delete one or more scans.

### Usage

```bash
cx scan delete --scan-id <scan_id1>[,<scan_id2>,...]
```

### Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--scan-id` | string | "" | One or more scan IDs to delete (comma-separated). **(Required)** |

### Examples

```bash
# Delete a single scan
cx scan delete --scan-id 7eb83ed3-5734-4428-92a2-4819fc6c490f

# Delete multiple scans
cx scan delete --scan-id 7eb83ed3-5734-4428-92a2-4819fc6c490f,a2f45c91-18ba-4d69-a748-972d0ecc1453
```

---

## 6. `cx scan tags`

List all available tags for scan filtering.

### Usage

```bash
cx scan tags
```

### Flags

No specific flags beyond global flags. Returns all available scan tags.

### Example Output

```json
{
  "demotag": [""],
  "main": [""],
  "team": ["dev01", "dev02", "qa"]
}
```

---

## 7. `cx scan workflow`

Provide information about a scan's workflow/execution log.

### Usage

```bash
cx scan workflow --scan-id <scan_id> [--format <format>]
```

### Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--scan-id` | string | "" | Scan ID to retrieve workflow info for. **(Required)** |
| `--format` | string | `"table"` | Output format: `table`, `list`, or `json` |

### Examples

```bash
# Show scan workflow in table format
cx scan workflow --scan-id a2f45c91-18ba-4d69-a748-972d0ecc1453

# Show scan workflow in JSON format
cx scan workflow --scan-id a2f45c91-18ba-4d69-a748-972d0ecc1453 --format json
```

---

## 8. `cx scan logs`

Download scan log for a selected scan type.

### Usage

```bash
cx scan logs --scan-id <scan_id> --scan-type <type>
```

### Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--scan-id` | string | "" | Scan ID to retrieve log for. **(Required)** |
| `--scan-type` | string | "" | Scan type: `sast` or `iac-security`. **(Required)** |

### Examples

```bash
# Download SAST scan log
cx scan logs --scan-id a2f45c91-18ba-4d69-a748-972d0ecc1453 --scan-type sast

# Download IaC Security scan log
cx scan logs --scan-id a2f45c91-18ba-4d69-a748-972d0ecc1453 --scan-type iac-security
```

---

## Global Flags (applicable to all subcommands)

These flags can be used with any `cx` command:

| Flag | Type | Description |
|---|---|---|
| `--base-uri` | string | Base system URI for Checkmarx One |
| `--base-auth-uri` | string | Base IAM/authentication URI |
| `--tenant` | string | Checkmarx One tenant name |
| `--client-id` | string | OAuth2 client ID |
| `--client-secret` | string | OAuth2 client secret |
| `--apikey` | string | API Key for Checkmarx One authentication |
| `--proxy` | string | Proxy server URL for communication |
| `--agent` | string | Agent name identifier |
| `--debug` | bool | Enable debug/verbose logging |
| `-h` / `--help` | bool | Show help for the command |
| `-v` / `--version` | bool | Show version information |

These can also be set via environment variables (`CX_BASE_URI`, `CX_BASE_AUTH_URI`, `CX_TENANT`, `CX_CLIENT_ID`, `CX_CLIENT_SECRET`, `CX_APIKEY`, `CX_PROXY`) or via the `cx configure` command.

---

## Validation Rules and Constraints

- **Max upload file size:** 5 GB
- **Container image formats:** Supports `image:tag`, `.tar` files, and prefixes (`docker:`, `podman:`, `file:`)
- **SBOM flag:** Only compatible with `sca` scan type
- **Git commit history:** Only validated for SCS `secret-detection` scans
- **SCS scorecard engine:** Requires GitHub Cloud repository URLs
- **Incremental SAST:** Requires at least one completed full SAST scan on the project
- **File filters on git repos:** `--source-dir-filter` does not work on git repositories; use scanner-specific filters instead
- **Branch for zip archives:** Required even for zips; use `.unknown` if not applicable
- **Project groups/tags:** `--project-groups` and `--project-tags` only apply when creating a new project

---

## Real-Time Scan Subcommands

These subcommands run scans locally without the full Checkmarx One cloud pipeline:

### `cx scan kics-realtime`

Run IaC security scan locally using a Docker/Podman container.

| Flag | Type | Default | Description |
|---|---|---|---|
| `--file` | string | "" | Input file path **(Required)** |
| `--engine` | string | `"docker"` | Container engine: `docker` or `podman` |
| `--additional-params` | string[] | [] | Additional KICS scan options (comma-separated) |

### `cx scan sca-realtime`

Run SCA real-time scan locally.

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| `--sources` | `-s` | string | "" | Path to manifest file |

### Hidden Real-Time Subcommands

| Subcommand | Key Flags |
|---|---|
| `cx scan asca` | `--sources` / `-s`, `--asca-latest-version`, `--ignored-file-path`, `--asca-location` |
| `cx scan oss-realtime` | `--sources` / `-s`, `--ignored-file-path` |
| `cx scan iac-realtime` | `--sources` / `-s`, `--ignored-file-path`, `--engine` |
| `cx scan containers-realtime` | `--sources` / `-s`, `--ignored-file-path` |
| `cx scan secrets-realtime` | `--sources` / `-s`, `--ignored-file-path` |
