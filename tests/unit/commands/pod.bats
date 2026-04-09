#!/usr/bin/env bats
# Unit tests for scripts/commands/pod.sh

load '../../test_helper/common'

setup() {
    load_common
    source "$SCRIPTS_DIR/internal/cli.sh"
    source "$SCRIPTS_DIR/commands/pod.sh"
    # select_menu requires a TTY — mock: always selects entry 0.
    select_menu() { SELECTED_IDX=0; }
    # Replace the real subcommands to isolate cmd_pod.
    cmd_pod_ssh()    { echo "SSH_CALLED"; }
    cmd_pod_status() { echo "STATUS_CALLED"; }
    cmd_pod_logs()   { echo "LOGS_CALLED"; }
    cmd_pod_env()    { echo "ENV_CALLED"; }
    cmd_pod_up()     { echo "UP_CALLED"; }
    cmd_pod_list()   { echo "LIST_CALLED"; }
    cmd_pod_update() { echo "UPDATE_CALLED"; }
    cmd_pod_pull()   { echo "PULL_CALLED"; }
    cmd_pod_clone()  { echo "CLONE_CALLED"; }
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "cmd_pod: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run cmd_pod
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Dispatch menu — sorted by @order ──────────────────────────────────────────

@test "cmd_pod: selection 0 (SSH to pod) → calls cmd_pod_ssh" {
    select_menu() { SELECTED_IDX=0; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_CALLED"* ]]
}

@test "cmd_pod: selection 1 (Status) → calls cmd_pod_status" {
    select_menu() { SELECTED_IDX=1; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS_CALLED"* ]]
}

@test "cmd_pod: selection 2 (Logs) → calls cmd_pod_logs" {
    select_menu() { SELECTED_IDX=2; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOGS_CALLED"* ]]
}

@test "cmd_pod: selection 3 (Env files) → calls cmd_pod_env" {
    select_menu() { SELECTED_IDX=3; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"ENV_CALLED"* ]]
}

@test "cmd_pod: selection 4 (Start pod) → calls cmd_pod_up" {
    select_menu() { SELECTED_IDX=4; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"UP_CALLED"* ]]
}

@test "cmd_pod: selection 5 (List pods) → calls cmd_pod_list" {
    select_menu() { SELECTED_IDX=5; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIST_CALLED"* ]]
}

@test "cmd_pod: selection 6 (Update pod) → calls cmd_pod_update" {
    select_menu() { SELECTED_IDX=6; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"UPDATE_CALLED"* ]]
}

@test "cmd_pod: selection 7 (Git pull) → calls cmd_pod_pull" {
    select_menu() { SELECTED_IDX=7; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"PULL_CALLED"* ]]
}

@test "cmd_pod: selection 8 (Clone repo) → calls cmd_pod_clone" {
    select_menu() { SELECTED_IDX=8; }
    run cmd_pod
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLONE_CALLED"* ]]
}

# ── Section header ─────────────────────────────────────────────────────────────

@test "cmd_pod: displays 'Pod' section header" {
    run cmd_pod
    [[ "$output" == *"Pod"* ]]
}

# ── Direct coverage (without run, for kcov) ───────────────────────────────────

@test "cmd_pod: direct call → dispatches correctly (coverage)" {
    select_menu() { SELECTED_IDX=0; }
    cmd_pod > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "SSH_CALLED" "$BATS_TEST_TMPDIR/out.txt"
}
