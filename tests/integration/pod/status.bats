#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/status.sh
# Invoked via scripts/bin/fleetman.
# Covers help and validation errors (before SSH/Docker).

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/fleet_key"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "fleetman pod status -h: displays Usage and exit 0" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod status -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod status"* ]]
}

@test "fleetman pod status --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman pod -h: lists 'status' as an available subcommand" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
}

# ── Basic validation ──────────────────────────────────────────────────────────

@test "fleetman pod status: no -p → exit 1 + 'required'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod status
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "fleetman pod status -p without argument: exit 1 + 'requires an argument'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod status -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "fleetman pod status -p api -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod status -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

# ── Missing pods.json ─────────────────────────────────────────────────────────

@test "fleetman pod status -p api: missing pods.json → exit 1" {
    rm -f "$HOME/.data/pods.json"
    run bash "$SCRIPTS_DIR/bin/fleetman" pod status -p api
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

# ── No matching pod ───────────────────────────────────────────────────────────

@test "fleetman pod status -p __nonexistent__: exit 1 + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod status -p __nonexistent__
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}

@test "fleetman pod status -p __nonexistent__ -e dev: exit 1 + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod status -p __nonexistent__ -e dev
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}
