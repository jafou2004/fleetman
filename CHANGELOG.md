# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.4] - 2026-04-16

### Added

- `fleetman ssh` — SSH into any fleet server via an interactive menu; optional `-e <env>` and `-s <shortname-filter>` flags; reads from `config.json .servers`

### Changed
- `fleetman config server add` — accepts multiple FQDNs (empty line to finish) before deploying SSH keys and syncing once

### Fixed

- `sync`: env with empty server list in `config.json` no longer triggers a spurious error line — `_IS_list_servers` now skips iteration when the array is empty
- `uninstall`: remote servers now uninstalled before local — prevents fleet key deletion from breaking SSH auth to remotes (race condition in parallel mode, ordering issue in sequential mode)
## [0.0.3] - 2026-04-16

### Added

- `fleetman port next` — lists the next N free external ports in the configured range across all servers/envs (default N=5, override with `-n X`)
- `fleetman port list` — lists all used external ports with pod/service, env, and server details; optional `-e <env>` filter
- `fleetman port check <port...>` — checks whether one or more port numbers are free (`✓`) or in use (`✗ used by pod/service [env] servers`)
- `fleetman config portrange` — configures the `port_range` in `config.json` (`min`/`max`, both in [1024, 65535]); prompted during `install.sh` wizard
- `config.json`: new optional `port_range` key `{ "min": N, "max": N }`
- `lib/ports.sh` — shared port helpers (`check_services_file`, `_port_read_range`, `_port_collect_used`)

### Fixed

- `sync`: deploy fleet key and `.fleet_pass.enc` via SSH stdin pipe instead of `scp` — fixes wrong destination on LDAP/domain users where SSH daemon `~` differs from shell `$HOME`

### Changed

- `sync`: executable bit on `bin/fleetman` and `internal/*.sh` tracked by git (`git update-index --chmod=+x`) — `chmod` calls removed from `sync_local`
## [0.0.2] - 2026-04-14

### Fixed

- `install.sh`: fix `curl-pipe-bash` bootstrap — `read` now uses `< /dev/tty` to avoid consuming script lines as user input
## [0.0.1] - 2026-04-12

### Added

#### CLI
- `fleetman` CLI entry point with auto-discovering dispatcher (`cli_dispatch`)
- Bash completion for all commands and sub-commands (3 levels deep) via `completion.sh`

#### Commands
- `sync` — propagates scripts, `.bash_aliases`, `config.json`, and `.data/` to the entire fleet; generates `pods.json`, `services.json` and per-server braille ASCII art
- `status` — checks SSH reachability, Docker daemon, and container health across the fleet
- `sudo` — runs a command with the fleet-shared sudo password
- `exec` — runs a command on one or all servers
- `alias` — manages bash aliases across the fleet
- `selfupdate` — pulls latest version from the git clone server, runs migrations, triggers sync
- `pod` subcommand suite: `list`, `up`, `update`, `logs`, `env`, `status`, `ssh`, `clone`, `pull`
- `config` subcommand suite: `server`, `pod`, `env`, `basefolder`, `autosync`, `status`, `welcome`, `selfupdate`, `templatevars`, `podsignore`, `parallel`, `updatepassword`

#### Infrastructure
- `install.sh` — one-time fleet initialization (SSH key, password encryption, git clone)
- `uninstall.sh` — removes fleet management tooling from all servers (triple confirmation)
- `welcome.sh` — welcome screen displayed on SSH login (TTY-guarded)
- Migration system — `run_migrations.sh` applies versioned `migrations/vX.Y.Z.sh` scripts on upgrade
- `config.json.example` — annotated configuration template

#### Shared library (`lib/`)
- `vars.sh` — global constants and paths
- `display.sh` — output formatting and coloring
- `auth.sh` — sudo password encryption/decryption
- `config.sh` — config.json read/write helpers
- `ui.sh` — interactive prompts and menus
- `iterate.sh` — fleet-wide parallel and sequential iteration
- `spinner.sh` — terminal spinner for long-running operations
- `templates.sh` — template variable substitution
- `bashrc.sh` — shell environment setup helpers

#### Tests
- Unit test suite with [bats](https://github.com/bats-core/bats-core) covering all commands and library functions
- Smoke test (`smoketest.sh`) for end-to-end sanity checks
- Coverage reporting via `make coverage`
