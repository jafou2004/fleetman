#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/env/diff.sh
# Covers help and validation errors (before SSH).

load '../../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    # dummy fleet_key to bypass check_sshpass
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/fleet_key"
}

# ── Help ─────────────────────────────────────────────────────────────────────

@test "fleetman pod env diff -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env diff -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod env diff"* ]]
}

@test "fleetman pod env diff --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env diff --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Mode C ───────────────────────────────────────────────────────────────────

@test "Mode C: empty directory without -p → exit 1 + 'not a pod directory'" {
    run bash -c "cd '$BATS_TEST_TMPDIR' && bash '$SCRIPTS_DIR/bin/fleetman' pod env diff"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a pod directory"* ]]
}

# ── Mode B ───────────────────────────────────────────────────────────────────

@test "Mode B in sync: .env-dist + .env identical → exit 0 + 'in sync'" {
    local pod_dir="$BATS_TEST_TMPDIR/mypod"
    mkdir -p "$pod_dir"
    printf 'FOO=bar\nBAR=baz\n' > "$pod_dir/.env-dist"
    printf 'FOO=bar\nBAR=baz\n' > "$pod_dir/.env"
    run bash -c "cd '$pod_dir' && bash '$SCRIPTS_DIR/bin/fleetman' pod env diff < /dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"in sync"* ]]
}

# ── Mode A — validation ───────────────────────────────────────────────────────

@test "fleetman pod env diff -p nonexistent: exit 1 + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env diff -p nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}

@test "fleetman pod env diff -p api -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env diff -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}
