#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/clone.sh
# Invoked via scripts/bin/fleetman (real entry point).
# Tests cover only help and errors before interactive input.

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    # Create a dummy fleet_key to bypass check_sshpass
    touch "$HOME/.ssh/fleet_key"
}

# ── Help ───────────────────────────────────────────────────────────────────────

@test "fleetman pod clone -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod clone -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod clone"* ]]
}

@test "fleetman pod clone --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod clone --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman pod -h: lists 'clone' as an available subcommand" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"clone"* ]]
}

# ── Flag errors (before interactive input) ────────────────────────────────────

@test "fleetman pod clone -z: unknown option → exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod clone -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "fleetman pod clone -e: -e without argument → exit 1 + 'requires an argument'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod clone -e
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "fleetman pod clone -e nosuchenv: invalid env → exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod clone -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

