#!/bin/bash

# One-time fleet initialisation: creates config.json via an interactive wizard,
# generates a fleet RSA key pair, encrypts the SSH/sudo password, and bootstraps
# key-based SSH auth on every server (authorized_keys).
# Usage: bash ~/fleetman/install.sh [-h]
#
# First install via curl:
#   curl -fsSL https://raw.githubusercontent.com/jafou2004/fleetman/main/install.sh | bash

# ── Bootstrap : clone at first launch with curl-pipe-bash ─────────────────
if [[ ! -f "$0" ]]; then
    _PROJECT_DIR="${FLEETMAN_DIR:-$HOME/fleetman}"
    _REPO_URL="${FLEETMAN_REPO:-https://github.com/jafou2004/fleetman.git}"

    # Requirements necessary before cloning
    for _cmd in git jq openssl ssh-keygen sshpass rsync; do
        if ! command -v "$_cmd" &>/dev/null; then
            echo "  ✗ Missing requirement : $_cmd"
            exit 1
        fi
    done

    if [[ ! -d "$_PROJECT_DIR/.git" ]]; then
        printf "  Git repository URL [%s] : " "$_REPO_URL"
        read -r _input; [[ -n "$_input" ]] && _REPO_URL="$_input"
        printf "  Installation directory [%s] : " "$_PROJECT_DIR"
        read -r _input; [[ -n "$_input" ]] && _PROJECT_DIR="$_input"

        git clone "$_REPO_URL" "$_PROJECT_DIR" || exit 1
        echo "  ✓ Cloned in $_PROJECT_DIR"
    else
        echo "  ⚠ Repository already present in $_PROJECT_DIR — clone skipped"
    fi

    if [[ -L "$HOME/scripts" ]]; then
        echo "  ⚠ Symlink ~/scripts already present"
    elif [[ -d "$HOME/scripts" ]]; then
        echo "  ✗ ~/scripts exists as a real directory"
        echo "    Please move it first: mv ~/scripts ~/scripts.bak"
        exit 1
    else
        ln -s "$_PROJECT_DIR/scripts" "$HOME/scripts"
        echo "  ✓ Symlink created: ~/scripts → $_PROJECT_DIR/scripts"
    fi

    export FLEETMAN_DIR="$_PROJECT_DIR"
    exec bash "$_PROJECT_DIR/install.sh" "$@"
fi
# ── Fin bootstrap ──────────────────────────────────────────────────────────────

_LIB="$(dirname "${BASH_SOURCE[0]}")/scripts/lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"
source "$_LIB/spinner.sh"
source "$_LIB/iterate.sh"

help() {
    echo "One-time fleet initialisation: creates config.json (if needed), generates"
    echo "a fleet RSA key pair, encrypts the SSH/sudo password, and bootstraps"
    echo "key-based SSH auth on every server (authorized_keys)."
    echo ""
    echo "Usage: bash ~/fleetman/install.sh [-h]"
    echo "       curl -fsSL https://raw.githubusercontent.com/jafou2004/fleetman/main/install.sh | bash"
    echo ""
    echo "Re-running on an already-configured server prompts before overwriting"
    echo "(default: N / abort)."
    echo ""
    echo "Options:"
    echo "  -h   Show this help"
    echo ""
    echo "Environment variables (curl install only):"
    echo "  FLEETMAN_DIR    Clone destination (default: ~/fleetman)"
    echo "  FLEETMAN_REPO   Repository URL (default: https://github.com/jafou2004/fleetman.git)"
    echo ""
    echo "Examples:"
    echo "  bash ~/fleetman/install.sh"
}

# ---------------------------------------------------------------------------
# Config wizard — interactive creation of config.json
# ---------------------------------------------------------------------------

