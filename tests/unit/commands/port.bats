#!/usr/bin/env bats
# Unit tests for scripts/commands/port.sh

load '../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/internal/cli.sh"
    source "$SCRIPTS_DIR/commands/port.sh"
    select_menu() { SELECTED_IDX=0; }
    cmd_port_next()  { echo "NEXT_CALLED"; }
    cmd_port_list()  { echo "LIST_CALLED"; }
    cmd_port_check() { echo "CHECK_CALLED"; }
}

# ── check_config_file ─────────────────────────────────────────────────────────

@test "cmd_port: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_port
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Dispatch menu — sorted by @order ──────────────────────────────────────────

@test "cmd_port: selection 0 (Next available ports) → calls cmd_port_next" {
    select_menu() { SELECTED_IDX=0; }
    run cmd_port
    [ "$status" -eq 0 ]
    [[ "$output" == *"NEXT_CALLED"* ]]
}

@test "cmd_port: selection 1 (List used ports) → calls cmd_port_list" {
    select_menu() { SELECTED_IDX=1; }
    run cmd_port
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIST_CALLED"* ]]
}

@test "cmd_port: selection 2 (Check port availability) → calls cmd_port_check" {
    select_menu() { SELECTED_IDX=2; }
    run cmd_port
    [ "$status" -eq 0 ]
    [[ "$output" == *"CHECK_CALLED"* ]]
}

# ── Section header ─────────────────────────────────────────────────────────────

@test "cmd_port: displays 'Port' section header" {
    run cmd_port
    [[ "$output" == *"Port"* ]]
}

# ── Direct call for kcov coverage ─────────────────────────────────────────────

@test "cmd_port: direct call → dispatches correctly (coverage)" {
    select_menu() { SELECTED_IDX=0; }
    cmd_port > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "NEXT_CALLED" "$BATS_TEST_TMPDIR/out.txt"
}
