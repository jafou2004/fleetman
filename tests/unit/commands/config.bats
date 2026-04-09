#!/usr/bin/env bats
# Unit tests for scripts/commands/config.sh

load '../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/internal/cli.sh"
    source "$SCRIPTS_DIR/commands/config.sh"
    # select_menu requires a TTY — mock: always selects entry 0.
    select_menu() { SELECTED_IDX=0; }
    # Replace the real subcommands to isolate cmd_config.
    cmd_config_parallel()      { echo "PARALLEL_CALLED"; }
    cmd_config_status()        { echo "STATUS_CALLED"; }
    cmd_config_podsignore()    { echo "PODSIGNORE_CALLED"; }
    cmd_config_autosync()      { echo "AUTOSYNC_CALLED"; }
    cmd_config_env()           { echo "ENV_CALLED"; }
    cmd_config_server()        { echo "SERVER_CALLED"; }
    cmd_config_templatevars() { echo "TEMPLATE_VARS_CALLED"; }
    cmd_config_welcome()      { echo "WELCOME_CALLED"; }
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_config: config.json absent → exit 1 + warning" {
    rm -f "$CONFIG_FILE"
    run cmd_config
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Dispatch menu ─────────────────────────────────────────────────────────────

@test "cmd_config: selection 0 (Parallel jobs) → calls cmd_config_parallel" {
    select_menu() { SELECTED_IDX=0; }
    run cmd_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARALLEL_CALLED"* ]]
}

@test "cmd_config: selection 1 (Status checks) → calls cmd_config_status" {
    select_menu() { SELECTED_IDX=1; }
    cmd_config_status() { echo "STATUS_CALLED"; }
    run cmd_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS_CALLED"* ]]
}

@test "cmd_config: selection 2 (Ignored pods) → calls cmd_config_podsignore" {
    select_menu() { SELECTED_IDX=2; }
    cmd_config_podsignore() { echo "PODSIGNORE_CALLED"; }
    run cmd_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"PODSIGNORE_CALLED"* ]]
}

@test "cmd_config: selection 3 (Autosync) → calls cmd_config_autosync" {
    select_menu() { SELECTED_IDX=3; }
    cmd_config_autosync() { echo "AUTOSYNC_CALLED"; }
    run cmd_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTOSYNC_CALLED"* ]]
}

@test "cmd_config: selection 4 (Environments) → calls cmd_config_env" {
    select_menu() { SELECTED_IDX=4; }
    cmd_config_env() { echo "ENV_CALLED"; }
    run cmd_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"ENV_CALLED"* ]]
}

@test "cmd_config: selection 5 (Servers) → calls cmd_config_server" {
    select_menu() { SELECTED_IDX=5; }
    cmd_config_server() { echo "SERVER_CALLED"; }
    run cmd_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_CALLED"* ]]
}

@test "cmd_config: selection 6 (Template vars) → calls cmd_config_templatevars" {
    select_menu() { SELECTED_IDX=6; }
    cmd_config_templatevars() { echo "TEMPLATE_VARS_CALLED"; }
    run cmd_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEMPLATE_VARS_CALLED"* ]]
}

@test "cmd_config: selection 7 (Welcome screen) → calls cmd_config_welcome" {
    select_menu() { SELECTED_IDX=7; }
    cmd_config_welcome() { echo "WELCOME_CALLED"; }
    run cmd_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"WELCOME_CALLED"* ]]
}
