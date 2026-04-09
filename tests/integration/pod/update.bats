#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/update.sh
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

@test "fleetman pod update -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod update -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod update"* ]]
}

@test "fleetman pod update --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod update --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman pod -h: lists 'update' as an available subcommand" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"update"* ]]
}

# ── Basic validation ──────────────────────────────────────────────────────────

@test "fleetman pod update: no -p → exit 1 + 'search term is required'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod update
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "fleetman pod update -p without argument: exit 1 + 'requires an argument'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod update -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "fleetman pod update -p api -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod update -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

# ── No matching pod ───────────────────────────────────────────────────────────

@test "fleetman pod update -p nonexistent: exit 1 + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod update -p nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}

@test "fleetman pod update -p nonexistent -e dev: exit 1 + 'No pod matching'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod update -p nonexistent -e dev
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}
