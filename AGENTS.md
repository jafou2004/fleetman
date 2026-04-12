# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Shell tooling to manage a fleet of remote servers: synchronize bash configuration, deploy git repositories, and operate Docker containers — all via SSH with a single shared password (`sshpass`).

## Deployment Model

- **"Master" server**: files are deployed manually on one server, then propagated (with `fleetman sync`)
- **Target fleet**: N servers across X environments, listed in `config.json`
- The local server is detected dynamically via `hostname -f` (`$MASTER_HOST`) — it is handled locally (no SSH to self); any server in the fleet can act as the execution point
- `sudo` is available on all servers; password is shared between SSH auth and sudo (`sudo -S`)

## File Structure

**Note**: The active codebase uses the structure below.

| File/Dir | Role |
|----------|------|
| `scripts/bin/fleetman` | CLI entry point (no `.sh` extension) — reads `internal/VERSION` → `_CLI_VERSION` global; intercepts `-v`/`--version`; sources `internal/cli.sh`; calls `cli_dispatch` |
| `scripts/internal/cli.sh` | Auto-discovering dispatcher: builds `cmd_<verb>[_<sub>...]` from positional args, loads matching file from `commands/`, calls the function; `_cli_extract_tag`/`_cli_scan_menu_dir` for dynamic interactive menus; `_cli_extract_desc`/`_cli_cmd_help` skip `# @tag` lines |
| `install.sh` | One-time fleet init at project root — NOT routed via cli_dispatch; run directly (`bash ~/fleetman/install.sh` or `curl | bash`); re-run prompts before overwriting (default N/abort) |
| `scripts/internal/uninstall.sh` | Removes fleet management tooling from all servers — NOT routed via cli_dispatch, run directly (`bash ~/scripts/internal/uninstall.sh [-h]`); triple confirmation required |
| `scripts/internal/welcome.sh` | Welcome screen on SSH login — run directly from `.bashrc` (TTY guard); only sources `lib/vars.sh`; `_LOADAVG_FILE`/`_OSRELEASE_FILE` injectable for tests |
| `scripts/internal/completion.sh` | Bash completion — `_fleetman_completions` + `_fleetman_opts_from_file`; sourced from `~/.bashrc` by `fleetman sync`; no lib dependencies, no `main()`, no main guard |
| `scripts/internal/VERSION` | Plain text version number (e.g. `1.0.0`); read by `scripts/bin/fleetman` as `_CLI_VERSION` global |
| `scripts/commands/` | Subcommand scripts — each exposes `cmd_<verb>()` functions; no main guard, no top-level executable code |
| `scripts/commands/pod/` | Pod sub-commands — each exposes `cmd_pod_<sub>()` functions; sourcing uses `../../lib` |
| `scripts/commands/pod/up.sh` | `cmd_pod_up` — starts a pod (`docker compose up -d`) across all servers hosting it; uses `find_and_select_pod` + `collect_pod_servers` + `iterate_pod_servers`; skips servers where pod directory is absent |
| `scripts/commands/pod/list.sh` | `cmd_pod_list` — lists pods from `pods.json`, filtered by `-p <search>` and/or `-e <env>`; purely local (no SSH) |
| `scripts/commands/pod/env/cp.sh` | `cmd_pod_env_cp` — propagates local `.env` to all servers hosting a pod; applies per-server template substitution for variables in `config.json .pods.<pod>.env_templates`; uses `_build_sed_cmds` + `_substitute` with built-in tokens (`{hostname}`, `{short}`, `{env}`, `{pod}`, `{name}`, `{num}`, `{suffix}`) and custom tokens from `template_vars`; all tokens support 3 case variants: `{foo}` lower, `{FOO}` upper, `{Foo}` title |
| `scripts/commands/pod/env/diff.sh` | `cmd_pod_env_diff` — compares `.env-dist` vs `.env` for a pod on a single chosen server; reports missing/extra variables and offers to sync them; template-aware: variables in `config.json .pods.<pod>.env_templates` are added with their computed per-server value via `lib/templates.sh`; three modes: Mode A (`-p <pod>`, fleet lookup + server menu if multiple), Mode B (current dir has `.env-dist` or `.env`), Mode C (error); directional command — does NOT use `iterate_pod_servers` |
| `scripts/commands/pod/env/edit.sh` | `cmd_pod_env_edit` — edits the `.env` of a selected pod locally via `$EDITOR` (fallback: `nano`); for remote pods, fetches via SCP, opens tmpfile in editor, pushes back if md5sum differs; `-p <pod>` required; warns about `env_templates`-managed variables before opening; directional command — does NOT use `iterate_pod_servers` |
| `scripts/commands/pod/update.sh` | `cmd_pod_update` — prompts for new `.env` values per `config.json .pods.<pod>.env_vars`, applies changes on all hosting servers, re-applies `env_templates` per-server via `lib/templates.sh`, restarts with `docker compose up -d`; uses `find_and_select_pod` + `collect_pod_servers` + `iterate_pod_servers` |
| `scripts/commands/selfupdate.sh` | `cmd_selfupdate` — finds git clone server (`_find_git_server` scans the fleet if cache absent or stale), git pull/checkout (tags/commits/branch/pin), runs migrations, triggers `sync --quick` |
| `scripts/commands/status.sh` | `cmd_status` — checks fleet health: SSH reachability, Docker daemon, and containers listed in `config.json status_checks.containers`; uses `iterate_servers` + `[ "$failure_count" -eq 0 ]` |
| `scripts/commands/sudo.sh` | `cmd_sudo` — runs a command with sudo using the stored fleet password (silent decrypt via `ask_password`); usage: `fleetman sudo -- <cmd> [args...]` |
| `scripts/commands/sync.sh` | `cmd_sync` — Phase 1: braille ASCII art + pod collection → `pods.json`; Phase 2: replicate scripts/, `.bash_aliases`, `config.json`, `.data/` to fleet; writes `.data/fqdn` locally in `sync_local`, then SSH `hostname -f > ~/.data/fqdn` in `sync_remote` after copying `.data/` |
| `scripts/commands/config.sh` | `cmd_config` — interactive menu for editing `config.json` fields; auto-discovers sub-commands via `_cli_scan_menu_dir`; lazily sources selected file only (allows mocking in tests) |
| `scripts/commands/config/parallel.sh` | `cmd_config_parallel` — reads/updates `config.json .parallel` (parallel SSH jobs); validates positive integer; atomic write via `mktemp`+`mv` |
| `scripts/commands/config/env.sh` | `cmd_config_env` — interactive menu dispatching `config/env/*.sh` sub-commands via `_cli_scan_menu_dir`; lazily sources selected file |
| `scripts/commands/config/env/add.sh` | `cmd_config_env_add` — adds a new environment to `config.json` (`.env_colors` + `.servers`); prompts for name + color picker; sync confirm |
| `scripts/commands/config/env/color.sh` | `cmd_config_env_color` — changes the color of an existing environment; menu 1: env selection (bg-colored labels); menu 2: color picker (bg-colored, preselects current color via index lookup in `COLOR_NAMES`); atomic write to `.env_colors`; sync confirm |
| `scripts/commands/config/server.sh` | `cmd_config_server` — interactive menu dispatching `config/server/*.sh` sub-commands via `_cli_dispatch_submenu`; `@order 5` in config menu |
| `scripts/commands/config/server/add.sh` | `cmd_config_server_add` — adds a new server FQDN to `config.json .servers[$env]`; selects env via colored menu; validates FQDN (regex, re-prompt loop) and checks for global duplicates across all envs; always bootstraps the new server via `_bootstrap_key`: decrypts fleet password, runs `ssh-copy-id`, verifies key auth, launches `fleetman sync` |
| `run_migrations.sh` | Standalone migration runner (project root, git clone server only) — `main <old_ver> <new_ver>`; finds `migrations/vX.Y.Z.sh` in `]old, new]` window; `main()` pattern with main guard; NOT synced to fleet servers |
| `migrations/` | Migration scripts (project root, git clone server only) — `vX.Y.Z.sh` naming; sourced with TTY (locally or via `ssh -t`); can source `../scripts/lib/`; NOT synced to fleet servers |
| `smoketest.sh` | Hybrid smoke test (project root, git clone server only) — runs read-only CLI commands automatically + prints manual checklist; NOT synced to fleet servers |
| `scripts/lib/vars.sh` | Global variables: colors (`GREEN/RED/YELLOW/BLUE/CYAN/NC`), `CONFIG_FILE`, `MASTER_HOST` (read from `~/.data/fqdn` if present, otherwise `hostname -f` as fallback), `FLEET_KEY`, `FLEET_PASS_FILE`, `DATA_DIR`, `PODS_FILE`, `PODS_DIR`, `SCRIPTS_DIR`, `USER_ALIASES_FILE` |
| `scripts/lib/display.sh` | `ok/err/warn/section/print_summary/short_name/compute_title` |
| `scripts/lib/auth.sh` | `require_cmd/sudo_run/check_sshpass/ask_password/ssh_cmd/scp_cmd/rsync_cmd/encrypt_password/prompt_pass_and_encrypt` |
| `scripts/lib/config.sh` | `check_config_file/parse_env/env_label/parse_search_env_opts/check_pods_file/validate_env_filter/collect_server_pods/find_and_select_pod/collect_pod_servers` |
| `scripts/lib/ui.sh` | `prompt_response/select_menu/build_server_labels/prompt_sync_confirm` |
| `scripts/lib/spinner.sh` | `_spin_start/_spin_stop` |
| `scripts/lib/iterate.sh` | `iterate_servers/_IS_*/append_result/iterate_pod_servers` |
| `scripts/lib/templates.sh` | Per-server `.env` template engine — `_parse_server_parts`, `_apply_var`, `_substitute`, `_build_sed_cmds`, `_apply_templates`, `_escape_for_sed`, `_get_env_for_server`; shared by `pod/env/cp.sh`, `pod/update.sh`, and `pod/env/diff.sh`; callers must set `TEMPLATES_JSON` + `TEMPLATE_VARS_JSON` + `SELECTED_POD` before calling; `_substitute` resolves object-form `template_vars` values env-aware (uses `has($env)` guard — not `//` — to avoid jq falsiness gotcha on `false`/`0` values) |
| `config.json` | Fleet configuration: `parallel`, `pods_dir`, `env_colors`, `status_checks`, `pods`, `servers` (gitignored — copy from `config.json.example`) |
| `~/.bash_aliases` | User alias file (not versioned, personal): synced from master to all servers by `fleetman sync`; created empty on first sync if absent |
| `.data/pods.json` | Generated — `{ "dev": { hostname: [pod, …] }, … }` produced by `fleetman sync` (gitignored) |
| `.data/welcome_<short>.ascii` | Generated — 2-line braille art per server, produced by `fleetman sync` Phase 1a (gitignored) |
| `.data/last_sync.txt` | Generated — date of last sync run (`YYYY-MM-DD HH:MM`), written by `fleetman sync` (gitignored) |
| `.data/fqdn` | Generated — FQDN of the current server, written by `sync_local` (master) and via SSH in `sync_remote` after copying `.data/` (each remote overwrites the master's FQDN copied by scp); read by `vars.sh` as `MASTER_HOST` cache to avoid `hostname -f` on every invocation (gitignored) |
| `.data/services.json` | Generated — `{ env: { server: { pod: [{"Service": "name"}, ...] } } }` produced by `fleetman sync -f` (Phase 1c); read by `pod/logs.sh` `-s` interactive menu; query: `jq '.[$e][$srv][$pod][].Service'`; gitignored |

## scripts/lib/ — Shared Library

Scripts source individual lib files instead of a monolithic `_common.sh`. Each lib sources its own dependencies; duplicate sourcing is safe because every lib opens with an idempotency guard: `[[ -n "${_FLEETMAN_<NAME>_LOADED:-}" ]] && return 0` / `_FLEETMAN_<NAME>_LOADED=1`. Add this guard to any new lib file — without it, `hostname -f` and `jq` in `vars.sh` are re-executed on every transitive source (8× for a command sourcing 5 libs), causing multi-second delays.

Sourcing pattern from `scripts/commands/`:
```bash
_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
# ... only what's needed
```
From `scripts/commands/pod/` (one level deeper): use `../../lib`.
From `scripts/internal/`: use `../lib`.

Lib dependency chain: `vars.sh` ← `display.sh` ← `spinner.sh`, `auth.sh`, `config.sh`, `ui.sh` ← `iterate.sh`.

- **Variables** (`lib/vars.sh`): `CONFIG_FILE` (`$HOME/config.json`), `MASTER_HOST` (local server hostname, detected via `hostname -f`), `DATA_DIR` (`$HOME/.data`), `PODS_FILE`, `PODS_DIR` (pod root dir, from `config.json .pods_dir`), `FLEET_KEY` (`~/.ssh/fleet_key`), `FLEET_PASS_FILE` (`~/.fleet_pass.enc`), `SCRIPTS_DIR` (`$HOME/scripts`), `USER_ALIASES_FILE` (`$HOME/.bash_aliases`), `GIT_SERVER_FILE` (`$DATA_DIR/git_server`) — FQDN of the server holding the git clone; written by `sync_local` when `.git` is present; read by `selfupdate` (Case 2), `autosync`, and `status`. Colors: `GREEN`, `RED`, `YELLOW`, `BLUE`, `CYAN`, `NC`. Use `$DATA_DIR`/`$PODS_FILE` everywhere in local scripts — never hardcode `$HOME/.data`. Exception: remote SCP destinations (`"$server:~/.data"`) and crontab entry strings use `~/.data` because `DATA_DIR` is a local variable.
- **`require_cmd <cmd>`** — exits with `err` if a binary is not in PATH; used by `check_sshpass` and `install.sh`. Note: the `curl-pipe-bash` bootstrap block in `install.sh` (before lib sourcing) cannot use it — that block uses a raw `command -v` loop.
- **`check_sshpass()`** / **`check_config_file()`** — prerequisite guards; `check_sshpass` is a no-op if `FLEET_KEY` exists, otherwise calls `require_cmd sshpass`; `check_config_file` emits `warn` (⚠) — not `err` (✗) — when absent; test assertions must use `⚠`
- **`parse_env <arg>`** — validates `$arg` against the keys of `config.json` `.servers`, sets global `$ENV`; if empty, sets `ENV=""` (all servers). Exits on invalid value. Must be called after `check_config_file`.
- **`env_label([env])`** — returns the env in uppercase, or `"ALL"` if empty; no arg → uses global `$ENV` (set by `parse_env`); with arg → uses that value, e.g. `env_label "$ENV_FILTER"` for scripts using `collect_server_pods`. Uses `${1-$ENV}` (not `:-`) so an explicit empty string `""` is valid and returns `"ALL"`
- **`prompt_response <question> [default]`** — prompts user, loops until non-empty; prompt text goes to **stderr**, answer to **stdout** — capture cleanly with `var=$(prompt_response ...)`. In bats tests, `run func <<< 'value'` feeds stdin correctly; no mock needed.

**Bats `run` creates a subshell — global mutations don't propagate**: `run func` captures output but any `_VAR=$((...))` mutations inside the function are lost. To test counter increments, call the function directly (without `run`); use `run` only to capture stdout/status. Separate tests as needed: one for output (`run func; [[ "$output" == *"✓"* ]]`), one for counters (`func; [ "$_PASS" -eq 1 ]`).

**`BASH_SOURCE[0]` is empty inside bats `run` subshells**: `${BASH_SOURCE[0]}` does not track the source file when a function runs in a bats `run` subshell — it resolves to empty, making `$(dirname "${BASH_SOURCE[0]}")` useless for locating sibling scripts. Use `$SCRIPTS_DIR` instead (e.g. `"$SCRIPTS_DIR/bin/fleetman"`) — it is set by `vars.sh` and overridden to the real path in test `load_common`.

**`set -e` + non-zero exit capture in bats**: under `set -e` (bats default), a failing command inside a function exits the function immediately before `_rc=$?` can capture it. Pattern: `cmd && _rc=0 || _rc=$?` — the `||` arm runs even under `set -e`, capturing the real exit code. Applied in `_st_run_test` in `smoketest.sh`.
- **`ask_password()`** — if `FLEET_KEY` + `FLEET_PASS_FILE` exist, decrypts password silently with `openssl pkeyutl` (no prompt); otherwise falls back to interactive prompt. Stores in `$PASSWORD` and `$B64_PASS`.
- **`sudo_run <cmd>`** — runs `cmd` with `sudo -S`, feeding `$PASSWORD` via stdin; only for local execution
- **`ssh_cmd <server> <args…>`** — uses `ssh -i FLEET_KEY` if key exists, otherwise falls back to `sshpass`; passes `"$@"` directly so `ssh_cmd -t server cmd` allocates a pseudo-TTY (used by `selfupdate` for interactive migrations on remote clones)
- **`scp_cmd <src> <dst>`** — uses `scp -i FLEET_KEY` if key exists, otherwise falls back to `sshpass`
- **`rsync_cmd [opts] <src> <dst>`** — uses `rsync -e "ssh -i FLEET_KEY ..."` if key exists, otherwise `-e "sshpass -p ... ssh ..."`; mirrors `scp_cmd` auth pattern; used by `sync_remote` for delta replication
- **`is_local_server <fqdn>`** — returns 0 if `<fqdn>` is the local server (exact FQDN match or short-name match against `$MASTER_HOST`); use instead of inline `[ "$server" = "$MASTER_HOST" ]` checks — short-name comparison handles cases where pods.json stores short names. Defined in `lib/auth.sh`.
- **`short_name <fqdn>`** — keeps only the part before the first `.`: `server1.example.com` → `server1`
- **`env_color_ansi <name> <fg|bg>`** — maps a color name (`green`, `yellow`, `red`, `grey`, `blue`, `purple`, `cyan`, `white`, `black`) to its ANSI escape literal as a `printf '%s'` string (e.g. `'\033[1;32m'`); `fg` = text color, `bg` = background; unknown name → `'\033[0m'`; used by `welcome.sh`, `commands/config/env/add.sh`, and `commands/config/env/color.sh`
- **`ok <msg>`** — `  ✓ msg` (green): operation success
- **`err <msg>`** — `  ✗ msg` (red): error or failure
- **`warn <msg>`** — `  ⚠ msg` (yellow): warning or skipped item
- **`section <title>`** — `=== title ===` (blue): section header; replaces all `echo -e "${...}=== ... ===${NC}"` in scripts
- **`_spin_start <short>`** — prints server name on current line and starts an animated spinner (background process, PID in `$_SPIN_PID`)
- **`_spin_stop <short> <ok|warn|err> <detail>`** — kills the spinner, overwrites the line with a colored `✓`/`⚠`/`✗` result; used directly in `synchronize.sh` phase 1
- **`select_menu <array_name>`** — arrow-key interactive menu; sets global `SELECTED_IDX`; shared by `pod/ssh.sh`, `pod/logs.sh`, `pod/pull.sh`, `pod/update.sh`, and `install.sh` wizard (color picker); `q`/Ctrl+C exits
- **`build_server_labels <labels_array_name>`** — fills a label array from `server_order` + `server_pods` globals (format: `"short_name  (pod1, pod2)"`); call after `collect_server_pods`. Used by `pod/ssh.sh`, `pod/logs.sh`.
- **`prompt_sync_confirm [mode]`** — prompts "Propager via fleetman sync ? [Y/n]", then calls `fleetman sync -q` (mode `"quick"`, default) or `fleetman sync` (mode `"full"`); used by `config/env/add.sh`, `config/env/color.sh`, `config/status.sh`, `config/parallel.sh`; config-only changes use quick, script changes use full. Mock in unit tests: `prompt_sync_confirm() { :; }` in `setup()`, override in specific sync tests.
- **`prompt_confirm <question>`** — prints `"  <question> [Y/n] "` to stdout, reads one line; returns 0 (yes) for Y/y/empty, 1 (no) for n/N; use instead of inline `read` + `[[ ! $answer =~ ^[nN] ]]` blocks. Defined in `lib/ui.sh`.
- **`compute_title <fqdn>`** — derives a human-readable title from a hostname: `server1-rec.abc.example.com` → `"Serveur Server 1 REC"`. Its FQDN-parsing algorithm is mirrored in `_parse_server_parts` in `pod/env/cp.sh`.
- **`parse_search_env_opts "$@" || true ; shift $((OPTIND - 1))`** — parses `-p:e:h`; sets globals `SEARCH` and `ENV_FILTER`. The `|| true` guards against non-zero return under `set -e` (getopts returns `$((OPTIND-1))` which is non-zero when flags are present); `OPTIND` remains valid after `|| true` so `shift $((OPTIND - 1))` is equivalent to the former `shift $?`. Used by all `pod/*.sh` except `pod/clone.sh` (has custom `-a` flag). **When a command needs extra flags** (e.g. `-n`, `-s`), skip this helper and write a manual `getopts ":p:e:n:s:"` loop (silent mode — leading `:`): set `OPTIND=1` before the loop, add `:)` case for missing-arg error, `\?)` for unknown option. See `pod/logs.sh`.
- **`check_pods_file()`** — exits if `$PODS_FILE` missing. Call in scripts that query pods.json directly without going through `find_and_select_pod` (which already checks it internally).
- **`validate_env_filter()`** — validates `$ENV_FILTER` against pods.json keys; no-op if empty. Call after `check_pods_file`. Used by `pod/list.sh`, `pod/ssh.sh`, `pod/logs.sh`.
- **`collect_pod_servers()`** — sets globals `pod_servers` (array of servers hosting `$SELECTED_POD`) and `_all` (`true`/`false`). Call after `find_and_select_pod` + `parse_env`. Used by `pod/pull.sh`, `pod/env/cp.sh`, `pod/start.sh`, `pod/update.sh`.
- **`collect_server_pods()`** — sets globals `server_pods` (assoc, server → space-sep pods) and `server_order`; uses `$SEARCH`/`$ENV_FILTER`. Does **not** call `parse_env`, so `$ENV` is never set — do not call `env_label()` (no-arg) after this function. For section headers use `label=$(env_label "$ENV_FILTER")`. Used by `pod/ssh.sh`, `pod/logs.sh`.
- **`find_and_select_pod <search> <env_filter> <menu_title>`** — validates search + pods.json + env_filter, collects matching pod names, shows interactive menu if multiple match; sets globals `SELECTED_POD` and `label`; exits on error or no match. Used by `pod/start.sh`, `pod/update.sh`, `pod/pull.sh`.
- **`_IS_sigint_handler()`** — `trap INT` handler inside `iterate_servers`: sets `_IS_stop_requested=1`, kills spinner and all background jobs, cleans tmpfiles. Triggered by Ctrl+C.
- **`_IS_parse_result <tmpfile> <exit_code>`** — parses function output from `tmpfile`, determines `_status`/`_detail` based on `✓`/`⚠`/`✗` markers and exit code, increments `success_count`/`warn_count`/`failure_count`. Uses `count=$(( count + 1 ))` (not `(( count++ ))`) to avoid exit 1 under `set -e`. Shared by `_IS_collect_result` (parallel) and `iterate_servers` (sequential).
- **`iterate_servers <local_fn> <remote_fn> [servers_var]`** — loops over hostnames of `$ENV` from `config.json`. Optional `servers_var` is the **name** of a bash array variable (e.g. `pod_servers`) — never pass a string label, it resolves to an empty array and skips all servers. Sequential mode (`parallel=1`): animated spinner per server + result line. Parallel mode (`parallel=N`): job pool of N background jobs, global progress line `[done/total active-servers…]`, results print on completion. **stdout and stderr of both functions are captured (hidden from the user)** — commands that need raw output visible (e.g. `exec`) must use a direct server loop instead. Updates globals `success_count`, `warn_count`, `failure_count`. Supports clean stop via Ctrl+C. Uses `_IS_draw_progress` / `_IS_parse_result` / `_IS_collect_result` helpers (defined in `lib/iterate.sh`). **`__APPEND` protocol**: parallel jobs cannot mutate parent-scope arrays; functions that do `arr+=("val")` must also `echo "__APPEND arr val"` so `_IS_collect_result` can replay the mutation in the parent scope
- **`print_summary`** — prints a compact color-coded summary line (`N ✓  N ⚠  N ✗`) from `success_count`/`warn_count`/`failure_count`; call after `iterate_servers`. **No arguments** — the old arch accepted a verb label; the new arch does not (passing one is silently ignored but wrong)
- **`iterate_servers` exit code**: `iterate_servers` always returns 0 (unless interrupted by Ctrl+C). Commands that should propagate failure must explicitly check `failure_count` after the call: `[ "$failure_count" -eq 0 ]` (clean one-liner) or `if [ "$failure_count" -gt 0 ]; then err "..."; return 1; fi` (when a descriptive error message is needed).
- **`append_result <array_name> <value>`** — appends `value` to the named array and emits `echo "__APPEND array_name value"`; use instead of the raw two-line pattern in `*_local`/`*_remote` functions. Used by `pod/start.sh`, `pod/update.sh`, `pod/clone.sh`.
- **Calling `*_local`/`*_remote` outside `iterate_servers`**: `append_result` emits `__APPEND` to stdout, which becomes visible noise. Capture output into a tmpfile, print non-`__APPEND` lines, and replay mutations: `while IFS= read -r _line; do if [[ "$_line" == "__APPEND "* ]]; then read -r _ _arr _val <<< "$_line"; eval "${_arr}+=(\"${_val}\")"; else echo "$_line"; fi; done < "$tmpfile"`. See `deploy_selective()` in `pod/clone.sh`.
- **`iterate_pod_servers <local_fn> <remote_fn>`** — calls `iterate_servers` with or without `pod_servers` depending on `$_all`; use after `collect_pod_servers` in pod scripts instead of the 4-line conditional. Used by `pod/start.sh`, `pod/pull.sh`, `pod/update.sh`, `pod/env/cp.sh`.
- **`lib/templates.sh`** — per-server template substitution engine; sourced by `pod/env/cp.sh`, `pod/update.sh`, and `pod/env/diff.sh`. Globals set by the lib: `_TP_NAME/_TP_NUM/_TP_SUFFIX/_RESULT/SED_CMDS`. Call `load_pod_templates <pod>` (also in `lib/templates.sh`) to populate `TEMPLATES_JSON` and `TEMPLATE_VARS_JSON` from `config.json` in one call — do not set them manually with inline `jq` calls. Key functions: `_build_sed_cmds(server)` → sets `$SED_CMDS` (semicolon-sep sed expression for all `env_templates`); `_apply_templates(server, env_file)` → wrapper calling `_build_sed_cmds` + `sed -i`; `_substitute(tmpl, hostname, short, env, pod)` → resolves all built-in + custom tokens with 3 case forms; `_escape_for_sed(val)` → escapes `\`, `|`, `&` for use as a sed `|`-delimited replacement (use wherever a value is embedded in a sed expression); `_get_env_for_server(fqdn)` → looks up `$PODS_FILE` to return the environment name for a server FQDN. Sources `display.sh` (for `short_name`). `env_vars` and `env_templates` are disjoint — a variable cannot appear in both.

`alias.sh` only uses `lib/vars.sh` for color variables — it needs no SSH, password, or server iteration.

## Versioning Convention

`scripts/internal/VERSION` always carries a `-dev` suffix during development (e.g. `0.0.1-dev`). The `release.yml` workflow strips the suffix to produce the release tag, then bumps to the next patch `-dev` version. Never commit a plain version number to `main` — it must always end in `-dev` except on the release commit itself (created automatically by `release.yml`).

## Key Patterns

**Path from `scripts/internal/` to `scripts/bin/`**: one level up — `"$(dirname "${BASH_SOURCE[0]}")/../bin/fleetman"`. Using `../../` would escape `scripts/` entirely and point to a non-existent path.

**`commands/*.sh` are function-only**: never run `bash scripts/commands/sync.sh` directly — these files expose only `cmd_*()` functions with no top-level code. Always invoke via the dispatcher: `bash scripts/bin/fleetman <verb>`.

**curl-pipe-bash bootstrap** (`install.sh`): detect pipe execution with `[[ ! -f "$0" ]]` (`$0` is `bash` when piped from stdin, a real path otherwise). Clone repo, then resolve and checkout the latest semver tag via `git -C "$_PROJECT_DIR" tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -1` (mirrors `selfupdate` default `track="tags"`); falls back to default branch with `⚠` if no tag exists. Then create symlink `~/scripts → ~/fleetman/scripts/`, then `exec bash "$_PROJECT_DIR/install.sh" "$@"` to re-exec from the real file — required so lib sourcing with `${BASH_SOURCE[0]}` works normally.

**Script structure**: All scripts follow the Google Shell Style Guide `main()` pattern — shebang + header comment, lib sourcing block, all function definitions at top level, then `main() { ... }` containing all executable code, ending with `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`. Verify syntax with `bash -n scripts/<path>.sh`.

**Non-interactive mode detection**: use `[[ -t 0 ]]` (stdin is a terminal) instead of `[[ -n "$PS1" ]]` to condition interactive prompts (`read -rp`, `select_menu`). `$PS1` can be unset in a real interactive session; `[[ -t 0 ]]` is robust (except in pipe: `cmd | tee`). Applied in `collect_all_pods` for `check_all_servers_flag`.

**Google Shell Style compliance**: Key rules in force — (1) `err()`/`warn()`/`ok()` write to **stdout** by design: `iterate_servers` captures stdout to detect `✗`/`⚠`/`✓` markers; redirecting to stderr would break fleet iteration. (2) Always declare `local` for function-local variables, separate from command substitution: `local result; result=$(cmd)` not `local result=$(cmd)`. (3) Variable naming: function-local variables must be **lowercase** (`local pub_pem`, `local check_containers`); script-level globals shared between functions must be **uppercase** (`PODS_DATA`, `TITLE_VAR`, `SED_CMDS`). (4) Always use `read -r` (or `read -rs` for silent); omitting `-r` causes backslash interpretation. (5) Avoid bare `$?` checks; prefer `if ! cmd; then` or capture the exit code immediately: `_rc=$?` with no intervening command. (6) **Optional-arg functions**: use `${1-$DEFAULT}` (not `${1:-$DEFAULT}`) when an explicit empty string should be valid — `:-` substitutes the default on both unset and empty; `-` substitutes only when unset. Applied in `env_label`. (7) **`IFS=$'\t' read` collapses consecutive tabs**: tab is a whitespace IFS char in bash, so `field\t\tfield` yields 2 fields (empty middle field silently dropped). When parsing tab-delimited data with potentially empty fields, use `mapfile -t _f < <(printf '%s\n' "$str" | tr '\t' '\n')` instead. (8) **`${var:----}` is `---`, not `—`**: the default in `${var:-default}` written as `----` is three hyphens, not an em dash. Write `${var:-—}` explicitly when the em dash character is needed. (9) **ANSI codes break `printf %-Ns` alignment**: color escape sequences add invisible bytes that `printf` counts as column width, misaligning fixed-width columns. Place color codes outside the format spec and add manual padding: `printf "${COLOR}%s${NC}%*s" "$text" "$pad" ""` where `pad=$(( col_width - ${#text} ))`. (10) **Global boolean variables**: initialize with `VAR=false`, test with `[ "$VAR" != "true" ]` or `[ "$VAR" = "true" ]`. Avoid `if ! $VAR` / `if $VAR` (valid bash but triggers shellcheck SC2294 "Instead of running variable as a command, expand it explicitly"). Applied via `QUICK_MODE` in `sync.sh`. (11) **Script-level globals for shared arrays**: declare associative and indexed arrays at script level before `main()` — `declare -A map=()` / `arr=()`. Inside functions, reset them with a plain `map=()` / `arr=()` assignment rather than re-declaring. `declare -gA` inside a function is legal but error-prone under `set -e` and harder to grep; script-level declaration is the preferred pattern.

**config.json format**: top-level object with:
- `pods_dir`: string — base directory for pod deployments on all servers; exposed as `$PODS_DIR` in all scripts
- `parallel`: integer — number of concurrent jobs in `iterate_servers` (default: 1 = sequential)
- `env_colors`: object mapping env name to color name (`"green"`, `"yellow"`, `"red"`, `"grey"`, `"blue"`, `"purple"`, `"cyan"`, `"white"`, `white`) — used by `scripts/internal/welcome.sh`; contrast rule: dark text (`\033[0;30m`) on light bg (grey/cyan/white), white bold text (`\033[1;37m`) on dark bg (blue/purple)
- `status_checks`: object `{ "containers": ["serviceA", …], "wud_port": N }` — container names checked by `status.sh` and `scripts/internal/welcome.sh`; optional `wud_port` enables WUD update-available indicator (`⬆`) in `scripts/internal/welcome.sh` via `GET http://localhost:{wud_port}/api/containers`
- `template_vars`: root-level object (optional) — tokens available in all `env_templates`. Values can be a string (same for all envs) or an object with env-specific keys + `"*"` as fallback (e.g. `{ "company": "ACME", "region": { "*": "EU", "dev": "EU-DEV" } }`). The two forms are equivalent: `"ACME"` ↔ `{ "*": "ACME" }`. Resolution in `_substitute`: exact env key wins, then `"*"`, then token left intact.
- `pods`: object mapping pod names to config — `{ "pod-name": { "env_vars": ["VAR1", …], "env_templates": { "VAR": "template" } } }` — `env_vars` used by `pod/update.sh` (auto-added empty on first run); `env_templates` optional, used by `pod/env/cp.sh` for per-server substitution (replaces deprecated `server_title_var`)
- `pods_ignore`: array of PCRE regex strings (optional) — pod names matching any regex are excluded from `pods.json` during `fleetman sync` Phase 1b; applied in `collect_env()` via `jq test()`; absent or `[]` = no filtering
- `selfupdate`: object (optional) — `{ "track": "tags"|"commits"|"branch", "branch": "main", "pin": "vX.Y.Z" }` — `track` defaults to `"tags"` (latest semver tag via `git checkout`); `"commits"` pulls upstream of current branch; `"branch"` tracks a named branch (`branch` field, default `"main"`); `pin` targets a specific version and overrides `track`
- `welcome`: object (optional) — `{ "enabled": true, "show_pods": true, "show_os": true, "show_docker": true }` — all flags default to `true` when absent; `enabled: false` causes `fleetman sync` to remove the welcome block from `.bashrc`; the other flags control `render()` column layout in `welcome.sh` (single-column or header-only when sections are disabled)
- `servers`: object with keys `dev`, `test`, `prod` (arrays of FQDNs, no `user@`)

`jq` query patterns for env iteration:
- Single env: `.servers[$env] | .[]`
- All envs (servers): `.servers[] | .[]`
- All env names: `.servers | keys[]`
- Env validation: `.servers | has($env)`

**jq boolean gotcha**: `jq`'s alternative operator `//` treats `false` as falsy — `.key // true` returns `true` even when `.key` is the boolean `false`. For boolean config flags, use `if .key == false then "false" else "true" end` (handles absent key as `true` correctly).

**`jq // empty` vs `// {}`**: use `// empty` (not `// {}`) to handle absent/null JSON keys that feed into `[ -n ]` checks. `// {}` always returns the literal string `{}` for absent keys — `[ -n "$var" ]` always succeeds and triggers template logic incorrectly. `// empty` returns an empty string — `[ -n "$var" ]` correctly reports absence. Applied in `load_pod_templates` and throughout `pod/env/*.sh`.

**pods.json format**: `{ "dev": { "hostname": ["pod-a", "pod-b"] }, "test": {…}, "prod": {…} }`. Grouped by environment to allow partial updates. Query example — find servers hosting a given pod across all envs:
```bash
jq -r --arg pod "service-docker" '.[] | to_entries[] | select(.value[] == $pod) | .key' .data/pods.json
```

**Long flags (`--flag`) pre-scan**: `getopts` doesn't handle long options. Pre-scan `"$@"` manually before calling `getopts`, filter out long flags, then `set -- "${_filtered_args[@]}"`. Used in `pod/clone.sh` for `--all`.

**Optional-arg short flag pre-scan**: When a short flag takes an optional value (getopts can't do this), pre-scan `"$@"` before `getopts`: iterate with `${!_idx}`, if the flag's next arg is empty or starts with `-`, set a boolean (`SELECT_SERVICE=true`) and skip adding the bare flag to `_new_args`; if a value follows, push both `"-s" "$_next"` and advance `_idx`. Then `set -- "${_new_args[@]}"` before `getopts`. Applied in `pod/logs.sh` for `-s [service]`.

**`install.sh` wizard ordering**: the config wizard in `install.sh` runs *before* `check_config_file` (it creates the file). If `config.json` already exists, `main()` prompts before overwriting (default N/abort) — then re-runs the full wizard + key generation. Never move `check_config_file` before the wizard gate.

**Named parameters**: all scripts use `getopts` for flag-based argument parsing. `-p <pod>` provides the pod search term; `-e <env>` provides the optional environment filter. Scripts that accept only an environment use `-e` only (e.g. `status`, `pod/clone.sh`). `exec.sh` keeps the command as a positional argument (`$1` after `shift`) and uses `-e` for the environment. `alias.sh` uses `-c <category>` for optional category prefix filter (case-insensitive prefix match). `pod/env/diff.sh` accepts both `-p` and `-e` as fully optional (mode depends on whether `-p` is given). `sync` and `selfupdate` do **not** accept `-e` — they always operate on all servers. All scripts also support `-h` which calls a `help()` function and exits. The standard call order is: parse flags with `getopts` → `check_sshpass` → `check_config_file` → `parse_env "$ENV_FILTER"` → `ask_password`.

**Alias files**: No versioned repo aliases file. `~/.bash_aliases` (not in git) is the single personal aliases file — same content on all servers, synced by `fleetman sync` from the master. Created empty on first sync if absent. `fleetman sync` adds blocks to `.bashrc` idempotently: `export PATH="$HOME/scripts/bin:$PATH"` (makes `fleetman` available everywhere), sourcing block for `~/.bash_aliases`, welcome screen guard, and completion sourcing. **Extending sync's `.bashrc` blocks**: add a sentinel-based block in both `sync_local()` (local `grep -qF` guard + `{ echo ... } >> ~/.bashrc`) and the `'ENDSSH'` heredoc in `sync_remote()` (same guard + `echo "X_ADDED"` to stdout). Parse sentinels from `$result` with `grep -q "^X_ADDED$"` to print ok/already-present messages.

**`lib/` scope**: `lib/` contains only genuinely reusable cross-command utilities. Command-specific logic (e.g. braille rendering, pod collection in `sync.sh`) stays in `commands/<name>.sh`, even if that makes the file larger. Never create `lib/<command>.sh` for logic used by only one command.

**`commands/*.sh` convention**: expose only `cmd_*()` functions — no `main()`, no top-level executable code, no main guard. The dispatcher calls `cmd_<verb>()` directly.

**Command docblock (help system)**: every `scripts/commands/**/*.sh` must open with a `##`-delimited docblock. The dispatcher reads it for `-h`/`--help` — **no `help()` function, no `h` in getopts**. Regular `# ` comments outside `##` are developer notes and do NOT appear in help. First non-`@tag` content line = short description shown in `fleetman -h` listing. Sub-commands that appear in a parent interactive menu must also include `# @menu <label>` and `# @order <N>` at the top of the docblock — `_cli_extract_desc` and `_cli_cmd_help` skip `# @*` lines so they don't leak into help output. **`@order` values must be unique within a directory** — a collision shifts all subsequent menu indices, breaking `SELECTED_IDX` assertions in `tests/unit/commands/config.bats`. Current `config/` order: parallel=1, status=2, podsignore=3, autosync=4, env=5, server=6, templatevars=7, welcome=8, basefolder=9, selfupdate=10, pod=11, updatepassword=12.
```bash
##
# @menu Short menu label
# @order 1
#
# Short description shown in fleetman -h.
#
# Usage: fleetman <verb> [options]
#
# Options:
#   -h, --help   Show this help
##
```

**CLI dispatcher** (`scripts/internal/cli.sh`): `cli_dispatch <commands_dir> [args...]` auto-discovers commands — no case statements, no registration. Converts positional args progressively into a function name (`fleetman pod pull -p foo` → `cmd_pod_pull`), attempts to load `commands/pod/pull.sh` then `commands/pod.sh` as fallback, then calls `cmd_pod_pull -p foo`. Stops arg scan at first flag. **Positional args gotcha**: every positional arg after the verb is consumed as a sub-command candidate — commands that need an optional user-provided value must use a flag (e.g. `-c git`), never a bare positional arg. **`--` separator for pass-through commands**: when a command must pass arbitrary positional args to another program (e.g. a sudo/exec wrapper), use `--` as separator: `fleetman sudo -- whoami`. The dispatcher stops scanning at `--` (it starts with `-`). In the command function, manually consume the `--` after getopts: `[[ "${1:-}" == "--" ]] && shift` — getopts does NOT advance `OPTIND` past `--`, so `shift $((OPTIND-1))` leaves it in `$@`. **Automatically intercepts `-h`/`--help`** before calling any command function: reads the `##` docblock from the loaded source file via `_cli_cmd_help`; if a sibling directory `<verb>/` exists next to the file, `_cli_cmd_help` also appends an auto-generated "Available subcommands:" section — do NOT include a hardcoded "Subcommands:" block in parent command docblocks. For verb groups with no parent `.sh` (e.g. `fleetman pod -h`), auto-lists `commands/pod/*.sh`. `_CLI_LOADED_FILE` global tracks the last sourced file. `_CLI_VERSION` global (set in `scripts/bin/fleetman` from `internal/VERSION`, read by `_cli_help`) drives the version header in `fleetman -h`; `-v`/`--version` are intercepted in `fleetman` before `cli_dispatch`.

**Adding a new command**: create `scripts/commands/<name>.sh` exposing `cmd_<name>()` with a `##` docblock. For sub-commands: `scripts/commands/pod/pull.sh` with `cmd_pod_pull()`. No changes to `cli.sh` needed. For a verb group (e.g. `pod`), create only `commands/pod/*.sh` — no `commands/pod.sh` needed; `fleetman pod -h` auto-lists from the directory.

**Sub-command filenames must not contain underscores**: `_cli_try_load` converts `cmd_config_foo_bar` → `commands/config/foo/bar.sh` (all `_` → `/`). Files in `commands/<verb>/` must be named without underscores (e.g. `basefolder.sh`, not `base_folder.sh`). The bash function name is unconstrained. This rule applies to **all** sub-commands including menu-driven ones — integration tests use direct CLI dispatch (`fleetman config podsignore`), which triggers `_cli_try_load`. Do NOT follow this pattern for new commands.

**Parent command that dispatches to sub-commands** (e.g. `fleetman config`): create both `commands/config.sh` (with `cmd_config()`) AND `commands/config/*.sh`. The dispatcher loads only ONE file per invocation — it does NOT load both `config.sh` and `config/parallel.sh` when `fleetman config parallel` is run. `cmd_config()` calls `_cli_dispatch_submenu "$_CMD_DIR" "$_COMMANDS_DIR"` (defined in `internal/cli.sh`, available without additional `source`): it scans `_CMD_DIR` for `@menu`/`@order` sub-commands, shows `select_menu`, then lazily sources and calls the selected function. The function name is derived from the path relative to `_COMMANDS_DIR` (`commands/`): `config/parallel.sh` → `cmd_config_parallel`. **Nested dispatcher** (e.g. `commands/config/env.sh` dispatching `commands/config/env/*.sh`, or `commands/pod/env.sh` dispatching `commands/pod/env/*.sh`): `_COMMANDS_DIR` must point to the `commands/` root — use `$(dirname "$(dirname "${BASH_SOURCE[0]}")")` (double dirname). A single `dirname` stops at `commands/config/` or `commands/pod/`, so fn reconstruction produces `cmd_env_add` instead of `cmd_config_env_add`, or `cmd_env_cp` instead of `cmd_pod_env_cp`.

**install.sh is not a command**: lives in `scripts/internal/`, run directly (`bash ~/scripts/internal/install.sh`), not through the dispatcher.

**Adding a new command**: for fleet-wide operations (same action on every server), define `cmd_<name>()` that calls `*_local()`/`*_remote()` + `iterate_servers`. For directional commands (find one specific server, act on it), use plain logic without `iterate_servers`.

**selfupdate — directional command pattern**: `cmd_selfupdate` does not use `iterate_servers` — it locates the single server holding the git clone and acts on it. Case 1 (local clone): calls `_update_*` locally then `$pdir/run_migrations.sh` + `fleetman sync`. Case 2 (remote clone): 3 separate SSH calls — heredoc (git update, captures `OLD_VER`/`NEW_VER`/marker), `ssh_cmd -t` (`$FLEETMAN_DIR/run_migrations.sh`, fully interactive), SSH (sync from git server).

**Detached HEAD after tag checkout**: `git checkout <tag>` leaves the repo in detached HEAD — `@{u}` is undefined, so `rev-list HEAD..@{u}` silently returns 0. Detect with `git symbolic-ref --quiet HEAD` (exit 1 = detached); checkout the configured branch before any pull. Applied in `_update_commits <pdir> <branch>`.

**`*_local`/`*_remote` naming**: prefix must match the command verb — `start_local`/`start_remote`, `pull_local`/`pull_remote`, etc.

**`echo ""`** after each `ok`/`warn`/`err` in `*_local`/`*_remote` functions: add an `echo ""` at the end of each branch (success, absent, failure) to separate display between servers. Consistent with `up.sh`.

**`absent=()` in `up.sh`**: `up_local`/`up_remote` call `append_result absent` but the array is never read after `iterate_pod_servers`. Do not copy this pattern in new commands (YAGNI) — the inline `warn` is sufficient.

**sudo in local functions**: use `sudo_run <cmd>`.

**sudo in remote heredocs**: `sudo_run` is not available on remote servers — use `echo "$B64_PASS" | base64 -d | sudo -S <cmd> >/dev/null 2>&1` inside the heredoc. `$B64_PASS` is set by `ask_password()` and is safe to embed because base64 output contains no shell-special characters.

**Heredoc variable expansion**: heredocs use unquoted `ENDSSH`, so local variables (`$B64_PASS`, `$POD_COMPOSE`, `$title`, etc.) expand before being sent to the remote server. Use `\$var` to defer expansion to the remote shell.

**JSON arbitrary in SSH heredoc**: to pass a JSON array/object to a remote script, encode locally with `pods_b64=$(printf '%s' "$json" | base64 | tr -d '\n')` and decode in the heredoc with `json=$(printf '%s' '${pods_b64}' | base64 -d)`. Extension of the `$B64_PASS` pattern — base64 only contains `[A-Za-z0-9+/=]`, safe in single-quotes in the heredoc.

**result=$() capture**: `result=$(ssh ... bash -s << ENDSSH ... ENDSSH)` captures all stdout. Docker commands must be redirected with `>/dev/null 2>&1` so only the explicit `echo "STATUS"` lines end up in `$result` for the `case` statement.

**`jq --argjson` ARG_MAX limit**: passing large JSON blobs via `--argjson var "$val"` becomes a shell argument — bash enforces `ARG_MAX` (~2 MB). On real fleets with many containers, `collect_services_env` produced an empty `services.json` with error `jq: Argument list too long`. Fix: pipe data via stdin with `printf '%s\n%s' "$json1" "$json2" | jq -sc '...'` instead of `--argjson`. Applied in `collect_services_env` in `sync.sh`.

**`jq` atomic write error guard**: bare `jq ... > "$tmp" && mv "$tmp" "$CONFIG_FILE"` silently reports success if `jq` fails. Use: `if ! jq --argjson v "$val" '...' "$CONFIG_FILE" > "$tmp" || ! mv "$tmp" "$CONFIG_FILE"; then rm -f "$tmp"; err "Failed to write config"; exit 1; fi`

**`jq --arg` for bash booleans**: to convert a bash string `"true"`/`"false"` to jq boolean, use `--arg v "$var"` then `($v == "true")` in the filter. Do not use `--argjson v "$var"` — this passes the jq boolean directly, making the comparison `$v == "true"` false (different types). Example: `jq --arg e "$enabled" '.welcome.enabled = ($e=="true")'`.

**Sed escaping for user-provided values**: embedding arbitrary values in sed replacement risks breaking the delimiter. Escape `|`, `\`, `&` first: `val_escaped=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/|/\\|/g; s/&/\\&/g')` — applied in `pod/update.sh` for `.env` variable updates.

**SIGTERM does not apply immediately to a bash subshell waiting for a child**: `kill $pid` sends SIGTERM, but if the subshell is in `waitpid()` for a child process (e.g. `docker ps` via `timeout`), bash defers the signal until the child finishes → `wait $pid` in the parent blocks as before. The "killer" pattern `( sleep N; kill $pid ) & ; wait $pid ; kill $killer ; wait $killer` fails twice: same problem for the killer (the killer subshell waits for `sleep N`). **Fix for bounded-duration background collections** (e.g. `welcome.sh docker`): do not use `wait` — write the result to a file via atomic write (`tmp` + `mv`), start the job in background before the foreground work, then check the file opportunistically without blocking (`kill $pid || true` then check `[ -f result ]`). The orphaned job terminates via its own internal `timeout`.

**Tmpfile-per-server for functions returning data via `iterate_servers`**: when `iterate_servers` needs to collect JSON per server (not just `✓`/`⚠`/`✗`), each `*_local`/`*_remote` writes its result to `$_TMP/<server_fqdn>.json` only on success. After `iterate_servers`, the parent iterates over the server list, reads present files and merges them. Missing file = failure = existing data preserved. Reference implementation: `collect_env`/`collect_services_env` in `sync.sh`. Do not modify `lib/iterate.sh` for this case.

## Testing

**Bats Core** is used for unit and integration tests (WSL or Docker):
- `bats --recursive tests/` — run all tests (requires `--recursive` for subdirectory discovery)
- `make test` / `make test-unit` / `make test-integration` — Docker-based equivalents
- `make coverage` — runs tests under **kcov** (`sudo apt install kcov`), outputs coverage HTML (`reports/coverage/`) **and** junit report (`reports/tests/`) in one pass; kcov correctly propagates bats exit code (exit 1 on failure)
- All `make test*` targets run parallel jobs (`BATS_JOBS`, auto-detected via `nproc`, default 4); parallelism is at the file level (36 files); override: `make test BATS_JOBS=1` to debug flaky tests serially
- CI triggers on `pull_request` (all branches) and `push` to `main` only — feature branch pushes without a PR do not trigger CI
- Migration scripts (`migrations/vX.Y.Z.sh`) do **not** have unit tests — they are one-shot; the runner (`run_migrations.sh`) and its window logic are already covered in `tests/unit/run_migrations.bats`.

**Test structure** (`tests/`) — to be rebuilt for new architecture:
- `test_helper/common.bash` — `load_common()` (unit tests): sets `HOME=$BATS_TEST_TMPDIR`, copies fixtures, sources lib files; `setup_fixtures()` (integration tests): same but does not source libs
- `fixtures/config.json` + `fixtures/pods.json` — fictitious fleet data (no real FQDNs); `config.json` is whitelisted in `.gitignore` via `!tests/fixtures/config.json`
- `unit/` — test individual lib functions; `load_common` in `setup()` sets up clean HOME + fixtures + sources all needed libs; then source the command under test: `source "$SCRIPTS_DIR/commands/pod/pull.sh"`
- `unit/commands/pod/` — unit tests for pod sub-commands; load path is `load '../../../test_helper/common'` (one extra `../` vs flat `unit/commands/`)
- `integration/pod/` — integration tests for pod sub-commands; load path is `load '../../test_helper/common'`
- `unit/auth.bats` — tests `ask_password`, `sudo_run`, `ssh_cmd`, `scp_cmd`; mocks `openssl`, `sudo`, `ssh`, `scp`, `sshpass` binaries
- `unit/ui.bats` — tests `prompt_response`, `prompt_sync_confirm`; `select_menu` is skipped (requires TTY arrow-key input)
- `unit/iterate.bats` — tests `_IS_list_servers`, `_IS_parse_result`, `iterate_servers` (sequential), `iterate_pod_servers`; mocks `_spin_start`/`_spin_stop` as no-ops
- `integration/` — invoke commands directly via `bash "$SCRIPTS_DIR/commands/pod/list.sh"`; no SSH needed

**Bats gotchas**:
- Bats runs tests with `set -e` — any non-zero return fails the test. `parse_search_env_opts` returns `$((OPTIND-1))` (the shift count), which is non-zero when flags are passed. Always call it with `|| true` in tests.
- `bats --filter` uses ERE (not POSIX grep) — `\|` is **not** the OR operator; use `|` or separate `--filter` calls. Ex: `--filter 'parse_args|-q'` works, `--filter 'parse_args\|-q'` matches nothing.
- Functions that modify globals (`parse_env`, `collect_pod_servers`…) must be called **without** `run` — `run` uses a subshell, so global mutations are invisible after the call.
- When a function both writes to stdout (e.g. `warn`) **and** mutates globals, call without `run` and redirect stdout to a file: `fn "arg" > "$BATS_TEST_TMPDIR/out.txt"`. Then `grep -q "pattern" out.txt` checks output while `[ "$GLOBAL" = "val" ]` checks the mutation — same process, no subshell.
- Overriding `CONFIG_FILE` or `PODS_FILE` inside a test: use `export VAR=...` so the subshell created by `run` inherits the new value.
- SC2030/SC2031 are disabled globally in `.shellcheckrc` — bats `@test` blocks are subshells by design; variable modifications inside tests are intentionally local.
- Requires `jq` in WSL (`sudo apt install jq`) — `lib/vars.sh` runs `jq` at source time; status 127 in `setup` means jq is missing.
- `(( n++ ))` when `n=0` returns exit 1 under `set -e`; wrap calls containing this pattern in `run` — filesystem writes inside `run` (fork) persist on disk and are checkable afterward.
- Counting mock function calls: use a tmpfile (`mock() { echo "X" >> "$BATS_TEST_TMPDIR/calls"; }; count=$(wc -l < "$BATS_TEST_TMPDIR/calls")`) — a local `(( counter++ ))` breaks under `set -e` when counter=0 and does not persist across `run` subshells.
- `getopts` stops at the first non-option argument; for scripts with mixed positional + flag args (e.g. `exec.sh`), put flags before the positional in tests: `exec.sh -e env cmd`, not `exec.sh cmd -e env`.
- `grep -c 'bash_aliases'` can match multiple lines; always use the most specific pattern in assertions (e.g. `'. ~/.bash_aliases'` for the sourcing block).
- `declare -gA assoc_array` is required when manually pre-populating associative globals like `server_pods` in tests; a plain assignment `server_pods["k"]="v"` creates a local indexed variable instead.
- **`jq keys[]` returns keys in alphabetical order**: when mocking `select_menu` with a fixed `SELECTED_IDX` targeting a specific env, calculate the alphabetical index (`dev=0, prod=1, test=2` in the fixture) — do not assume the declaration order in `config.json`.
- **Mock `select_menu` for multi-level navigation**: use a counter in the test body to vary `SELECTED_IDX` based on the call: `local _call=0; select_menu() { _call=$(( _call + 1 )); case "$_call" in 1) SELECTED_IDX=0 ;; 2) SELECTED_IDX=2 ;; esac; }`. Use `$(( _call + 1 ))` and not `(( _call++ ))` to avoid exit 1 under `set -e`.
- `cd` calls in functions under `set -e` require the target path to exist; override `PODS_DIR="$BATS_TEST_TMPDIR/pods"` and `mkdir -p` the required subdirectories before testing local-branch functions that call `cd "$PODS_DIR/$pod"`.
- **Test "local server only" (assert no ssh_cmd)**: use the `test` env (1 server in fixtures: `test1.fleet.test`) as `MASTER_HOST` — `dev` has 2 servers in `config.json` (dev1 + dev2), dev2 triggers SSH even if absent from `PODS_DATA`. The `collect_*_env` functions iterate over `CONFIG_FILE`, not `PODS_DATA`.
- **Normalize `docker compose ps --format json`**: produces JSON Lines (`{}\n{}`) before Compose 2.17, JSON Array (`[{}]`) after. Normalize: `jq -sc 'if length == 1 and (.[0] | type == "array") then .[0] else . end'`.
- Pod scripts using `collect_server_pods` have a testable "No results" path reachable without SSH: `bash pod/ssh.sh -p __no_such_pod__` exits 0 + "No results". Works for any script that calls `collect_server_pods` before `check_sshpass`.
- **Lazy SSH auth** (directional commands): only call `check_sshpass`/`ask_password` when remote servers are involved — loop `for server in "${server_order[@]}"; do [ "$server" != "$MASTER_HOST" ] && needs_ssh=true && break; done` before auth calls. Avoids prompting when only the local server is targeted. See `cmd_pod_ssh`. **Exception**: if the local branch calls `sudo_run` (which reads `$PASSWORD`), auth must be called unconditionally — the lazy optimization does not apply. See `pod/logs.sh`.
- **Optional trailing arg in docker commands**: use `${VAR:+ $VAR}` to append a value only when non-empty (e.g. `docker compose logs -f${SERVICE:+ $SERVICE}`). Expands to empty when `VAR=""`, to ` value` (leading space included) otherwise. Works in both local `sudo_run` calls and remote SSH strings (expansion happens in the local shell before the string is sent).
- **`var=$(cmd)` is exempt from `set -e`**: in bash, a command substitution assignment (`pods_raw=$(ssh_cmd ...)`) is never treated as an error even if the command fails — the return code is silently ignored. Use `if ! var=$(cmd); then ... return 1; fi` to capture both the output AND detect failure. Applied in `_collect_pods_server` and `_services_collect_job` in `sync.sh`.
- Always read existing `tests/integration/*.bats` files before creating a new one — some scripts (e.g. `alias.sh`) already have test files to augment rather than replace.
- **Integration tests with `bash -c` subshell** (`tests/integration/*.bats`): these tests source lib files inside a `bash -c` with a restricted PATH (`$BATS_TEST_TMPDIR/bin` + system). Any system binary called early (e.g. by `require_cmd` in a command's entry point) must be provided as a no-op mock in `setup()` — otherwise the subshell exits before the test's own function mocks take effect. Example: `printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/rsync"; chmod +x ...`.
- **`prompt_response` hangs on empty stdin**: integration tests that pass valid flags and reach `prompt_response` will hang forever with `< /dev/null` (the function loops until a non-empty response). Only test pre-prompt error paths (bad flags, invalid env) in integration tests; use unit tests with mocked `prompt_response` for post-prompt logic.
- **Mocking `prompt_response` for add-loops**: the standard setup mock `prompt_response() { echo "${_PROMPT_MOCK_VALUE:-$2}"; }` returns a single fixed value. For functions that call `prompt_response` in a loop (e.g. an "add" loop needing N values then `""` to exit), use a file-based sequence: `printf '%s\n' 'val1' '' > "$BATS_TEST_TMPDIR/pr_seq"; echo "0" > "$BATS_TEST_TMPDIR/pr_idx"; prompt_response() { local _i; _i=$(cat "$BATS_TEST_TMPDIR/pr_idx"); _i=$(( _i + 1 )); echo "$_i" > "$BATS_TEST_TMPDIR/pr_idx"; sed -n "${_i}p" "$BATS_TEST_TMPDIR/pr_seq"; }`. See `tests/unit/commands/config/podsignore.bats`.
- Bats intercepts stdin in `@test` blocks — file redirection (`func < file`) and heredocs do NOT feed stdin to functions using `read`. Workaround: use a custom fd (e.g. fd 9): `exec 9< "$file"`, override `prompt_response` to `read -r response <&9`, and call `_wizard_create_config <&9`. Close with `exec 9<&-`. See `tests/unit/install.bats` for the full pattern.
- When `_wizard_create_config` calls `select_menu` internally (color picker), mock it in the test body: `select_menu() { SELECTED_IDX=0; }`. Also remove the color text lines from the fd 9 input stream — they no longer exist after the switch to the interactive menu. The standard fd-9 `read` mock handles `-ra` with `shift 2` which consumes the varname, so `read -ra envs <<< "$envs_raw"` never populates the `envs` array — only assert on `status_checks`, `parallel`, `pods_dir`; not on `servers`.
- Adding a `read` call to `_wizard_create_config` breaks all existing fd-9 tests silently: the new `read` consumes the next line in the stream, shifting all subsequent inputs. Every existing test must have a `\n` inserted at the correct position in its `printf` input string.
- `install.sh` bootstrap block (`[[ ! -f "$0" ]]`) fires when `$0` is a bare word (e.g. `bash` in `bash -c`); in bats `$0=/usr/bin/bats` (a file), so the block is skipped. Never use `bash -c` to test install.sh functions — always `source` it from a bats test. This includes `run bash -c "source install.sh; func"` — the inner `bash -c` still sets `$0=bash`. Call the already-sourced function directly: `run func <<< 'input'`. **Exception — testing the bootstrap block itself**: use `bash -c "cat 'path/install.sh' | bash"` (inner bash reads from a pipe, `$0="bash"`, no function definitions embedded in the `-c` string). Capture the real path with `readlink -f "$SCRIPTS_DIR/..."` *before* any symlink manipulation.
- `load_common` creates `$HOME/scripts` as a symlink to the real scripts dir. Bootstrap tests that need `$HOME/scripts` as a real directory must first `rm -f "$HOME/scripts"` (`mkdir -p` on a symlink target doesn't convert it). After `rm`, `$SCRIPTS_DIR` resolves through the broken path — always save the canonical path with `readlink -f` beforehand.
- **Bootstrap test invocation — two styles**: (1) `run bash -c "cat install.sh | bash"` — bash reads the script character-by-character from stdin; safe only for tests that exit BEFORE any `read` call (dependency check, symlink-is-real-dir). (2) `run bash -c "$(cat install.sh)"` — content embedded as `-c` arg, stdin is empty so `read` gets EOF immediately → defaults used; required for tests that exercise the clone + tag-checkout path. Use an unquoted heredoc to create the git mock so `$fake_dir`/`$git_calls` expand from the test env while `\$*` stays literal; pre-create a stub `install.sh` in `$FLEETMAN_DIR` (just `exit 0`) to satisfy the final `exec bash "$_PROJECT_DIR/install.sh"`; `FLEETMAN_DIR` must NOT have `.git` so the clone path runs. **Git mock: use positional args (`$1`, `$3`) not `$*` patterns** — `$*` glob patterns like `*"clone"*` also match path substrings (e.g. `fresh_clone`), causing the clone branch to fire on tag calls too; use `[[ "$1" == "clone" ]]` for clone and `[[ "$1" == "-C" && "$3" == "tag" ]]` for tag commands instead.
- Sourcing `install.sh` in unit test `setup()` re-sources `vars.sh` which resets `SCRIPTS_DIR="$HOME/scripts"` (the tmpdir symlink). Same issue as the integration `setup()` note below, but applies to unit tests too — use `readlink -f "$SCRIPTS_DIR/..."` when the symlink may later be removed in the test.
- Overriding external commands (not builtins) as shell functions works in `run` subshells when exported: `func() { echo "CALLED:$*"; }; export -f func; run target_fn; unset -f func`. Works for `bash`, `dirname`, etc. to intercept calls from functions under test without creating mock binaries.
- Nested `bash -c` strings embedding function definitions with `()` cause "unexpected EOF while looking for matching `(`" parsing errors. Prefer direct function calls (already sourced in `setup()`) over complex `bash -c` wrappers.
- `run func <<< 'input'` passes stdin correctly to `read` inside the function; bats stdin interception only applies to direct calls (without `run`). Use this for single-step interactive reads. The fd-9 workaround is only needed when global mutations must be visible after the call (i.e., can't use `run`).
- **`read -rs` does not consume `<<<` input**: `run cmd <<< 'pass'` does NOT feed stdin to `read -rs` (silent/no-echo mode). Write input to a tmpfile and redirect: `printf 'pass\npass\n' > "$BATS_TEST_TMPDIR/input.txt"; run cmd_config_updatepassword < "$BATS_TEST_TMPDIR/input.txt"`. Applies to any command that uses `read -rs` for password prompts.
- Bash completion functions (`_fleetman_completions` etc.) can be tested directly: set `COMP_WORDS=("fleetman" "arg")`, `COMP_CWORD=N`, `COMPREPLY=()`, call the function (no `run` needed), then assert on `${COMPREPLY[*]}`. The function resolves `cmd_dir` from the first `fleetman` binary in `$PATH` — put the fake binary in `$BATS_TEST_TMPDIR/bin/` so `cmd_dir=$BATS_TEST_TMPDIR/commands`.
- `[ -f "$file" ] && cmd` returns exit 1 under `set -e` when the file is absent; inside functions called from bats, use `if [ -f "$file" ]; then cmd; fi` instead. Same applies to any `test && action` guard pattern.
- `sed -i 'pattern' file 2>/dev/null` returns exit 2 (not 0) when `file` doesn't exist — `2>/dev/null` suppresses stderr but NOT the exit code. Under `set -e`, this silently aborts the function. Fix: add `|| true` after the sed call. Applied in `uninstall_local` for `.bashrc` cleanup.
- **Parameterized stdin in integration tests**: `$"${var}\nline2\n"` is bash locale-translation — `\n` are NOT interpreted as newlines. For heredoc-style stdin with variable interpolation, use process substitution: `run cmd < <(printf '%s\nline2\n' "$var")`.
- **`print_summary` zero-count**: `print_summary` uses `[ n -gt 0 ] && ...` internally — if all counters are 0, it returns 1. Calling a command function directly (without `run`) that ends with `print_summary` will fail the test. Append `|| true` at the call site: `cmd_pod_clone --all > /dev/null || true`.
- **Mock `tput` in bats**: calls to `tput civis`/`cnorm`/`clear` fail without TTY. Create a no-op binary in `setup()`: `printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/bin/tput"; chmod +x "$BATS_TEST_TMPDIR/bin/tput"` with `export PATH="$BATS_TEST_TMPDIR/bin:$PATH"`.
- `scripts/internal/welcome.sh` exposes `_LOADAVG_FILE` and `_OSRELEASE_FILE` overridable variables (default `/proc/loadavg` and `/etc/os-release`) for unit test injection of fake system data. Mock `hostname`, `uname`, `nproc`, `free`, `uptime`, `docker`, `sudo`, `curl`, `openssl` in `$BATS_TEST_TMPDIR/bin/`.
- **kcov multi-line construct limitation**: kcov's debug trap fires once per compound statement — continuation lines of `$(jq -r '[ \` … `]')` and body lines inside `arr+=( … )` are always `lineNoCov` even when the code executes. This is an instrumentation limit of kcov for bash, not a testing gap. Reaching 100% on files with such constructs is not achievable without restructuring code.
- **Direct call vs `run` for kcov loop coverage**: Calling a function directly (without `run`) improves kcov tracking inside loop bodies and the `done < <(...)` line. When kcov coverage of those lines matters, prefer direct calls + side-effect assertions over `run`.
- **Testing TTY-guarded functions (`[[ -t 1 ]]`)**: Use `script -qc "bash $tmpscript" /dev/null` (util-linux `script`) to run code in a real PTY. kcov continues to trace the subprocess because `KCOV_BASH_XTRACEFD` is a separate fd inherited through the PTY boundary. Write the test script to a tmpfile via an unquoted heredoc (`<< MARKER`) so local bats variables expand at write time; use `\$VAR` for deferred expansion in the child bash.
- Counting multi-byte UTF-8 characters (`█`, `─`, box-drawing chars) in pipelines: `tr -cd 'char' | wc -c` counts bytes (3 per char), not occurrences. Use `grep -o 'char' | wc -l` instead. Affects all tests that assert on `welcome.sh` rendering output.
- `source vars.sh` in integration `setup()` overwrites `SCRIPTS_DIR` to `$HOME/scripts` (the tmpdir symlink). Always restore after: `export SCRIPTS_DIR="$_REAL_SCRIPTS_DIR"`. Read `VERSION` and any path-dependent values *before* sourcing `vars.sh`.
- ANSI codes in shell scripts are assigned as literal strings (e.g. `ENV_FG='\033[0m'`), not interpreted sequences. Test assertions must match: use `'\033[0m'`, not `$'\033[0m'` (which is the actual ESC character).

**Making a command sourceable for unit tests** (all `scripts/commands/**/*.sh` and `scripts/internal/*.sh`):
1. Always use `${BASH_SOURCE[0]}` not `$0` when sourcing libs — when sourced from bats `$0` is the bats binary. Lib path from `scripts/commands/`: `"$(dirname "${BASH_SOURCE[0]}")/../lib/<lib>.sh"`; from `scripts/commands/pod/`: `"$(dirname "${BASH_SOURCE[0]}")/../../lib/<lib>.sh"`; from `scripts/internal/`: `"$(dirname "${BASH_SOURCE[0]}")/../lib/<lib>.sh"`. To source an `internal/` script from `commands/config/` (function reuse): `"$(dirname "${BASH_SOURCE[0]}")/../../internal/<name>.sh"` — the main guard `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` prevents `main()` from executing when sourced.
2. `main "$@"` → `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` — the `if` form is mandatory (not `[[ ]] && cmd`): a false `[[ ]]` returns exit 1, failing `source` under bats's `set -e`.

**Mocking binaries in tests**: create scripts in `$BATS_TEST_TMPDIR/bin/` and `export PATH="$BATS_TEST_TMPDIR/bin:$PATH"` in `setup()`. Used for: `crontab` (uninstall — prevents real crontab writes), `sudo`+`docker` (status — `sudo` mock strips `-S` and execs remaining args). Also: `touch "$HOME/.ssh/fleet_key"` bypasses `check_sshpass` (returns 0 when key file exists, even zero-byte), useful in integration tests that need to reach `parse_env` error paths.
Also used for crypto mocks in `install.sh` tests: `openssl` (encrypt→write stdin to `-out` file, decrypt→write fixed string to `-out`), `ssh-keygen` (-e→fake PEM), `diff` (always exit 0), `crontab` (-l→cat stored file, -→store stdin to file). See `tests/unit/install.bats`.

**Mocking functions in tests**: override a function after sourcing the script to capture its args without SSH/Docker. Example: `show_logs() { echo "SHOW_LOGS:$1:$2"; }` lets `connect_to_server()` tests verify the correct server/pod is passed. Override after `source "$SCRIPTS_DIR/..."` — bash function definitions are always replaceable.
- **Mock before AND after source**: mocks set before `source "command.sh"` get overwritten when the command re-sources its lib files. Always re-declare all mock functions *after* the `source` line in `setup()`. See `tests/unit/commands/pod/ssh.bats`.
- **`source` at runtime inside a function overwrites mocks** even in the `run` subshell: if a function calls `source "$file"` dynamically (e.g. `cmd_config` auto-discovering sub-commands), it re-defines the function, bypassing mocks set in `setup()`. Fix in production code: `if ! declare -f "$fn" > /dev/null 2>&1; then source "$file"; fi` — skips sourcing when the function is already defined (mock present in tests, already-loaded in subsequent calls in production). See `cmd_config()` in `config.sh`.
- `_spin_start`/`_spin_stop` create background processes (`&` + `kill`); override them as no-ops (`_spin_start() { :; }; _spin_stop() { :; }`) **after** sourcing in `setup()` to prevent test instability. See `tests/unit/synchronize.bats`.
- **Dispatcher tests require populated `cmd_dir`**: when unit-testing a dispatcher that calls `_cli_dispatch_submenu`, the sub-command directory (`_CMD_DIR`) must already contain at least one valid `@menu`-tagged `.sh` file — otherwise `_cli_scan_menu_dir` returns empty, `files[0]` is unset, and `"$fn"` evaluates to `cmd_` (exit 127). Create a minimal stub sub-command file before writing dispatcher tests.
- `ssh_cmd`/`scp_cmd` can be mocked as function overrides (not binaries) to test remote-facing functions like `sync_remote`, `collect_env`. The mock should simply `return 0` — do NOT use `cat > /dev/null` to consume heredoc stdin, as it blocks indefinitely on calls without a heredoc. Bash automatically cleans up unread heredoc stdin when the command returns. See `tests/unit/synchronize.bats`.
- **Mocking `ssh_cmd` for multiple call types**: When a function uses `ssh_cmd` for different operations (e.g. scan `[ -d "$pdir/.git" ]` and `rm -rf`), the mock must inspect `"$*"` with glob patterns: `if [[ "$*" == *"[ -d"* ]]; then return 0; else echo "RM:$*" >> file; fi`. Works for both function overrides (unit tests) and binary mocks (integration tests).
- **Pipeline race condition in mocks**: In a pipeline `cmd_a | filter | cmd_b`, bash starts all 3 concurrently. If `cmd_b` writes to the same file `cmd_a` reads (e.g. `crontab -l | grep | crontab -`), `cmd_b`'s `cat > file` truncates the file before `cmd_a` finishes reading → store emptied. Fix: `_tmp=$(mktemp); cat > "$_tmp"; mv "$_tmp" "$file"` in the mock's write branch.
- **`[ cond ] && continue` under `set -e`**: Returns exit 1 when `cond` is false (the `&&` short-circuit returns the test's exit code). Use `if [ cond ]; then continue; fi` instead. Same applies to `[ cond ] && break`.
- `chmod u+x "$DIR"/*.sh 2>/dev/null` still fails under `set -e` when the glob matches nothing (exit 1 from chmod, not from stderr). Ensure test directories contain at least one `.sh` file when testing functions that run this pattern.
- **`chmod 444` does not block `mv`**: making a file non-writable is not enough to simulate an atomic write failure (`jq > tmp && mv tmp file`) — `mv` succeeds if the parent directory is writable. To test this path, use `chmod 555 "$(dirname "$file")"` and restore with `chmod 755` after the test.
- **`grep -vF '^{}'` to filter git `^{}` annotations**: `grep -v '\^\{\}'` produces `Invalid content of \{\}` on GNU grep (WSL) because `\{\}` is an invalid BRE. Use `grep -vF '^{}'` (fixed-string) — functionally identical and portable.
- `kill <pid> 2>/dev/null` returns exit 1 for non-existent PIDs — `2>/dev/null` suppresses stderr but NOT the exit code; under bats `set -e` this triggers failure. Always use a real background process (e.g. `sleep 100 &`) when testing functions that call `kill`.
- `wait <pid>` on a killed process returns 143 (128+SIGTERM) — triggers `set -e`. Override the builtin: `wait() { return 0; }` before the call, `unset -f wait` after. Bash function definitions shadow builtins and are restorable with `unset -f`.
- **Mocking git subcommands** (selfupdate pattern): create `$BATS_TEST_TMPDIR/bin/git` that strips `-C <dir>` prefix then switches on the subcommand; control behavior via env vars (`GIT_TAG_POINTS_AT`, `GIT_TAG_LIST`, `GIT_REV_LIST_COUNT`, `GIT_REV_PARSE_HEAD`, `GIT_REV_PARSE_UPSTREAM`, `GIT_FETCH_FAIL`, `GIT_DETACHED_HEAD`, `GIT_CHECKOUT_FAIL`). See `tests/unit/commands/selfupdate.bats`.
- **`${EDITOR:-nano}` in tests**: create `nano` (no-op) + a named editor (e.g. `editor_noop`, `editor_modify`) in `$BATS_TEST_TMPDIR/bin/`; `export EDITOR="$BATS_TEST_TMPDIR/bin/editor_noop"` in `setup()` — otherwise any test reaching `${EDITOR:-nano}` hangs. The "modify" editor implements: `printf '#!/bin/bash\necho "modified" >> "$1"\n'`.
- **Mock `mktemp` to verify tmpfile cleanup**: `mktemp` is an external binary (not a builtin) — it can be shadowed by a function: `touch "$known"; mktemp() { echo "$known"; }; export -f mktemp; run fn; [ ! -f "$known" ]`. `unset -f mktemp` after the test.
- **`md5sum` for detecting file modifications**: always use `md5sum "$file" | cut -d' ' -f1` to compare only the hash — raw `md5sum` output includes the filename (`<hash>  <filename>`), making comparison fragile if the name changes.


## Linting

**ShellCheck** is configured for all `.sh` scripts:
- `.shellcheckrc` — global disables: SC1090/1091 (dynamic source path), SC2154 (globals from lib files), SC2153 (PODS_DIR ≠ POD_DIR false positive), SC2001 (sed style)
- `Makefile` — `make lint` (gcc format, CI-friendly) / `make lint-verbose` (full explanations) / `make check` (alias)
- `scripts/bin/fleetman` has no `.sh` extension — `find scripts/ -name "*.sh"` misses it; Makefile adds it via `SCRIPTS_NOEXT := scripts/bin/fleetman` passed separately to shellcheck.

Per-script suppression conventions:
- `# shellcheck disable=SC2034` — globals set in lib files appear unused in the defining scope; used in callers via source
- `# shellcheck disable=SC2086` — intentional word-splitting on space-separated strings (container lists, etc.)
- `# shellcheck disable=SC2015` — intentional `A && B || C` ternary pattern
- `# shellcheck disable=SC2016` — single-quoted strings written verbatim into remote shells or `.bashrc`; also jq filter strings using `--arg`-passed variables (e.g. `'.template_vars[$k] = $v'` — `$k` is a jq var, not a bash var)
- `# shellcheck disable=SC1083` — git upstream refspec `@{u}` misread as a bash brace expression
- **SC1087 in string interpolation**: `$var[$idx]` inside strings (ok/err/printf messages) triggers SC1087 — use `${var}[${idx}]` instead.


## Initial Setup (new server)

**Quick install** (any server): `curl -fsSL https://raw.githubusercontent.com/jafou2004/fleetman/main/scripts/internal/install.sh | bash`
→ clones repo to `~/fleetman/`, creates symlink `~/scripts → ~/fleetman/scripts/`, runs wizard + key setup.
Override: `FLEETMAN_DIR=~/mydir FLEETMAN_REPO=<url> curl ... | bash`

**Manual install**: `git clone <url> ~/fleetman && ln -s ~/fleetman/scripts ~/scripts`, then `bash ~/scripts/internal/install.sh`.

After install: `fleetman sync` to replicate to fleet, `source ~/.bashrc` on each server.

**`config.json`** is gitignored — copy `config.json.example` to `config.json` and edit before running `install.sh`.

## Fleet Key Setup (install.sh)

Run once on any server to bootstrap key-based authentication across the fleet:

```bash
bash ~/scripts/internal/install.sh
# or with reconfigure: bash ~/scripts/internal/install.sh --reconfigure
```

What it does:
1. Generates `~/.ssh/fleet_key` (RSA 4096) if not present
2. If `~/.fleet_pass.enc` already exists → decrypts it silently (no prompt). Otherwise → prompts once for the fleet password and encrypts it (RSA-OAEP via `openssl pkeyutl`)
3. Deploys to every server via sshpass:
   - Public key → `~/.ssh/authorized_keys` (enables SSH key auth)
   - Private key → `~/.ssh/fleet_key` (allows any server to act as master)
   - Encrypted file → `~/.fleet_pass.enc` (allows `ask_password()` to run silently)

**First run**: password is typed once, then never again.

**Adding a new server**: add it to `config.json` under `servers.<env>`, re-run `bash ~/scripts/internal/install.sh` from any already-configured server — fully silent, no prompt.

**Rotating the password**: re-run `install.sh` — it asks `Password rotation? [Y/n]` (Y by default), prompts for the new password, re-deploys everywhere.

**Selfupdate cron** (offered by install.sh): `0 1 * * * bash ~/scripts/bin/fleetman selfupdate >> ~/.data/selfupdate.log 2>&1`. Idempotency check: `grep -qF "bin/fleetman selfupdate"` in crontab.
