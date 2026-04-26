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

# ── Remote-only env happy path ────────────────────────────────────────────────

@test "cmd_config_env_remove: remote-only env → uninstall_remote called for each server" {
    local call_file="$BATS_TEST_TMPDIR/uninstall_calls"
    uninstall_remote() { echo "UNINSTALL:$1" >> "$call_file"; }
    run cmd_config_env_remove -e dev
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
    grep -q "dev1.fleet.test" "$call_file"
    grep -q "dev2.fleet.test" "$call_file"
}

@test "cmd_config_env_remove: remote-only env → env removed from config" {
    run cmd_config_env_remove -e dev
    [ "$status" -eq 0 ]
    [ "$(jq '.servers | has("dev")' "$CONFIG_FILE")" = "false" ]
    [ "$(jq '.env_colors | has("dev")' "$CONFIG_FILE")" = "false" ]
}

@test "cmd_config_env_remove: remote-only env → sync called" {
    local sync_file="$BATS_TEST_TMPDIR/sync_ran"
    run_sync_or_warn() { touch "$sync_file"; }
    run cmd_config_env_remove -e dev
    [ "$status" -eq 0 ]
    [ -f "$sync_file" ]
}

# ── Env with local server ─────────────────────────────────────────────────────

@test "cmd_config_env_remove: env with local server → uninstall_local called, remote loop skips it" {
    local call_file="$BATS_TEST_TMPDIR/uninstall_calls"
    local local_file="$BATS_TEST_TMPDIR/local_uninstall"
    is_local_server()  { [[ "$1" == "dev1.fleet.test" ]]; }
    uninstall_remote() { echo "UNINSTALL:$1" >> "$call_file"; }
    uninstall_local()  { touch "$local_file"; }
    run cmd_config_env_remove -e dev
    [ "$status" -eq 0 ]
    [ -f "$local_file" ]
    [ -f "$call_file" ]
    ! grep -q "dev1.fleet.test" "$call_file"
    grep -q "dev2.fleet.test" "$call_file"
}

@test "cmd_config_env_remove: env with local server → prints 'no longer in the fleet'" {
    is_local_server() { [[ "$1" == "dev1.fleet.test" ]]; }
    uninstall_local() { :; }
    run cmd_config_env_remove -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *"no longer"* ]]
}

@test "cmd_config_env_remove: env with local server → sync called before local uninstall" {
    local order_file="$BATS_TEST_TMPDIR/order"
    is_local_server()  { [[ "$1" == "dev1.fleet.test" ]]; }
    run_sync_or_warn() { echo "sync" >> "$order_file"; }
    uninstall_local()  { echo "local" >> "$order_file"; }
    run cmd_config_env_remove -e dev
    [ "$status" -eq 0 ]
    [ "$(sed -n '1p' "$order_file")" = "sync" ]
    [ "$(sed -n '2p' "$order_file")" = "local" ]
}

# ── _remove_env_from_config failure ───────────────────────────────────────────

@test "_remove_env_from_config: jq failure → return 1 + ✗" {
    jq() { return 1; }
    run _remove_env_from_config "dev"
    [ "$status" -ne 0 ]
    [[ "$output" == *"✗"* ]]
}
