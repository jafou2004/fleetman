#!/usr/bin/env bats
# Integration tests for scripts/commands/config/env/color.sh
# Invoked via scripts/bin/fleetman (real entry point).
# Restriction: covers only pre-interactive paths (no TTY or blocking prompts).

load '../../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "fleetman config env color -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env color -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"color"* ]]
}

@test "fleetman config env color --help: exit 0 and displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env color --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "fleetman config env color: missing config.json → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" config env color
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

@test "fleetman config env color: unknown option → exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env color -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
