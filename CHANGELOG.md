# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
