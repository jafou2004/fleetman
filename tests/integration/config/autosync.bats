#!/usr/bin/env bats
# Integration tests for scripts/commands/config/autosync.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures

    # Mock crontab binary (same pattern as unit tests)
    cat > "$BATS_TEST_TMPDIR/bin/crontab" << EOF
#!/bin/bash
_CRON_FILE="$BATS_TEST_TMPDIR/crontab.txt"
if [[ "\$1" == "-l" ]]; then
    cat "\$_CRON_FILE" 2>/dev/null || true
else
    _tmp=\$(mktemp)
    cat > "\$_tmp"
    mv "\$_tmp" "\$_CRON_FILE"
fi
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/crontab"

    # Fleet key to bypass check_sshpass
    touch "$HOME/.ssh/fleet_key"

    # Simulated local clone
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$FLEETMAN_DIR/.git"
}

# ── config.json absent ────────────────────────────────────────────────────────

@test "fleetman config autosync: config.json absent → exit 1 + ⚠" {
    rm -f "$HOME/config.json"
    run bash "$SCRIPTS_DIR/bin/fleetman" config autosync <<< 'n'
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Cron absent, response n ───────────────────────────────────────────────────

@test "fleetman config autosync: cron absent, response n → Unchanged, crontab not modified" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config autosync <<< 'n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unchanged"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/crontab.txt" ]
}

# ── Activation with time ──────────────────────────────────────────────────────

@test "fleetman config autosync: cron absent, activation 01:30 → correct cron line" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config autosync < <(printf 'Y\n01:30\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"01:30"* ]]
    # _hh="01" (zero-padded from user input "01:30"), _mm="30"
    grep -q "30 01 \* \* \*.*fleetman sync" "$BATS_TEST_TMPDIR/crontab.txt"
}

# ── Deactivation ──────────────────────────────────────────────────────────────

@test "fleetman config autosync: cron present, deactivation → line removed" {
    echo "0 1 * * * mv ~/.data/autosync.log ~/.data/autosync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/autosync.log 2>&1" \
        > "$BATS_TEST_TMPDIR/crontab.txt"
    run bash "$SCRIPTS_DIR/bin/fleetman" config autosync <<< 'y'
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled"* ]]
    run grep "fleetman sync" "$BATS_TEST_TMPDIR/crontab.txt"
    [ "$status" -ne 0 ]
}