_wizard_create_config() {
    require_cmd jq

    section "Fleet configuration wizard"
    echo ""

    # ── General settings ──────────────────────────────────────────────────────

    local pods_dir
    pods_dir=$(prompt_response "pods_dir (pod root directory on every server)" "/opt/pod")

    local base_folder
    printf "  base_folder (default working directory on SSH login) [%s] (Enter to skip) ? " "$HOME"
    read -r base_folder
    if [ -n "$base_folder" ]; then
        while [ ! -d "$base_folder" ]; do
            warn "Directory does not exist: $base_folder"
            printf "  base_folder (Enter to skip) ? "
            read -r base_folder
            [ -z "$base_folder" ] && break
        done
    fi

    local parallel
    parallel=$(prompt_response "Parallel jobs for fleet operations" "4")
    while ! [[ "$parallel" =~ ^[1-9][0-9]*$ ]]; do
        warn "Must be a positive integer"
        parallel=$(prompt_response "Parallel jobs" "4")
    done

    # ── Status checks ─────────────────────────────────────────────────────────

    local containers_raw
    printf "  Status check containers (space-separated, Enter to skip) ? "
    read -r containers_raw

    local wud_port
    printf "  WUD port (0 = disable) ? [3000] "
    read -r wud_port
    wud_port="${wud_port:-3000}"
    while ! [[ "$wud_port" =~ ^[0-9]+$ ]]; do
        warn "Must be a non-negative integer (0 = disable)"
        printf "  WUD port ? [3000] "
        read -r wud_port
        wud_port="${wud_port:-3000}"
    done

    # ── Welcome screen ────────────────────────────────────────────────────────

    local welcome_enabled_raw welcome_enabled welcome_json
    printf "  Display welcome screen on SSH login ? [Y/n] "
    read -r welcome_enabled_raw
    welcome_enabled_raw="${welcome_enabled_raw:-Y}"
    if [[ "$welcome_enabled_raw" =~ ^[Nn] ]]; then
        welcome_enabled="false"
    else
        welcome_enabled="true"
    fi
    echo "  ℹ Fine-grained display options (show_pods, show_os, show_docker) can be configured manually in config.json"
    welcome_json=$(jq -n --argjson enabled "$welcome_enabled" '{"enabled": $enabled}')

    # ── Environments ──────────────────────────────────────────────────────────

    local envs_raw
    envs_raw=$(prompt_response "Environments to configure (space-separated)" "dev test prod")
    local -a envs
    read -ra envs <<< "$envs_raw"

    local env_colors_json="{}"
    local servers_json="{}"
    local -a _default_colors=("green" "yellow" "red")
    local _env_idx=0

    for _env in "${envs[@]}"; do
        [[ -z "$_env" ]] && continue
        echo ""
        section "Environment: $_env"

        local _color_default="${_default_colors[$_env_idx]:-green}"
        local _color_initial_idx=0 _ci
        for _ci in "${!COLOR_NAMES[@]}"; do
            [[ "${COLOR_NAMES[$_ci]}" == "$_color_default" ]] && _color_initial_idx=$_ci
        done
        echo "  Color for $_env:"
        echo ""
        select_menu COLOR_NAMES "$_color_initial_idx"
        echo ""
        local _color="${COLOR_NAMES[$SELECTED_IDX]}"

        local -a _servers=()
        echo "  Enter server FQDNs one per line (blank line to finish):"
        while true; do
            local _fqdn
            printf "  FQDN: "
            read -r _fqdn
            [[ -z "$_fqdn" ]] && break
            _servers+=("$_fqdn")
        done

        if [ "${#_servers[@]}" -eq 0 ]; then
            warn "No servers entered for $_env — environment created with empty list"
        fi

        env_colors_json=$(jq -n \
            --argjson base "$env_colors_json" \
            --arg env "$_env" --arg color "$_color" \
            '$base + {($env): $color}')

        local _servers_array
        _servers_array=$(printf '%s\n' "${_servers[@]}" | jq -R . | jq -s .)
        servers_json=$(jq -n \
            --argjson base "$servers_json" \
            --arg env "$_env" \
            --argjson list "$_servers_array" \
            '$base + {($env): $list}')

        (( _env_idx++ )) || true
    done

    # ── Build containers JSON array ───────────────────────────────────────────

    local containers_json="[]"
    if [ -n "$containers_raw" ]; then
        # shellcheck disable=SC2086  # intentional word-split on space-separated container names
        containers_json=$(printf '%s\n' $containers_raw | jq -R . | jq -s .)
    fi

    # ── Build status_checks object ────────────────────────────────────────────

    local status_checks_json
    if [ "$wud_port" -gt 0 ]; then
        status_checks_json=$(jq -n \
            --argjson containers "$containers_json" \
            --argjson wud_port "$wud_port" \
            '{"containers": $containers, "wud_port": $wud_port}')
    else
        status_checks_json=$(jq -n \
            --argjson containers "$containers_json" \
            '{"containers": $containers}')
    fi

    # ── Assemble and write config.json ────────────────────────────────────────
    # Note: "pods" is reset to {} — pod metadata is rebuilt by fleetman sync

    local config_json
    config_json=$(jq -n \
        --argjson parallel "$parallel" \
        --arg pods_dir "$pods_dir" \
        --arg base_folder "$base_folder" \
        --argjson env_colors "$env_colors_json" \
        --argjson status_checks "$status_checks_json" \
        --argjson welcome "$welcome_json" \
        --argjson servers "$servers_json" \
        '{
            "parallel": $parallel,
            "pods_dir": $pods_dir,
            "env_colors": $env_colors,
            "status_checks": $status_checks,
            "welcome": $welcome,
            "pods": {},
            "servers": $servers
        } + (if $base_folder != "" then {"base_folder": $base_folder} else {} end)')

    echo ""
    if ! printf '%s\n' "$config_json" > "$CONFIG_FILE"; then
        err "Could not write $CONFIG_FILE — check permissions"
        exit 1
    fi
    ok "config.json created at $CONFIG_FILE"
    echo ""
}

# ---------------------------------------------------------------------------
# Fleet key helpers
# ---------------------------------------------------------------------------

