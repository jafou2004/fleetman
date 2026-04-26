#!/usr/bin/env bats
# Unit tests for scripts/commands/config/server/remove.sh

load '../../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/server/remove.sh"
    # Mock interactive menus and shared lib functions
    select_menu()          { SELECTED_IDX=0; }
    select_menu_disabled() { SELECTED_IDX=0; }
    get_git_server()       { :; }
    delete_ascii()         { :; }
    select_env_colored()   { SELECTED_ENV="${2:-dev}"; }
    run_sync_or_warn()     { :; }
}

# ── Option parsing ─────────────────────────────────────────────────────────────

@test "cmd_config_server_remove: unknown option -z → exit 1 + Unknown option" {
    run cmd_config_server_remove -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_config_server_remove: missing config.json → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_server_remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── _remove_from_config ────────────────────────────────────────────────────────

@test "_remove_from_config: removes target FQDN from correct env" {
    _remove_from_config "dev" "dev1.fleet.test"
    local remaining
    remaining=$(jq -r '.servers.dev[]' "$CONFIG_FILE")
    [[ "$remaining" != *"dev1.fleet.test"* ]]
    [[ "$remaining" == *"dev2.fleet.test"* ]]
}

@test "_remove_from_config: other envs untouched" {
    _remove_from_config "dev" "dev1.fleet.test"
    local test_servers
    test_servers=$(jq -r '.servers.test[]' "$CONFIG_FILE")
    [[ "$test_servers" == *"test1.fleet.test"* ]]
}

@test "_remove_from_config: prints ✓ on success" {
    run _remove_from_config "dev" "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
}

# ── is_local_server ────────────────────────────────────────────────────────────

@test "is_local_server: returns true for MASTER_HOST exact match" {
    export MASTER_HOST="myserver.fleet.test"
    run is_local_server "myserver.fleet.test"
    [ "$status" -eq 0 ]
}

@test "is_local_server: returns true for short-name match" {
    export MASTER_HOST="myserver.fleet.test"
    run is_local_server "myserver.other.domain"
    [ "$status" -eq 0 ]
}

@test "is_local_server: returns false for different server" {
    export MASTER_HOST="myserver.fleet.test"
    run is_local_server "other.fleet.test"
    [ "$status" -eq 1 ]
}

# ── Confirmation ───────────────────────────────────────────────────────────────

@test "cmd_config_server_remove: confirmation declined (Enter=N) → exit 0, config unchanged" {
    local before
    before=$(cat "$CONFIG_FILE")
    run bash -c "
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        source '$SCRIPTS_DIR/lib/uninstall.sh'
        source '$SCRIPTS_DIR/commands/config/server/remove.sh'
        select_menu()          { SELECTED_IDX=0; }
        select_menu_disabled() { SELECTED_IDX=0; }
        get_git_server()       { :; }
        delete_ascii()         { :; }
        select_env_colored()   { SELECTED_ENV='dev'; }
        run_sync_or_warn()     { :; }
        prompt_confirm()       { return 1; }
        export HOME='$HOME'
        export CONFIG_FILE='$CONFIG_FILE'
        cmd_config_server_remove -e dev
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aborted"* ]]
    local after
    after=$(cat "$CONFIG_FILE")
    [ "$before" = "$after" ]
}

# ── No servers in env ──────────────────────────────────────────────────────────

@test "cmd_config_server_remove: env with 0 servers → exit 0 + ⚠" {
    local tmp
    tmp=$(mktemp)
    jq '.servers.dev = []' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    run cmd_config_server_remove -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Git clone is the only server → all disabled ────────────────────────────────

@test "cmd_config_server_remove: git clone is only server → exit 0 + protected" {
    local tmp
    tmp=$(mktemp)
    jq '.servers.dev = ["dev1.fleet.test"]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    get_git_server() { echo "dev1.fleet.test"; }
    run cmd_config_server_remove -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *"protected"* ]]
}

# ── Remote server happy path ───────────────────────────────────────────────────

@test "cmd_config_server_remove: remote server → uninstall_remote called" {
    local call_file="$BATS_TEST_TMPDIR/uninstall_called"
    prompt_confirm()   { return 0; }
    is_local_server()  { return 1; }
    check_sshpass()    { :; }
    ask_password()     { :; }
    uninstall_remote() { echo "UNINSTALL:$1" > "$call_file"; }
    run cmd_config_server_remove -e dev
    [ "$status" -eq 0 ]
    [ -f "$call_file" ]
    grep -q "dev1.fleet.test" "$call_file"
}

@test "cmd_config_server_remove: remote server → server removed from config" {
    prompt_confirm()   { return 0; }
    is_local_server()  { return 1; }
    check_sshpass()    { :; }
    ask_password()     { :; }
    uninstall_remote() { :; }
    run cmd_config_server_remove -e dev
    [ "$status" -eq 0 ]
    local remaining
    remaining=$(jq -r '.servers.dev[]' "$CONFIG_FILE")
    [[ "$remaining" != *"dev1.fleet.test"* ]]
    [[ "$remaining" == *"dev2.fleet.test"* ]]
}

# ── Local server happy path ────────────────────────────────────────────────────

@test "cmd_config_server_remove: local server → uninstall_local called after sync" {
    local local_file="$BATS_TEST_TMPDIR/local_uninstall"
    local sync_file="$BATS_TEST_TMPDIR/sync_ran"
    prompt_confirm()   { return 0; }
    is_local_server()  { return 0; }
    uninstall_local()  { touch "$local_file"; }
    run_sync_or_warn() { touch "$sync_file"; }
    run cmd_config_server_remove -e dev
    [ "$status" -eq 0 ]
    [ -f "$local_file" ]
    [ -f "$sync_file" ]
}

@test "cmd_config_server_remove: local server → prints 'no longer in the fleet'" {
    prompt_confirm()  { return 0; }
    is_local_server() { return 0; }
    uninstall_local() { :; }
    run cmd_config_server_remove -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *"no longer"* ]]
}

@test "cmd_config_server_remove: local server → server removed from config" {
    prompt_confirm()  { return 0; }
    is_local_server() { return 0; }
    uninstall_local() { :; }
    run cmd_config_server_remove -e dev
    [ "$status" -eq 0 ]
    local remaining
    remaining=$(jq -r '.servers.dev[]' "$CONFIG_FILE")
    [[ "$remaining" != *"dev1.fleet.test"* ]]
}

# ── _remove_from_config failure ────────────────────────────────────────────────

@test "_remove_from_config: jq failure → return 1 + ✗" {
    jq() { return 1; }
    run _remove_from_config "dev" "dev1.fleet.test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"✗"* ]]
}
