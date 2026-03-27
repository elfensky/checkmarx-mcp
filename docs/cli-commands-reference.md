# Checkmarx One CLI Commands Reference

Comprehensive reference for `cx results`, `cx triage`, and `cx project` commands.

---

## cx results

The `results` command retrieves scan results and generates reports from Checkmarx One.

### cx results show

Retrieves scan results and generates reports in various formats.

**Syntax:**

```bash
cx results show --scan-id <scan-id> [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--scan-id` | string | Yes | - | The unique identifier of the scan to retrieve results for |
| `--report-format` | string | No | - | Output report format (see values below) |
| `--output-name` | string | No | - | Custom filename for the generated report |
| `--output-path` | string | No | `.` | Directory path where the report file will be saved |
| `--filter` | string | No | - | Filter, pagination, and sorting options for report data |
| `--report-pdf-email` | string | No | - | Email recipients for PDF reports (comma-separated). Only valid when `--report-format pdf` |
| `--report-pdf-options` | string | No | All Sections | Sections to include in PDF report. Only valid when `--report-format pdf` |
| `--report-sbom-format` | string | No | - | SBOM standard and output format. Only valid when `--report-format sbom` |
| `--sca-hide-devtest-dependencies` | bool | No | false | Filters out dev and test dependencies from SCA results in scan reports |
| `--format` | string | No | - | Output format for console display: `json`, `list`, or `table` |

#### --report-format Values

| Value | Description |
|-------|-------------|
| `json` | Detailed list of risks identified (original format) |
| `json-v2` | Detailed list of risks, identical to JSON report generated via UI |
| `sarif` | SARIF (Static Analysis Results Interchange Format) detailed report |
| `csv` | Comma-separated values format |
| `pdf` | PDF report with summary and/or detailed risk list (use `--report-pdf-options` to customize sections) |
| `summaryHTML` | HTML summary report with aggregated risk data |
| `summaryConsole` | Console-formatted summary report with aggregated risk data |
| `summaryJSON` | JSON summary report with aggregated risk data |
| `markdown` | Markdown-formatted summary report with aggregated risk data |
| `gl-sast` | GitLab SAST format (returns only SAST results) |
| `gl-sca` | GitLab SCA format (returns only SCA results) |
| `sonar` | SonarQube-compatible detailed report |
| `sbom` | Software Bill of Materials (requires `--report-sbom-format`) |

#### --report-pdf-options Values

Comma-separated list of sections to include in the PDF report:

- `Sast` -- SAST scan results section
- `Sca` -- SCA scan results section
- `Iac-Security` -- IaC Security scan results section
- `ScanSummary` -- Scan summary section
- `ExecutiveSummary` -- Executive summary section
- `ScanResults` -- Detailed scan results section

#### --report-sbom-format Values

| Value | Description |
|-------|-------------|
| `CycloneDxJson` | CycloneDX standard in JSON format |
| `CycloneDxXml` | CycloneDX standard in XML format |
| `SpdxJson` | SPDX standard in JSON format |

#### --filter Syntax

Filters, pagination, and sorting for report data. Use `;` to separate multiple values for a single filter. Use `,` to separate multiple filter attributes. When multiple filter attributes are used, AND logic is applied between them. When multiple values are given for one attribute, OR logic is applied.

| Filter Key | Values / Description |
|------------|---------------------|
| `severity` | `Critical`, `High`, `Medium`, `Low`, `Info` |
| `state` | `TO_VERIFY`, `NOT_EXPLOITABLE`, `PROPOSED_NOT_EXPLOITABLE`, `CONFIRMED`, `URGENT`, `EXCLUDE_NOT_EXPLOITABLE` |
| `status` | Result status filter |
| `limit` | Maximum number of results to return |
| `offset` | Number of results to skip |
| `sort` | Sort order for results |

The special state value `EXCLUDE_NOT_EXPLOITABLE` excludes only NOT_EXPLOITABLE results (rather than including only a specific state).

#### Examples

```bash
# Generate a SARIF report
cx results show --scan-id <scan-id> --report-format sarif \
  --output-name my-report --output-path /tmp/reports

# Generate a JSON report filtered by high/critical severity
cx results show --scan-id <scan-id> --report-format json \
  --filter "severity=High;Critical,state=CONFIRMED"

# Generate a PDF report emailed to recipients
cx results show --scan-id <scan-id> --report-format pdf \
  --report-pdf-email "dev@example.com,security@example.com" \
  --report-pdf-options "ExecutiveSummary,ScanSummary,Sast,Sca"

# Generate an SBOM report in CycloneDX JSON
cx results show --scan-id <scan-id> --report-format sbom \
  --report-sbom-format CycloneDxJson

# Summary report on the console
cx results show --scan-id <scan-id> --report-format summaryConsole

# GitLab SAST integration format
cx results show --scan-id <scan-id> --report-format gl-sast

# Hide dev/test dependencies in SCA results
cx results show --scan-id <scan-id> --report-format json \
  --sca-hide-devtest-dependencies

# Paginated results
cx results show --scan-id <scan-id> --report-format json \
  --filter "limit=50,offset=100"
```

