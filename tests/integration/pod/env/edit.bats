#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/env/edit.sh
# Covers help output and pre-selection validation errors only.

load '../../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    # Fake fleet_key to bypass check_sshpass
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/fleet_key"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "fleetman pod env edit -h: displays docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env edit -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod env edit"* ]]
}

@test "fleetman pod env edit --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env edit --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "fleetman pod env edit (no -p): exit non-zero + usage message" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env edit
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod env edit"* ]]
}

@test "fleetman pod env edit -p nonexistent: exit non-zero + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env edit -p nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"No pod matching"* ]]
}

@test "fleetman pod env edit -p api -e nosuchenv: exit non-zero + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env edit -p api -e nosuchenv
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid environment"* ]]
}
