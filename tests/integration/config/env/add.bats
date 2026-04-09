#!/usr/bin/env bats
# Integration tests for scripts/commands/config/env/add.sh
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

@test "fleetman config env add -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env add -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"add"* ]]
}

@test "fleetman config env add --help: exit 0 and displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env add --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "fleetman config env add: config.json absent → exit 1 + ⚠" {
    rm -f "$CONFIG_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" config env add
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

@test "fleetman config env add: unknown option → exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config env add -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Env already present (pre-select_menu path) ────────────────────────────────

@test "fleetman config env add: env 'dev' already present → exit 1 + 'already exists'" {
    # Feed 'dev' via stdin → prompt_response reads the name → validation fails before select_menu
    run bash "$SCRIPTS_DIR/bin/fleetman" config env add <<< 'dev'
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "fleetman config env add: config.json not modified when env already exists" {
    local before
    before=$(jq -c '.' "$CONFIG_FILE")
    run bash "$SCRIPTS_DIR/bin/fleetman" config env add <<< 'dev'
    [ "$status" -eq 1 ]
    local after
    after=$(jq -c '.' "$CONFIG_FILE")
    [ "$before" = "$after" ]
}

@test "fleetman config env add: lists existing envs in initial display" {
    # The list is displayed before the prompt — visible even if an existing env is entered
    run bash "$SCRIPTS_DIR/bin/fleetman" config env add <<< 'dev'
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"test"* ]]
    [[ "$output" == *"prod"* ]]
}
