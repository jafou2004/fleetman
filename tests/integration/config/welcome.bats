#!/usr/bin/env bats
# Integration tests for scripts/commands/config/welcome.sh
# Covers only pre-interactive paths (no TTY or blocking prompts).

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures

    # tput no-op
    printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/bin/tput"
    chmod +x "$BATS_TEST_TMPDIR/bin/tput"
}

# ── Unknown option ────────────────────────────────────────────────────────────

@test "fleetman config welcome -z → exit 1 + 'Unknown option'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config welcome -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── Missing config.json ───────────────────────────────────────────────────────

@test "fleetman config welcome: missing config.json → exit 1 + ⚠" {
    rm -f "$HOME/config.json"
    run bash "$SCRIPTS_DIR/bin/fleetman" config welcome
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}
