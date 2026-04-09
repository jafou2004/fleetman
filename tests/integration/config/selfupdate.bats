#!/usr/bin/env bats
# Integration tests for scripts/commands/config/selfupdate.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    # fleet_key to bypass check_sshpass
    touch "$HOME/.ssh/fleet_key"
}

# ── Via the fleetman dispatcher ───────────────────────────────────────────────

@test "fleetman config selfupdate -h: displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config selfupdate -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Configures automatic update"* ]]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman config selfupdate --help: exit 0 + displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config selfupdate --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Prerequisites validation ──────────────────────────────────────────────────

@test "cmd_config_selfupdate: missing config.json → exit 1" {
    rm -f "$HOME/config.json"
    run bash -c "
        export HOME='$HOME'
        export CONFIG_FILE='$HOME/config.json'
        export PATH='$BATS_TEST_TMPDIR/bin:$PATH'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/lib/ui.sh'
        source '$SCRIPTS_DIR/commands/config/selfupdate.sh'
        cmd_config_selfupdate
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

# ── Command present in the config menu ───────────────────────────────────────

@test "fleetman config -h: displays 'Selfupdate' in the subcommand list" {
    run bash "$SCRIPTS_DIR/bin/fleetman" config -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"elf"* ]]
}