---

### cx results codebashing

Retrieves Codebashing lesson links for vulnerability remediation training. Requires a Codebashing account linked to your Checkmarx One account.

**Syntax:**

```bash
cx results codebashing --language <language> --vulnerability-type <type> --cwe-id <id> [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--language` | string | Yes | - | Programming language of the vulnerability (e.g., `PHP`, `Java`, `JavaScript`, `C#`, `Python`) |
| `--vulnerability-type` | string | Yes | - | The type/name of the vulnerability (e.g., `Reflected XSS All Clients`, `SQL Injection`) |
| `--cwe-id` | string | Yes | - | CWE (Common Weakness Enumeration) identifier (e.g., `79`, `89`) |
| `--format` | string | No | - | Output format: `json`, `list`, or `table` |

#### Example

```bash
# Get Codebashing link for a PHP XSS vulnerability
cx results codebashing --language PHP \
  --vulnerability-type "Reflected XSS All Clients" --cwe-id 79

# Get remediation training for SQL Injection in Java
cx results codebashing --language Java \
  --vulnerability-type "SQL Injection" --cwe-id 89 --format json
```

---

## cx triage

The `triage` command manages vulnerability predicates (state, severity, notes) in Checkmarx One. Each vulnerability instance has a Predicate comprised of state, severity, and notes.

### cx triage show

Retrieves the predicate history (list of all changes) for a specific vulnerability instance.

**Syntax:**

```bash
cx triage show --scan-type <type> --project-id <id> --similarity-id <id> [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--project-id` | string | Yes | - | Project ID for which to retrieve the predicate history |
| `--similarity-id` | string | Yes | - | Unique identifier of the specific vulnerability instance |
| `--scan-type` | string | Yes | - | Scanner type that identified the risk: `sast`, `kics`, or `scs` |
| `--format` | string | No | - | Output format: `json`, `list`, or `table` |

#### Example

```bash
# Show triage history for a SAST finding
cx triage show --scan-type sast \
  --project-id 885ca4ad-5926-4177-b51c-fa1d11248d84 \
  --similarity-id 549106280

# Show triage history in JSON format
cx triage show --scan-type kics \
  --project-id <project-id> \
  --similarity-id <similarity-id> --format json
```

---

### cx triage update

Updates the predicate (state, severity, comment) for a vulnerability instance.

**Syntax:**

```bash
cx triage update --scan-type <type> --project-id <id> --similarity-id <id> --state <state> --severity <severity> [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--project-id` | string | Yes | - | Project ID for which this predicate change will take effect |
| `--similarity-id` | string | Yes | - | Unique identifier of the specific vulnerability instance |
| `--scan-type` | string | Yes | - | Scanner type that identified the risk: `sast`, `kics`, or `scs` |
| `--state` | string | Yes | - | New state for the vulnerability |
| `--severity` | string | Yes | - | New severity for the vulnerability |
| `--comment` | string | No | - | Comment/note to attach to this triage change (may be mandatory for certain state transitions) |

#### --state Values

| Value | Description |
|-------|-------------|
| `to_verify` | Default state; result needs review |
| `not_exploitable` | Result confirmed as not exploitable |
| `proposed_not_exploitable` | Proposed as not exploitable (pending confirmation) |
| `confirmed` | Result confirmed as a real vulnerability |
| `urgent` | Result is urgent and requires immediate attention |

#### --severity Values

| Value | Description |
|-------|-------------|
| `critical` | Critical severity |
| `high` | High severity |
| `medium` | Medium severity |
| `low` | Low severity |
| `info` | Informational only |

#### Example

```bash
# Mark a finding as confirmed with high severity
cx triage update --scan-type sast \
  --project-id <project-id> \
  --similarity-id <similarity-id> \
  --state confirmed --severity high \
  --comment "Verified via manual review"

# Mark a finding as not exploitable
cx triage update --scan-type sast \
  --project-id <project-id> \
  --similarity-id <similarity-id> \
  --state not_exploitable --severity medium \
  --comment "Input is sanitized upstream in middleware"

# Mark a KICS finding as urgent
cx triage update --scan-type kics \
  --project-id <project-id> \
  --similarity-id <similarity-id> \
  --state urgent --severity critical
```

---

## cx project

The `project` command manages projects in Checkmarx One.

### cx project create

Creates a new project.

**Syntax:**

```bash
cx project create --project-name <name> [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--project-name` | string | Yes | - | Name for the new project |
| `--branch` | string | No | - | Main branch for the project |
| `--groups` | string | No | - | List of groups to assign (e.g., `PowerUsers`) |
| `--tags` | string | No | - | List of tags in format `tagA,tagB:val` (key or key:value pairs) |
| `--format` | string | No | - | Output format: `json`, `list`, or `table` |

#### Example

```bash
# Create a simple project
cx project create --project-name "my-app"

# Create a project with branch, groups, and tags
cx project create --project-name "my-app" \
  --branch main \
  --groups "PowerUsers" \
  --tags "env:prod,team:backend,priority:high"

# Create and output as JSON
cx project create --project-name "my-app" --format json
```

---

### cx project list

