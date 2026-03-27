# Checkmarx One CLI -- Comprehensive Reference

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Authentication](#authentication)
- [Configuration](#configuration)
- [Global Flags](#global-flags)
- [Environment Variables](#environment-variables)
- [Utilities (cx utils)](#utilities-cx-utils)

---

## Overview

The Checkmarx One CLI (`cx`) is a standalone command-line tool wrapping Checkmarx One application security testing (AST) APIs. It is written in Go and distributed as a single binary for all major platforms.

- **Repository**: <https://github.com/Checkmarx/ast-cli>
- **License**: Apache 2.0
- **Documentation**: <https://docs.checkmarx.com/en/34965-68620-checkmarx-one-cli-tool.html>

---

## Installation

### Direct Downloads (Latest Stable)

| Platform | URL |
|---|---|
| **Windows x64** | `https://download.checkmarx.com/CxOne/CLI/latest/ast-cli_windows_x64.zip` |
| **macOS x64 (Intel)** | `https://download.checkmarx.com/CxOne/CLI/latest/ast-cli_darwin_x64.tar.gz` |
| **Linux x64** | `https://download.checkmarx.com/CxOne/CLI/latest/ast-cli_linux_x64.tar.gz` |
| **Linux ARM64** | `https://download.checkmarx.com/CxOne/CLI/latest/ast-cli_linux_arm64.tar.gz` |
| **Linux ARMv6** | `https://download.checkmarx.com/CxOne/CLI/latest/ast-cli_linux_armv6.tar.gz` |

> **Note on macOS Apple Silicon (ARM64)**: The official "latest" download links list a macOS x64 build. For Apple Silicon (M-series) Macs, check the [GitHub Releases page](https://github.com/Checkmarx/ast-cli/releases) for a `darwin_arm64` asset. If not available, the x64 build runs via Rosetta 2.

Versioned releases with all platform binaries are available at:
<https://github.com/Checkmarx/ast-cli/releases>

### Homebrew (macOS / Linux)

```bash
brew install checkmarx/ast-cli/ast-cli
```

Repository: <https://github.com/Checkmarx/homebrew-ast-cli>

### Docker

```bash
docker pull checkmarx/ast-cli
```

Docker Hub: <https://hub.docker.com/r/checkmarx/ast-cli>

Example usage:

```bash
docker run --rm \
  -v "$(pwd)":/src \
  checkmarx/ast-cli \
  scan create -s /src --project-name MyProject --branch main
```

### Manual Installation & PATH Setup

**Linux / macOS:**

```bash
# Download and extract (example: Linux x64)
curl -LO https://download.checkmarx.com/CxOne/CLI/latest/ast-cli_linux_x64.tar.gz
tar -xzf ast-cli_linux_x64.tar.gz

# Move to a directory in your PATH
sudo mv cx /usr/local/bin/
cx version
```

**Windows:**

1. Download `ast-cli_windows_x64.zip`
2. Extract `cx.exe` from the archive
3. Move `cx.exe` to a directory in your system PATH, or add its location to PATH:
   ```cmd
   setx PATH "%PATH%;C:\path\to\cx"
   ```

### Supported / Tested Platforms

The CLI should work on recent versions of Windows, Linux, and macOS. Tested platforms include:

- **Windows**: Server 2012, 2016, 2019, 2022
- **Linux**: RedHat 8.9, Amazon Linux 2, Fedora 34, Ubuntu 20.04, CentOS 8
- **macOS**: Sequoia 15.5

### Building from Source

Requires [Go](https://golang.org/doc/install).

```bash
# Linux
export GOOS=linux GOARCH=amd64
go build -o ./bin/cx ./cmd

# macOS
export GOOS=darwin GOARCH=amd64   # or arm64 for Apple Silicon
go build -o ./bin/cx ./cmd

# Windows
set GOOS=windows
set GOARCH=amd64
go build -o ./bin/cx.exe ./cmd

# Or use the Makefile (builds all platforms)
make build
```

---

## Authentication

Authentication to Checkmarx One can use either an **API Key** or **OAuth2 Client Credentials**. The required parameters can be provided via CLI flags, environment variables, or a config file.

### Authentication Methods

#### 1. API Key

The simplest method. An API Key encodes all necessary account information (Base URI, Auth URI, Tenant). Generate one from the Checkmarx One portal: **Settings > Identity & Access Management > API Keys**.

```bash
cx scan create --apikey <YOUR_API_KEY> -s . --project-name MyProject --branch main
```

Or via environment variable:
```bash
export CX_APIKEY=<YOUR_API_KEY>
cx scan create -s . --project-name MyProject --branch main
```

#### 2. OAuth2 Client Credentials

Create an OAuth client from the Checkmarx One portal: **Settings > Identity & Access Management > OAuth Clients > Create Client**.

```bash
cx scan create \
  --base-uri https://ast.checkmarx.net \
  --base-auth-uri https://iam.checkmarx.net \
  --tenant your-tenant \
  --client-id <CLIENT_ID> \
  --client-secret <CLIENT_SECRET> \
  -s . --project-name MyProject --branch main
```

### `cx auth validate`

Validates authentication credentials against the Checkmarx One server.

```bash
cx auth validate --apikey <YOUR_API_KEY>
```

Or with OAuth2 credentials:

```bash
cx auth validate \
  --base-uri https://ast.checkmarx.net \
  --base-auth-uri https://iam.checkmarx.net \
  --tenant your-tenant \
  --client-id <CLIENT_ID> \
  --client-secret <CLIENT_SECRET>
```

### Credential Precedence

When the same parameter is specified in multiple places, the precedence is:

1. **CLI flags** (highest priority -- always win)
2. **Config file** values (`$HOME/.checkmarx/`)
3. **Environment variables** (lowest priority)

---

## Configuration

### `cx configure` (Interactive)

When run without subcommands, `cx configure` launches an interactive prompt that asks for authentication parameters and saves them to the config file.

```bash
cx configure
```

This prompts for: Base URI, Base Auth URI, Tenant, Client ID, Client Secret, and/or API Key.

### `cx configure set`

Sets individual configuration properties non-interactively.

```bash
cx configure set --prop-name cx_base_uri --prop-value https://ast.checkmarx.net
cx configure set --prop-name cx_base_auth_uri --prop-value https://iam.checkmarx.net
cx configure set --prop-name cx_tenant --prop-value your-tenant
cx configure set --prop-name cx_apikey --prop-value <YOUR_API_KEY>
cx configure set --prop-name cx_client_id --prop-value <CLIENT_ID>
cx configure set --prop-name cx_client_secret --prop-value <CLIENT_SECRET>
```

### `cx configure show`

Displays the current effective configuration.

```bash
cx configure show
```

Example output:

```
Current Effective Configuration:
  BaseURI:        https://ast.checkmarx.net
  BaseAuthURI:    https://iam.checkmarx.net
  Tenant:         your-tenant
  Client ID:      ********
  Client Secret:  ********
  APIKey:         ********
```

### Config File

- **Default location**: `$HOME/.checkmarx/`
- **Override location**: Set `CX_CONFIG_FILE_PATH` environment variable
- **Profile**: default profile name is `default`
- The `--config-file` flag can override the config file path per-command

---

## Global Flags

Global flags are optional and can be appended to any CLI command/sub-command.

### Authentication & Connection

| Flag | Type | Description | Default |
|---|---|---|---|
| `--base-uri` | string | The base system URI (Checkmarx One server URL) | -- |
| `--base-auth-uri` | string | The base system IAM URI (identity/auth server URL) | -- |
| `--tenant` | string | The Checkmarx One tenant name | -- |
| `--apikey` | string | API Key to login to Checkmarx One | -- |
| `--client-id` | string | OAuth2 client ID | -- |
| `--client-secret` | string | OAuth2 client secret | -- |

### Proxy

| Flag | Type | Description | Default |
|---|---|---|---|
| `--proxy` | string | Proxy server to send communication through | -- |
| `--proxy-auth-type` | string | Proxy authentication type: `basic`, `ntlm`, `kerberos`, or `kerberos-native` | -- |
| `--proxy-ntlm-domain` | string | Windows domain when using NTLM proxy | -- |
| `--proxy-kerberos-spn` | string | Service Principal Name for Kerberos proxy auth | -- |
| `--proxy-kerberos-krb5-conf` | string | Path to Kerberos configuration file | -- |
| `--proxy-kerberos-ccache` | string | Path to Kerberos credential cache | -- |
| `--ignore-proxy` | bool | Ignore the system proxy; run commands from local machine directly | false |

### Security

| Flag | Type | Description | Default |
|---|---|---|---|
| `--insecure` | bool | Ignore TLS certificate validations | false |

### Logging & Debugging

| Flag | Type | Description | Default |
|---|---|---|---|
| `--debug` | bool | Debug mode with detailed logs | false |
| `--log-file` | string | Save logs to the specified file path only (not to console) | -- |
| `--log-file-console` | string | Save logs to the specified file path AND to the console | -- |

### Output & Behavior

| Flag | Type | Description | Default |
|---|---|---|---|
| `--format` | string | Output format: `json`, `list`, or `table` | varies per command |
| `--timeout` | int | Timeout for network activity (in seconds) | `5` |
| `--agent` | string | Scan origin name (user-agent identifier) | `ASTCLI` |
| `--retry` | int | Retry requests on connection failure | `3` |
| `--config-file` | string | Path to config file for the current command | `$HOME/.checkmarx/` |
| `--optional-flags` | string | Pass command-specific flags as key-value pairs (useful for IDE/CI-CD plugins) | -- |

### Help

| Flag | Type | Description |
|---|---|---|
| `-h`, `--help` | bool | Show help for any command |

---

## Environment Variables

### Core Authentication & Connection

These are the primary environment variables for configuring the CLI:

| Environment Variable | Description |
|---|---|
| `CX_BASE_URI` | URL of the Checkmarx One server |
| `CX_BASE_AUTH_URI` | URL of the Checkmarx One IAM/authentication server |
| `CX_TENANT` | Checkmarx One tenant name |
| `CX_APIKEY` | API Key for authentication |
| `CX_CLIENT_ID` | OAuth2 client ID |
| `CX_CLIENT_SECRET` | OAuth2 client secret |

### Proxy

| Environment Variable | Description |
|---|---|
| `HTTP_PROXY` / `http_proxy` | Standard HTTP proxy (system-level) |
| `CX_HTTP_PROXY` | Checkmarx-specific HTTP proxy override |
| `CX_PROXY_AUTH_TYPE` | Proxy authentication type (basic, ntlm, kerberos, kerberos-native) |
| `CX_PROXY_NTLM_DOMAIN` | NTLM domain for proxy |
| `CX_PROXY_KERBEROS_SPN` | Kerberos SPN for proxy auth |
| `CX_PROXY_KERBEROS_KRB5_CONF` | Path to Kerberos krb5.conf file |
| `CX_PROXY_KERBEROS_CCACHE` | Path to Kerberos credential cache |
| `CX_IGNORE_PROXY` | If set, bypasses proxy configuration |

### Behavior & Misc

| Environment Variable | Description |
|---|---|
| `CX_TIMEOUT` | Client timeout duration |
| `CX_BRANCH` | Default branch specification |
| `CX_AGENT_NAME` | Agent identification name |
| `CX_ORIGIN` | Request origin identifier |
| `CX_TOKEN_EXPIRY_SECONDS` | Token expiration duration |
| `CX_CONFIG_FILE_PATH` | Override path for the config file |
| `CX_OPTIONAL_FLAGS` | Additional CLI parameters as key-value pairs |
| `CX_UNIQUE_ID` | Instance identifier |
| `CX_AST_ROLE` | User role assignment |
| `CX_FEATURE_FLAGS_PATH` | Feature flags endpoint path |

### Setting Environment Variables

**Linux / macOS:**

```bash
export CX_BASE_URI=https://ast.checkmarx.net
export CX_BASE_AUTH_URI=https://iam.checkmarx.net
export CX_TENANT=your-tenant
export CX_APIKEY=your-api-key
```

**Windows:**

```cmd
setx CX_BASE_URI https://ast.checkmarx.net
setx CX_BASE_AUTH_URI https://iam.checkmarx.net
setx CX_TENANT your-tenant
setx CX_APIKEY your-api-key
```

> **Note**: Environment variables set with `export` (Linux/macOS) are valid only for the current shell session. Use shell profile files (`.bashrc`, `.zshrc`, etc.) for persistence. On Windows, `setx` persists across sessions.

---

## Utilities (`cx utils`)

### `cx utils env`

Displays all detected Checkmarx One CLI environment variables and their current values.

```bash
cx utils env
```

Example output shows variables including: `cx_proxy_auth_type`, `cx_client_id`, `cx_client_secret`, `cx_apikey`, `cx_branch`, `cx_timeout`, `cx_base_uri`, `cx_tenant`, `http_proxy`, `sca_resolver`, `cx_base_auth_uri`.

### `cx utils completion`

Generates shell auto-completion scripts. Supports `bash`, `zsh`, `fish`, and `powershell`.

**Flag**: `-s` (shell type)

**Bash:**

```bash
cx utils completion -s bash > /etc/bash_completion.d/cx
```

**Zsh:**

```bash
cx utils completion -s zsh > "${fpath[1]}/_cx"
```

**Fish:**

```bash
cx utils completion -s fish > ~/.config/fish/completions/cx.fish
```

**PowerShell:**

```powershell
# Load for current session
cx.exe utils completion -s powershell | Out-String | Invoke-Expression

# Or save to file
cx.exe utils completion -s powershell > cx.ps1
```

### `cx utils contributor-count`

Counts unique contributors from SCM repositories for the past 90 days.

### `cx utils remediation`

Provides SCA (Software Composition Analysis) remediation utilities.

### `cx utils pr`

Decorates pull requests with results from Checkmarx One scans (GitHub, GitLab, Azure DevOps, Bitbucket).

---

## Quick Reference: All CLI Commands

| Command | Description |
|---|---|
| `cx auth validate` | Validate authentication credentials |
| `cx configure` | Interactive authentication configuration |
| `cx configure set` | Set a configuration property |
| `cx configure show` | Show current configuration |
| `cx scan create` | Create and run a new scan |
| `cx scan list` | List scans |
| `cx scan show` | Show scan details |
| `cx scan cancel` | Cancel a running scan |
| `cx scan delete` | Delete a scan |
| `cx scan tags` | Manage scan tags |
| `cx project create` | Create a project |
| `cx project list` | List projects |
| `cx project show` | Show project details |
| `cx project delete` | Delete a project |
| `cx project tags` | Manage project tags |
| `cx results show` | Show scan results |
| `cx triage show` | Show triage information |
| `cx triage update` | Update triage state |
| `cx utils env` | Show environment variables |
| `cx utils completion` | Generate shell completion scripts |
| `cx utils contributor-count` | Count repository contributors |
| `cx utils remediation` | SCA remediation utilities |
| `cx utils pr` | PR decoration with scan results |
| `cx version` | Show CLI version |
| `cx help` | Show help |

---

## Sources

- [Checkmarx One CLI Tool (docs)](https://docs.checkmarx.com/en/34965-68620-checkmarx-one-cli-tool.html)
- [Downloading and Installing the CLI](https://docs.checkmarx.com/en/34965-68622-checkmarx-one-cli-installation.html)
- [Configuring the CLI](https://docs.checkmarx.com/en/34965-118315-authentication-for-checkmarx-one-cli.html)
- [CLI Config and Environment Variables](https://docs.checkmarx.com/en/34965-68624-checkmarx-one-cli-config-and-environment-variables.html)
- [Global Flags](https://docs.checkmarx.com/en/34965-68626-global-flags.html)
- [auth Command](https://docs.checkmarx.com/en/34965-68627-auth.html)
- [configure Command](https://docs.checkmarx.com/en/34965-68630-configure.html)
- [utils Command](https://docs.checkmarx.com/en/34965-68653-utils.html)
- [CLI Quick Start Guide](https://docs.checkmarx.com/en/34965-68621-checkmarx-one-cli-quick-start-guide.html)
- [GitHub Repository (Checkmarx/ast-cli)](https://github.com/Checkmarx/ast-cli)
- [Docker Hub (checkmarx/ast-cli)](https://hub.docker.com/r/checkmarx/ast-cli)
- [Homebrew Tap (Checkmarx/homebrew-ast-cli)](https://github.com/Checkmarx/homebrew-ast-cli)
- [Creating an API Key](https://docs.checkmarx.com/en/34965-68618-generating-an-api-key.html)
- [Creating OAuth Clients](https://docs.checkmarx.com/en/34965-68612-creating-oauth-clients.html)
