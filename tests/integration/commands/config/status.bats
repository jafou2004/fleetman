#!/usr/bin/env bats
# Integration tests for scripts/commands/config/status.sh
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

@test "fleetman config status -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config status -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"status"* ]]
}

@test "fleetman config status --help: exit 0 and displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "fleetman config status: unknown option → exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config status -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "fleetman config status: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" config status
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Initial display ───────────────────────────────────────────────────────────

@test "fleetman config status: containers present → nginx and app in output" {
    # Fixture has containers: ["nginx", "app"], wud_port: 3000
    # Feed: n (skip remove) + empty (skip add) + empty (WUD port → default 3000)
    run bash "$SCRIPTS_DIR/bin/fleetman" config status < <(printf 'n\n\n\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"nginx"* ]]
    [[ "$output" == *"app"* ]]
}

@test "fleetman config status: liste vide → 'No container followed' dans output" {
    jq 'del(.status_checks.containers)' "$CONFIG_FILE" > "$BATS_TEST_TMPDIR/tmp.json" \
        && mv "$BATS_TEST_TMPDIR/tmp.json" "$CONFIG_FILE"
    # No remove step (empty list); feed: empty (skip add) + empty (WUD port → default 3000)
    run bash "$SCRIPTS_DIR/bin/fleetman" config status < <(printf '\n\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"No container followed"* ]]
}
