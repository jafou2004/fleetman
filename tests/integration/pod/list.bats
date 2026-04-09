#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/list.sh
# Invoked via scripts/bin/fleetman (real entry point).

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    # pod list is purely local — no SSH, no fleet_key needed
}

# ── Help ───────────────────────────────────────────────────────────────────────

@test "fleetman pod list -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod list"* ]]
}

@test "fleetman pod list --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman pod -h: lists 'list' as an available subcommand" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"list"* ]]
}

# ── Missing pods.json ─────────────────────────────────────────────────────────

@test "fleetman pod list: missing pods.json → exit 1 + error message" {
    rm -f "$PODS_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

# ── No filter ─────────────────────────────────────────────────────────────────

@test "fleetman pod list: exit 0" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list
    [ "$status" -eq 0 ]
}

@test "fleetman pod list: displays the 3 envs (DEV, TEST, PROD)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list
    [[ "$output" == *"DEV"* ]]
    [[ "$output" == *"TEST"* ]]
    [[ "$output" == *"PROD"* ]]
}

@test "fleetman pod list: displays short names (dev1, test1)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list
    [[ "$output" == *"dev1"* ]]
    [[ "$output" == *"test1"* ]]
}

@test "fleetman pod list: summary '7 pod(s) across 3 environment(s)'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list
    [[ "$output" == *"7 pod(s) across 3 environment(s)"* ]]
}

# ── Filter -e ─────────────────────────────────────────────────────────────────

@test "fleetman pod list -e dev: DEV present, PROD absent" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEV"* ]]
    [[ "$output" != *"PROD"* ]]
}

@test "fleetman pod list -e dev: summary '3 pod(s) across 1 environment(s)'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -e dev
    [[ "$output" == *"3 pod(s) across 1 environment(s)"* ]]
}

@test "fleetman pod list -e test: summary '2 pod(s) across 1 environment(s)'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -e test
    [[ "$output" == *"2 pod(s) across 1 environment(s)"* ]]
}

@test "fleetman pod list -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

# ── Filter -p ─────────────────────────────────────────────────────────────────

@test "fleetman pod list -p api: 'api' present, 'worker' absent" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -p api
    [[ "$output" == *"api"* ]]
    [[ "$output" != *"worker"* ]]
}

@test "fleetman pod list -p api: summary '4 pod(s) across 3 environment(s)'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -p api
    [[ "$output" == *"4 pod(s) across 3 environment(s)"* ]]
}

@test "fleetman pod list -p api -e dev: summary '2 pod(s) across 1 environment(s)'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -p api -e dev
    [[ "$output" == *"2 pod(s) across 1 environment(s)"* ]]
}

@test "fleetman pod list -p nonexistent: exit 0 + warn 'No results'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -p nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"No results"* ]]
}

# ── Invalid options ───────────────────────────────────────────────────────────

@test "fleetman pod list -p without argument: exit 1 + 'requires an argument'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "fleetman pod list -z unknown option: exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod list -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
