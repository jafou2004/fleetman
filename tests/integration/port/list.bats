#!/usr/bin/env bats
# Integration tests for fleetman port list

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
}

@test "fleetman port list -h: displays docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port list -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"port list"* ]]
}

@test "fleetman port list --help: exit 0" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port list --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman port list -z: unknown option → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" port list -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
