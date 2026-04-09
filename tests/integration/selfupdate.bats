#!/usr/bin/env bats
# Integration tests for scripts/commands/selfupdate.sh
# Invoked via scripts/bin/fleetman (real entry point) or directly.

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
}

# ── Via the fleetman dispatcher ───────────────────────────────────────────────

@test "fleetman selfupdate -h: displays the selfupdate.sh docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" selfupdate -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updates the fleet scripts"* ]]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman selfupdate --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" selfupdate --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Prerequisites validation ──────────────────────────────────────────────────

@test "cmd_selfupdate: missing config → exit 1" {
    rm -f "$HOME/config.json"
    touch "$HOME/.ssh/fleet_key"
    run bash -c "
        export HOME='$HOME'
        export PATH='$BATS_TEST_TMPDIR/bin:\$PATH'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/commands/selfupdate.sh'
        check_sshpass
        check_config_file
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

@test "cmd_selfupdate: neither fleet_key nor sshpass in PATH → exit 1" {
    rm -f "$HOME/.ssh/fleet_key"
    run env PATH="/usr/bin:/bin" bash -c "
        export HOME='$HOME'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        check_sshpass
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "cmd_selfupdate: invalid track in config → exit 1 with error message" {
    touch "$HOME/.ssh/fleet_key"
    # Inject an invalid track into the config
    local cfg
    cfg=$(cat "$HOME/config.json")
    echo "$cfg" | jq '.selfupdate.track = "invalid_mode"' > "$HOME/config.json"
    run bash -c "
        export HOME='$HOME'
        export PATH='$BATS_TEST_TMPDIR/bin:\$PATH'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/commands/selfupdate.sh'
        ask_password() { PASSWORD='test'; B64_PASS='dGVzdA=='; }
        cmd_selfupdate
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be"* ]]
}
