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
