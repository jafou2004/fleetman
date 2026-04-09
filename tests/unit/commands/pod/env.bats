#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/env.sh

load '../../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/internal/cli.sh"
    source "$SCRIPTS_DIR/commands/pod/env.sh"
    # select_menu requires a TTY — mock: always selects entry 0.
    select_menu() { SELECTED_IDX=0; }
    # Replace the real subcommands to isolate cmd_pod_env.
    cmd_pod_env_cp()   { echo "CP_CALLED"; }
    cmd_pod_env_diff() { echo "DIFF_CALLED"; }
    cmd_pod_env_edit() { echo "EDIT_CALLED"; }
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_pod_env: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_pod_env
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Dispatch menu — sorted by @order ──────────────────────────────────────────

@test "cmd_pod_env: selection 0 (Copy .env to fleet) → calls cmd_pod_env_cp" {
    select_menu() { SELECTED_IDX=0; }
    run cmd_pod_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"CP_CALLED"* ]]
}

@test "cmd_pod_env: selection 1 (Diff .env vs .env-dist) → calls cmd_pod_env_diff" {
    select_menu() { SELECTED_IDX=1; }
    run cmd_pod_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"DIFF_CALLED"* ]]
}

@test "cmd_pod_env: selection 2 (Edit .env) → calls cmd_pod_env_edit" {
    select_menu() { SELECTED_IDX=2; }
    run cmd_pod_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"EDIT_CALLED"* ]]
}

# ── Section header ─────────────────────────────────────────────────────────────

@test "cmd_pod_env: displays '.env' section header" {
    run cmd_pod_env
    [[ "$output" == *".env"* ]]
}

# ── Direct coverage (without run, for kcov) ───────────────────────────────────

@test "cmd_pod_env: direct call → dispatches correctly (coverage)" {
    select_menu() { SELECTED_IDX=0; }
    cmd_pod_env > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "CP_CALLED" "$BATS_TEST_TMPDIR/out.txt"
}
