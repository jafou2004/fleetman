#!/usr/bin/env bats
# Unit tests for scripts/commands/config/server/remove.sh

load '../../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/commands/config/server/remove.sh"
    # Mock interactive menus to avoid TTY requirements
    select_menu()          { SELECTED_IDX=0; }
    select_menu_disabled() { SELECTED_IDX=0; }
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

@test "cmd_config_server_remove: -e invalid_env → exit 1" {
    run cmd_config_server_remove -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"nosuchenv"* ]]
}

# ── _get_git_server ────────────────────────────────────────────────────────────

@test "_get_git_server: reads FQDN from GIT_SERVER_FILE" {
    echo "git1.fleet.test" > "$HOME/.data/git_server"
    export GIT_SERVER_FILE="$HOME/.data/git_server"
    run _get_git_server
    [ "$status" -eq 0 ]
    [ "$output" = "git1.fleet.test" ]
}

@test "_get_git_server: returns empty when file absent" {
    export GIT_SERVER_FILE="$HOME/.data/git_server_absent"
    run _get_git_server
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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

# ── _delete_ascii ──────────────────────────────────────────────────────────────

@test "_delete_ascii: removes welcome_<short>.ascii when present" {
    touch "$HOME/.data/welcome_dev1.ascii"
    export DATA_DIR="$HOME/.data"
    _delete_ascii "dev1.fleet.test"
    [ ! -f "$HOME/.data/welcome_dev1.ascii" ]
}

@test "_delete_ascii: no error when file absent" {
    export DATA_DIR="$HOME/.data"
    run _delete_ascii "noserver.fleet.test"
    [ "$status" -eq 0 ]
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
        source '$SCRIPTS_DIR/commands/config/server/remove.sh'
        select_menu()          { SELECTED_IDX=0; }
        select_menu_disabled() { SELECTED_IDX=0; }
        prompt_confirm()       { return 1; }
        export HOME='$HOME'
        export CONFIG_FILE='$CONFIG_FILE'
        export GIT_SERVER_FILE='$HOME/.data/git_server_absent'
        cmd_config_server_remove -e dev
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aborted"* ]]
    local after
    after=$(cat "$CONFIG_FILE")
    [ "$before" = "$after" ]
}
