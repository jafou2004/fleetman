# fleetman
[![codecov](https://codecov.io/github/jafou2004/fleetman/graph/badge.svg?token=epAhdFg6wI)](https://codecov.io/github/jafou2004/fleetman)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/jafou2004/fleetman/ci.yml?logo=githubactions)
](https://github.com/jafou2004/fleetman/actions/workflows/ci.yml)
[![GitHub License](https://img.shields.io/github/license/jafou2004/fleetman)](https://github.com/jafou2004/fleetman/blob/main/LICENSE)

Shell tooling to manage a fleet of remote Linux servers: synchronize bash configuration, deploy git repositories, and operate Docker containers — all via SSH.

## Features

- **Fleet synchronization** — propagate scripts and config to all servers in one command
- **Docker pod management** — clone, start, update, pull, diff and push `.env` files across the fleet
- **Fleet health check** — SSH reachability, Docker daemon, container status at a glance
- **Key-based auth** — one-time setup generates a fleet RSA key; no password prompts after that
- **Any server can be master** — run `fleetman sync` from any server to push updates to all others
- **Per-server `.env` templating** — auto-generate server-specific variables from a shared template

## Prerequisites

All servers in the fleet must have:

```
git  jq  openssl  ssh-keygen  sshpass  docker
```

Install on Debian/Ubuntu: `sudo apt-get install git jq openssl openssh-client sshpass docker.io`

> `docker` is required only on servers that host pods. `git`, `jq`, `openssl`, `ssh-keygen`, and `sshpass` are required on the server running `fleetman install` and `fleetman sync`.

## Installation

### Quick install (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/jafou2004/fleetman/main/install.sh | bash
```

This will:
1. Clone the repository into `~/fleetman/`
2. Check out the latest semver release tag
3. Create a symlink `~/scripts → ~/fleetman/scripts/`
4. Run the interactive wizard to create `~/config.json`
5. Generate a fleet RSA key pair (`~/.ssh/fleet_key`)
6. Encrypt the shared SSH/sudo password (`~/.fleet_pass.enc`)
7. Deploy the key and encrypted password to all servers
8. Offer to run `sync` immediately

**Custom install directory or repository:**

```bash
FLEETMAN_DIR=~/mydir FLEETMAN_REPO=https://github.com/<MY_FORK>/fleetman.git \
  curl -fsSL https://raw.githubusercontent.com/<MY_FORK>/fleetman/main/install.sh | bash
```

### Manual install

```bash
git clone https://github.com/jafou2004/fleetman.git ~/fleetman
# Pin to the latest release (mirrors selfupdate default behaviour)
git -C ~/fleetman checkout "$(git -C ~/fleetman tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -1)"
ln -s ~/fleetman/scripts ~/scripts
bash ~/fleetman/install.sh
```

Re-running `install.sh` on an already-configured server prompts before overwriting — the default answer is **N** (abort).

## Configuration

Copy the example and edit with your fleet details:

```bash
cp ~/fleetman/config.json.example ~/config.json
```

### config.json reference

| Field | Type | Description |
|---|---|---|
| `servers` | object | Environments (`dev`, `test`, `prod`) mapping to arrays of FQDNs |
| `pods_dir` | string | Base directory for pod deployments on all servers (e.g. `/opt/pod`) |
| `base_folder` | string | Default working directory on SSH login — added to `~/.bashrc` on all servers |
| `parallel` | integer | Number of concurrent SSH jobs (default: 1 = sequential) |
| `env_colors` | object | Color per environment — used in the welcome screen |
| `status_checks.containers` | array | Container names checked by `fleetman status` and the welcome screen |
| `status_checks.wud_port` | integer | Port of the WUD update checker (enables the `⬆` indicator in the welcome screen) |
| `pods_ignore` | array | PCRE regex patterns — matching pod names are excluded from sync |
| `selfupdate` | object | Update tracking strategy (see [Selfupdate tracking](#selfupdate-tracking)) |
| `welcome` | object | Welcome screen flags: `enabled`, `show_pods`, `show_os`, `show_docker` |
| `template_vars` | object | Custom tokens for `.env` templates (see [env_templates](#env_templates)) |
| `pods` | object | Per-pod configuration: `env_vars` and `env_templates` |

### Example

```json
{
  "parallel": 4,
  "pods_dir": "/opt/pod",
  "pods_ignore": ["^tmp-"],
  "env_colors": { "dev": "green", "test": "yellow", "prod": "red" },
  "status_checks": { "containers": ["my-service"], "wud_port": 3000 },
  "servers": {
    "dev":  ["server1-dev.example.com", "server2-dev.example.com"],
    "test": ["server1-test.example.com"],
    "prod": ["server1-prod.example.com", "server2-prod.example.com"]
  }
}
```

## Usage

After `source ~/.bashrc`:

### Fleet commands

```bash
fleetman sync                        # Synchronize scripts and config to all servers
fleetman sync -q                     # Quick sync (config only, skip pod collection)
fleetman status                      # Fleet health: SSH, Docker, containers
fleetman exec "uptime"               # Run a command on all servers
fleetman exec "df -h" -e prod        # Run only on prod
fleetman sudo -- whoami              # Run a command with sudo
fleetman selfupdate                  # git pull + sync (update fleet scripts)
fleetman alias                       # List available aliases
fleetman alias -c git                # List aliases in the "git" category
```

### Pod commands

```bash
fleetman pod list                    # List all known pods
fleetman pod list -p myapp           # Filter by name
fleetman pod list -e prod            # Filter by environment

fleetman pod clone -e dev            # Clone a git repo to dev servers (interactive)
fleetman pod up -p myapp             # Start a pod (docker compose up -d)
fleetman pod pull -p myapp           # git pull on a pod
fleetman pod update -p myapp         # Prompt for new .env values and restart
fleetman pod logs -p myapp           # Tail logs (interactive server selection)
fleetman pod ssh -p myapp            # SSH into a server hosting a pod
fleetman pod status -p myapp         # Docker container status for a pod
fleetman pod search -p myapp         # Find servers hosting a pod
```

### Pod env commands

```bash
fleetman pod env diff -p myapp       # Diff .env vs .env-dist (shows missing/extra vars)
fleetman pod env edit -p myapp       # Edit the .env of a pod (local or remote)
fleetman pod env cp -p myapp         # Propagate .env to all servers hosting the pod
```

`fleetman pod env cp` applies per-server template substitution before copying (see [env_templates](#env_templates)).

### Config commands (interactive)

```bash
fleetman config               # Interactive config menu
fleetman config parallel      # Set the number of parallel SSH jobs
fleetman config env           # Manage environments (add, change color)
fleetman config server        # Manage servers (add)
fleetman config status        # Manage status check containers
fleetman config templatevars  # Manage template_vars
fleetman config welcome       # Toggle welcome screen options
fleetman config selfupdate    # Configure selfupdate tracking strategy
fleetman config pod           # Manage pod configurations (env_vars, env_templates)
fleetman config podsignore    # Manage pods_ignore patterns
fleetman config basefolder    # Set the default working directory on SSH login
fleetman config autosync      # Toggle auto-sync after config changes
fleetman config updatepassword  # Rotate the fleet SSH/sudo password
```

## env_templates

`env_templates` let you define `.env` variables whose value is computed per-server at deploy time, rather than being copied verbatim. When you run `pod env cp` or `pod update`, fleetman substitutes tokens in the template before writing the `.env` to each server.

### Defining templates

In `config.json`, under `pods.<pod-name>.env_templates`:

```json
"pods": {
  "my-app-docker": {
    "env_vars": ["MY_APP_VERSION"],
    "env_templates": {
      "MY_APP_TITLE": "[{COMPANY}] Server {name} {num}",
      "MY_APP_HOST":  "{hostname}",
      "MY_APP_ENV":   "{ENV}",
      "MY_APP_LABEL": "Instance {Suffix} n°{num}"
    }
  }
}
```

`env_vars` and `env_templates` are mutually exclusive — a variable cannot appear in both.

### Built-in tokens

These tokens are resolved automatically from the server's FQDN (e.g. `server1-prod.abc.example.com`):

| Token | Example value | Description |
|---|---|---|
| `{hostname}` | `server1-prod.abc.example.com` | Full FQDN |
| `{short}` | `server1-prod` | Hostname without domain |
| `{env}` | `prod` | Environment name |
| `{pod}` | `my-app-docker` | Pod name |
| `{name}` | `server1` | Server name (part before the first `-`) |
| `{num}` | `1` | Server number extracted from the name |
| `{suffix}` | `prod` | Part after the number (e.g. `-prod`) |

All built-in tokens support three case variants:
- `{token}` — lowercase (`server1`)
- `{TOKEN}` — uppercase (`SERVER1`)
- `{Token}` — title case (`Server1`)

### Custom tokens (`template_vars`)

Define reusable values under `template_vars` at the root of `config.json`. Values can be a plain string (same across all environments) or an environment-specific object:

```json
"template_vars": {
  "company": "ACME",
  "region": {
    "*":    "EU",
    "dev":  "EU-DEV",
    "test": "EU-TEST"
  }
}
```

- `"*"` is the fallback used when no env-specific key matches
- Custom tokens support the same three case variants as built-in tokens

Reference them in templates with `{company}`, `{COMPANY}`, `{Company}`, etc.

## Selfupdate tracking

Configure how `fleetman selfupdate` resolves the target version in `config.json`:

```json
"selfupdate": {
  "track": "tags",
  "branch": "main",
  "pin": ""
}
```

| `track` value | Behavior |
|---|---|
| `"tags"` (default) | Checks out the latest semver tag |
| `"commits"` | Pulls the latest commit on the current branch |
| `"branch"` | Tracks a named branch (configured in `branch`) |

Set `pin` to a specific version (e.g. `"v1.2.0"`) to lock the fleet to that release, overriding `track`.

## Fleet management

### Adding a new server

1. Run `fleetman config server add` — prompts for the FQDN, selects the environment, and offers to bootstrap the new server
2. Run `fleetman sync`

### Rotating the fleet password

```bash
fleetman config updatepassword
```

### Updating fleet scripts

```bash
fleetman selfupdate     # git pull + sync to all servers
```

Or manually:

```bash
cd ~/fleetman && git pull
fleetman sync
```

From any other server, `fleetman selfupdate` locates the server holding the git clone, runs `git pull` there, then syncs to all servers.

## Uninstalling

```bash
bash ~/scripts/internal/uninstall.sh
```

This will:
1. Ask for triple confirmation (server hostname / `yes` / `UNINSTALL`)
2. Remove on every server: `~/scripts/`, `~/.bash_aliases`, `~/config.json`, `~/.data/`, `~/.ssh/fleet_key*`, `~/.fleet_pass.enc`, `.bashrc` blocks, selfupdate cron entry
3. Offer to remove the git clone directory (`~/fleetman/`) on the local server
