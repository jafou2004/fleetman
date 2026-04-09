#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/up.sh
# Invoked via scripts/bin/fleetman (real entry point).
# Tests cover help and validation errors (before SSH/Docker).

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    # dummy fleet_key to bypass check_sshpass
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/fleet_key"
}

# ── Help ───────────────────────────────────────────────────────────────────────

@test "fleetman pod up -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod up -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod up"* ]]
}

@test "fleetman pod up --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod up --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman pod -h: lists 'up' as an available subcommand" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"up"* ]]
}

# ── Basic validation ──────────────────────────────────────────────────────────

@test "fleetman pod up: no -p → exit 1 + 'search term is required'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod up
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "fleetman pod up -p without argument: exit 1 + 'requires an argument'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod up -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "fleetman pod up -p api -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod up -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

# ── Missing pods.json ─────────────────────────────────────────────────────────

@test "fleetman pod up -p api: missing pods.json → exit 1 + error message" {
    rm -f "$PODS_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" pod up -p api
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

# ── No matching pod ───────────────────────────────────────────────────────────

@test "fleetman pod up -p nonexistent: exit 1 + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod up -p nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}

@test "fleetman pod up -p nonexistent -e dev: exit 1 + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod up -p nonexistent -e dev
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}
