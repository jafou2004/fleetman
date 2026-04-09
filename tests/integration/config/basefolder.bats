#!/usr/bin/env bats
# Integration tests for scripts/commands/config/basefolder.sh
# Covers only pre-interactive paths (no blocking prompts).

load '../../test_helper/common'

setup() {
    setup_fixtures
}

# ── Unknown option ────────────────────────────────────────────────────────────

@test "fleetman config basefolder -z → exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config basefolder -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Missing config.json ───────────────────────────────────────────────────────

@test "fleetman config basefolder: missing config.json → exit 1 + ⚠" {
    rm -f "$HOME/config.json"
    run bash "$SCRIPTS_DIR/bin/fleetman" config basefolder
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}
