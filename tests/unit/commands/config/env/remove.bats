#!/usr/bin/env bats
# Unit tests for scripts/commands/config/env/remove.sh

load '../../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/env/remove.sh"
    get_git_server()       { :; }
    delete_ascii()         { :; }
    select_env_colored()   { SELECTED_ENV="${2:-dev}"; }
    run_sync_or_warn()     { :; }
    uninstall_remote()     { :; }
    uninstall_local()      { :; }
    prompt_confirm()       { return 0; }
    check_sshpass()        { :; }
    ask_password()         { :; }
    is_local_server()      { return 1; }
}

# ── Option parsing ─────────────────────────────────────────────────────────────

@test "cmd_config_env_remove: unknown option -z → exit 1 + Unknown option" {
    run cmd_config_env_remove -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_config_env_remove: missing config.json → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_env_remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

@test "cmd_config_env_remove: -e env containing git clone server → exit 1" {
    mkdir -p "$HOME/.data"
    echo "dev1.fleet.test" > "$HOME/.data/git_server"
    export GIT_SERVER_FILE="$HOME/.data/git_server"
    get_git_server() { cat "$GIT_SERVER_FILE"; }
    run cmd_config_env_remove -e dev
    [ "$status" -eq 1 ]
    [[ "$output" == *"git clone"* ]]
}

@test "cmd_config_env_remove: env with 0 servers → exit 0 + ⚠" {
    local tmp
    tmp=$(mktemp)
    jq '.servers.test = []' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    run cmd_config_env_remove -e test
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
}

# ── _remove_env_from_config ────────────────────────────────────────────────────

@test "_remove_env_from_config: removes .servers[env]" {
    _remove_env_from_config "dev"
    [ "$(jq '.servers | has("dev")' "$CONFIG_FILE")" = "false" ]
}

@test "_remove_env_from_config: removes .env_colors[env]" {
    _remove_env_from_config "dev"
    [ "$(jq '.env_colors | has("dev")' "$CONFIG_FILE")" = "false" ]
}

@test "_remove_env_from_config: other envs untouched" {
    _remove_env_from_config "dev"
    [ "$(jq '.servers | has("test")' "$CONFIG_FILE")" = "true" ]
    [ "$(jq '.env_colors | has("test")' "$CONFIG_FILE")" = "true" ]
}

@test "_remove_env_from_config: prints ✓" {
    run _remove_env_from_config "dev"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
}

# ── Confirmation ───────────────────────────────────────────────────────────────

@test "cmd_config_env_remove: confirmation declined → exit 0 + Aborted + config unchanged" {
    local before
    before=$(cat "$CONFIG_FILE")
    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        source '$SCRIPTS_DIR/lib/uninstall.sh'
        source '$SCRIPTS_DIR/commands/config/env/remove.sh'
        get_git_server()     { :; }
        delete_ascii()       { :; }
        select_env_colored() { SELECTED_ENV='dev'; }
        run_sync_or_warn()   { :; }
        uninstall_remote()   { :; }
        uninstall_local()    { :; }
        check_sshpass()      { :; }
        ask_password()       { :; }
        is_local_server()    { return 1; }
        prompt_confirm()     { return 1; }
        export HOME='$HOME'
        export CONFIG_FILE='$CONFIG_FILE'
        cmd_config_env_remove -e dev
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aborted"* ]]
    local after
    after=$(cat "$CONFIG_FILE")
    [ "$before" = "$after" ]
}
