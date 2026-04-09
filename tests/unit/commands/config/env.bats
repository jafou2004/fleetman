#!/usr/bin/env bats
# Unit tests for scripts/commands/config/env.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/internal/cli.sh"
    source "$SCRIPTS_DIR/commands/config/env.sh"
    # select_menu requires a TTY — mock: always selects entry 0.
    select_menu() { SELECTED_IDX=0; }
    # Replace the real subcommands to isolate cmd_config_env.
    cmd_config_env_add() { echo "ADD_CALLED"; }
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config_env: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_config_env
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Dispatch menu ─────────────────────────────────────────────────────────────

@test "cmd_config_env: selection 0 (Add environment) → calls cmd_config_env_add" {
    select_menu() { SELECTED_IDX=0; }
    run cmd_config_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADD_CALLED"* ]]
}