deploy_local() {
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    local pubkey
    pubkey=$(cat "$FLEET_KEY.pub")
    if ! grep -qF "$pubkey" ~/.ssh/authorized_keys 2>/dev/null; then
        echo "$pubkey" >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        ok "Public key added to local authorized_keys"
    else
        ok "Public key already present in local authorized_keys"
    fi
    ok "Configured"
    echo ""
    return 0
}

deploy_remote() {
    local server=$1

    if ! sshpass -p "$PASSWORD" ssh-copy-id \
            -i "$FLEET_KEY.pub" \
            -o StrictHostKeyChecking=no \
            "$server" > /dev/null 2>&1; then
        err "Failed to deploy public key"; echo ""; return 1
    fi
    ok "Public key deployed to authorized_keys"

    if ! ssh -i "$FLEET_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
            "$server" true > /dev/null 2>&1; then
        err "Key authentication test failed"; echo ""; return 1
    fi
    ok "Key authentication verified"

    ok "Configured"
    echo ""
    return 0
}

# ---------------------------------------------------------------------------
# Post-deploy offers
# ---------------------------------------------------------------------------

_run_sync() {
    local _fleetman
    _fleetman="$(dirname "${BASH_SOURCE[0]}")/scripts/bin/fleetman"
    if [[ -f "$_fleetman" ]]; then
        section "Launching sync"
        echo ""
        bash "$_fleetman" sync
    else
        warn "fleetman not found — run 'fleetman sync' manually when ready"
    fi
}

_ask_sync_cron() {
    echo ""
    printf "Schedule daily autosync at 1 AM (fleet replication)? [Y/n] "
    local _answer
    read -r _answer
    if [[ "${_answer,,}" != "n" ]]; then
        local _cron_line="0 1 * * * mv ~/.data/autosync.log ~/.data/autosync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/autosync.log 2>&1"
        if crontab -l 2>/dev/null | grep -qF "bin/fleetman sync"; then
            ok "Cron already present — skipped"
        else
            (crontab -l 2>/dev/null; echo "$_cron_line") | crontab -
            ok "Cron added: daily autosync at 01:00 → ~/.data/autosync.log"
        fi
    else
        ok "Skipped — add a cron manually if needed"
    fi
}

# ---------------------------------------------------------------------------
# Repo URL auto-detection
# ---------------------------------------------------------------------------

_write_repo_url() {
    local current
    current=$(jq -r '.repo_url // ""' "$CONFIG_FILE")
    [[ -n "$current" ]] && return 0

    local pdir="${FLEETMAN_DIR:-$HOME/fleetman}"
    local url=""
    if [[ -d "$pdir/.git" ]]; then
        url=$(git -C "$pdir" remote get-url origin 2>/dev/null || true)
    fi

    [[ -z "$url" ]] && return 0

    local tmp
    tmp=$(mktemp)
    if jq --arg v "$url" '.repo_url = $v' "$CONFIG_FILE" > "$tmp" \
            && mv "$tmp" "$CONFIG_FILE"; then
        ok "repo_url detected: $url"
    else
        rm -f "$tmp"
        warn "Cannot write repo_url to config.json"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    while getopts ":h" _opt "$@"; do
        case "$_opt" in
            h) help; exit 0 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # Re-run guard — prompt before overwriting an existing configuration
    if [ -f "$CONFIG_FILE" ]; then
        warn "config.json already exists — continuing will overwrite it and regenerate the fleet key"
        echo ""
        printf "Continue and overwrite? [N/y] "
        local _answer
        read -r _answer
        if [[ ! "${_answer,,}" =~ ^y ]]; then
            ok "Aborted — nothing changed"
            exit 0
        fi
        echo ""
    fi

    _wizard_create_config

    check_config_file

    _write_repo_url

    require_cmd openssl
    require_cmd sshpass
    require_cmd rsync

    # ============================================================
    # Step 1: Generate RSA key pair
    # ============================================================

    section "Step 1: Fleet RSA key pair"

    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    rm -f "$FLEET_KEY" "${FLEET_KEY}.pub"
    # -m PEM forces traditional RSA PEM format (openssl pkeyutl requires it)
    ssh-keygen -t rsa -b 4096 -f "$FLEET_KEY" -N "" -m PEM -C "fleet-key"
    chmod 600 "$FLEET_KEY"
    ok "Key generated: $FLEET_KEY"
    echo ""

    # ============================================================
    # Step 2: Fleet password
    # ============================================================

    section "Step 2: Fleet password"

    while ! prompt_pass_and_encrypt; do :; done
    echo ""

    # ============================================================
    # Step 3: Deploy to all servers
    # ============================================================

    section "Step 3: Bootstrap key-based SSH auth [$(env_label)]"
    echo ""

    PASSWORD="$RAW_PASSWORD"

    iterate_servers deploy_local deploy_remote
    print_summary

    unset PASSWORD RAW_PASSWORD

    _run_sync
    _ask_sync_cron
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
