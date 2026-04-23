#!/usr/bin/env bats
# Integration tests for scripts/commands/config/server/remove.sh

load '../../../test_helper/common'

setup() {
    setup_fixtures
}

@test "fleetman config server remove -h: exit 0 + Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config server remove -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"remove"* ]]
}

@test "fleetman config server remove --help: exit 0 + Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config server remove --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman config server remove -z: exit 1 + Unknown option" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config server remove -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "fleetman config server remove: missing config.json → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" config server remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

@test "fleetman config server remove -e invalid: exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config server remove -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"nosuchenv"* ]]
}
