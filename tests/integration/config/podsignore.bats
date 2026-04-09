#!/usr/bin/env bats
# Integration tests for scripts/commands/config/pods_ignore.sh
# Covers only pre-interactive paths (no blocking prompts).

load '../../test_helper/common'

setup() {
    setup_fixtures
}

# ── Unknown option ────────────────────────────────────────────────────────────

@test "fleetman config podsignore -z → exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config podsignore -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Missing config.json ───────────────────────────────────────────────────────

@test "fleetman config podsignore: missing config.json → exit 1 + ⚠" {
    rm -f "$HOME/config.json"
    run bash "$SCRIPTS_DIR/bin/fleetman" config podsignore
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "fleetman config podsignore -h → displays docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config podsignore -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"PCRE"* ]]
}
