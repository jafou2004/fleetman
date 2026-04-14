#!/usr/bin/env bats
# Integration tests for fleetman config portrange

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
}

@test "fleetman config portrange -h: displays docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config portrange -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"portrange"* ]]
}

@test "fleetman config portrange --help: exit 0" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config portrange --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman config portrange -z: unknown option → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config portrange -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
