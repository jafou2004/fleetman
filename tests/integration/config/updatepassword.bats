#!/usr/bin/env bats
# Integration tests for scripts/commands/config/updatepassword.sh
# Covers pre-interactive paths only (no blocking prompts).

load '../../test_helper/common'

setup() {
    setup_fixtures
}

# ── Missing config.json ───────────────────────────────────────────────────────

@test "fleetman config updatepassword: missing config.json → exit 1 + ⚠" {
    rm -f "$HOME/config.json"
    run bash "$SCRIPTS_DIR/bin/fleetman" config updatepassword
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Missing fleet key ─────────────────────────────────────────────────────────

@test "fleetman config updatepassword: FLEET_KEY missing → exit 1 + 'Fleet key not found'" {
    rm -f "$HOME/.ssh/fleet_key"
    touch "$HOME/.fleet_pass.enc"
    run bash "$SCRIPTS_DIR/bin/fleetman" config updatepassword
    [ "$status" -eq 1 ]
    [[ "$output" == *"Fleet key not found"* ]]
}

# ── Missing fleet pass file ───────────────────────────────────────────────────

@test "fleetman config updatepassword: FLEET_PASS_FILE missing → exit 1 + 'Fleet password file not found'" {
    touch "$HOME/.ssh/fleet_key"
    rm -f "$HOME/.fleet_pass.enc"
    run bash "$SCRIPTS_DIR/bin/fleetman" config updatepassword
    [ "$status" -eq 1 ]
    [[ "$output" == *"Fleet password file not found"* ]]
}
