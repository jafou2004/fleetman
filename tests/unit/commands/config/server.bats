#!/usr/bin/env bats
# Unit tests for scripts/commands/config/server.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/internal/cli.sh"
    source "$SCRIPTS_DIR/commands/config/server.sh"
    # select_menu requires a TTY — mock: always selects entry 0.
    select_menu() { SELECTED_IDX=0; }
    # Replace the real subcommand to isolate cmd_config_server.
    cmd_config_server_add() { echo "ADD_CALLED"; }
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_server: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_server
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Dispatch menu ──────────────────────────────────────────────────────────────

@test "cmd_config_server: selection 0 (Add server) → calls cmd_config_server_add" {
    select_menu() { SELECTED_IDX=0; }
    run cmd_config_server
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADD_CALLED"* ]]
}
