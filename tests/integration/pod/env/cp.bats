#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/env/cp.sh
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

# ── Help ────────────────────────────────────────────────────────────────────────

@test "fleetman pod env cp -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env cp -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod env cp"* ]]
}

@test "fleetman pod env cp --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env cp --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman pod -h: lists 'env' as an available subgroup" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"env"* ]]
}

# ── Basic validation ──────────────────────────────────────────────────────────

@test "fleetman pod env cp: no -p → exit 1 + 'search term is required'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env cp
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "fleetman pod env cp -p nonexistent: exit 1 + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env cp -p nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}

@test "fleetman pod env cp -p api -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env cp -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

# ── Missing .env ──────────────────────────────────────────────────────────────

@test "fleetman pod env cp -p api -e dev: missing .env → exit 1 + 'not found'" {
    # PODS_DIR = /opt/pod (from config fixture) — file does not exist in WSL
    run bash "$SCRIPTS_DIR/bin/fleetman" pod env cp -p api -e dev < /dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}