Lists all projects in the system. Returns Project ID, Project Name, creation date, Tags, and Groups.

**Syntax:**

```bash
cx project list [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--filter` | string | No | - | Filter projects (see filter keys below) |
| `--format` | string | No | - | Output format: `json`, `list`, or `table` |

#### --filter Keys

All filter and pagination options available for the `GET /projects` REST API can be used. Use `;` to separate multiple values for one filter key. Use `,` to separate multiple filter keys. AND logic between attributes; OR logic between values of the same attribute.

| Filter Key | Description |
|------------|-------------|
| `limit` | Maximum number of results (default: 20; set to `0` for all records) |
| `offset` | Number of results to skip |
| `ids` | Filter by specific project IDs |
| `name` | Filter by exact project name |
| `name-regex` | Filter by project name using regex |
| `names` | Filter by multiple project names |
| `groups` | Filter by group names |
| `tags-keys` | Filter by tag keys (use `NONE` for projects with no tags) |
| `tags-values` | Filter by tag values (use `NONE` for projects with no tags) |
| `repo-url` | Filter by repository URL |

#### Example

```bash
# List all projects (first 20)
cx project list

# List all projects (no limit)
cx project list --filter "limit=0"

# List projects with specific tags
cx project list --filter "tags-keys=env,tags-values=prod"

# List projects with no tags
cx project list --filter "tags-keys=NONE,tags-values=NONE"

# List projects with pagination
cx project list --filter "limit=50,offset=100"

# List projects by name regex
cx project list --filter "name-regex=my-app.*"

# Output as JSON
cx project list --format json
```

---

### cx project show

Shows detailed information about a specific project.

**Syntax:**

```bash
cx project show --project-id <project-id> [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--project-id` | string | Yes | - | The unique identifier of the project |
| `--format` | string | No | - | Output format: `json`, `list`, or `table` |

#### Example

```bash
# Show project details
cx project show --project-id ce46df28-7f33-49fe-88cb-337fe8eb2c39

# Show project details as JSON
cx project show --project-id ce46df28-7f33-49fe-88cb-337fe8eb2c39 --format json
```

---

### cx project delete

Deletes a project.

**Syntax:**

```bash
cx project delete --project-id <project-id> [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--project-id` | string | Yes | - | The unique identifier of the project to delete |

#### Example

```bash
cx project delete --project-id ce46df28-7f33-49fe-88cb-337fe8eb2c39
```

---

### cx project tags

Retrieves a list of all available tags across all projects.

**Syntax:**

```bash
cx project tags [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--format` | string | No | - | Output format: `json`, `list`, or `table` |

#### Example

```bash
# List all tags
cx project tags

# Example output (JSON):
# {"Demo":[""],"QA":["Automation","Manual"],"test":[""]}
```

---

### cx project branches

Lists all available branches for a project.

**Syntax:**

```bash
cx project branches --project-id <project-id> [flags]
```

#### Flags

| Flag | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `--project-id` | string | Yes | - | Project ID to retrieve branches for |
| `--filter` | string | No | - | Filter branches (supports `limit`, `offset`, and other pagination options) |
| `--format` | string | No | - | Output format: `json`, `list`, or `table` |

#### Example

```bash
# List branches for a project
cx project branches --project-id <project-id>

# List all branches (no limit)
cx project branches --project-id <project-id> --filter "limit=0"
```

---

## Global Flags (Available on All Commands)

These flags can be appended to any `cx` command:

| Flag | Type | Description |
|------|------|-------------|
| `--base-uri` | string | Base system URI for the Checkmarx One server |
| `--base-auth-uri` | string | Base IAM URI for authentication |
| `--tenant` | string | Checkmarx One tenant name |
| `--apikey` | string | API Key for authentication |
| `--client-id` | string | OAuth2 client ID |
| `--client-secret` | string | OAuth2 client secret |
| `--proxy` | string | Proxy server URL |
| `--proxy-auth-type` | string | Proxy authentication type: `basic` or `ntlm` |
| `--proxy-ntlm-domain` | string | Windows domain for NTLM proxy auth |

---

## Sources

- [Checkmarx One CLI - results](https://docs.checkmarx.com/en/34965-68640-results.html)
- [Checkmarx One CLI - triage](https://docs.checkmarx.com/en/34965-68662-triage.html)
- [Checkmarx One CLI - project](https://docs.checkmarx.com/en/34965-68634-project.html)
- [Checkmarx One CLI - Global Flags](https://docs.checkmarx.com/en/34965-68626-global-flags.html)
- [Checkmarx One CLI Commands](https://docs.checkmarx.com/en/34965-68625-checkmarx-one-cli-commands.html)
- [Checkmarx One CLI Tool](https://docs.checkmarx.com/en/34965-68620-checkmarx-one-cli-tool.html)
- [Scan Reports](https://docs.checkmarx.com/en/34965-182434-checkmarx-one-reporting.html)
- [SBOM Reports](https://docs.checkmarx.com/en/34965-19159-sbom-reports.html)
- [Checkmarx ast-cli GitHub Repository](https://github.com/Checkmarx/ast-cli)
