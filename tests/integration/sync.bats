#!/usr/bin/env bats
# Integration tests for scripts/commands/sync.sh
# Invoked via scripts/bin/fleetman (real entry point) or directly via cmd_sync.
# sync.sh is a command file (not an entry point) — no main() guard.

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/rsync"
    chmod +x "$BATS_TEST_TMPDIR/bin/rsync"
    setup_fixtures
}

# ── Via the fleetman dispatcher ───────────────────────────────────────────────

@test "fleetman sync -h: displays the sync.sh docblock" {
    # Bypass key / password — testing help only
    run bash "$SCRIPTS_DIR/bin/fleetman" sync -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Synchronizes"* ]]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman sync --help: displays the sync.sh docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" sync --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Via cmd_sync directly (source the file then call the function) ────────────

@test "cmd_sync: missing config → exit 1 with warn message" {
    rm -f "$HOME/config.json"
    # mock sshpass pour passer check_sshpass
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sshpass"
    chmod +x "$BATS_TEST_TMPDIR/bin/sshpass"
    run bash -c "
        export HOME='$HOME'
        export PATH='$BATS_TEST_TMPDIR/bin:\$PATH'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/lib/iterate.sh'
        source '$SCRIPTS_DIR/commands/sync.sh'
        check_sshpass
        check_config_file
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"⚠"* ]]
}

@test "cmd_sync: neither fleet_key nor sshpass in PATH → exit 1" {
    rm -f "$HOME/.ssh/fleet_key"
    # Minimal PATH without sshpass or fleet_key
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

@test "cmd_sync: fleet_key present → passes check_sshpass" {
    touch "$HOME/.ssh/fleet_key"
    # vars.sh defines FLEET_KEY="$HOME/.ssh/fleet_key" — file exists so check_sshpass returns 0
    run bash -c "
        export HOME='$HOME'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        check_sshpass
        echo 'PASS'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# ── Quick mode ─────────────────────────────────────────────────────────────────

@test "fleetman sync -h: output contains '-q' and 'quick'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" sync -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"-q"* ]]
    [[ "$output" == *"quick"* ]]
}

# ── Full mode (-f) ─────────────────────────────────────────────────────────────

@test "fleetman sync -h: output contains '-f' and 'full'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" sync -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"-f"* ]]
    [[ "$output" == *"full"* ]]
}

@test "fleetman sync -f -h: exit 0 (help intercepted before auth)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" sync -f -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "cmd_sync -q -f: exit 1 with incompatibility message" {
    touch "$HOME/.ssh/fleet_key"
    run bash -c "
        export HOME='$HOME'
        export PATH='$BATS_TEST_TMPDIR/bin:\$PATH'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/lib/iterate.sh'
        source '$SCRIPTS_DIR/lib/bashrc.sh'
        source '$SCRIPTS_DIR/commands/sync.sh'
        cmd_sync -q -f
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"incompatibles"* ]]
}

@test "cmd_sync -f: Phase 1c present in output" {
    touch "$HOME/.ssh/fleet_key"
    run bash -c "
        export HOME='$HOME'
        export PATH='$BATS_TEST_TMPDIR/bin:\$PATH'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/lib/iterate.sh'
        source '$SCRIPTS_DIR/lib/bashrc.sh'
        source '$SCRIPTS_DIR/commands/sync.sh'
        check_sshpass()           { :; }
        ask_password()            { :; }
        ensure_user_aliases()     { :; }
        load_pods_data()          { PODS_DATA='{}'; }
        generate_ascii_files()    { :; }
        collect_all_pods()        { :; }
        collect_all_services()    { :; }
        iterate_servers()         { :; }
        print_summary()           { :; }
        cmd_sync -f
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Phase 1c"* ]]
}

@test "cmd_sync -q: sections Phase 1a and Phase 1b absent, Phase 2 present" {
    touch "$HOME/.ssh/fleet_key"
    run bash -c "
        export HOME='$HOME'
        export PATH='$BATS_TEST_TMPDIR/bin:\$PATH'
        source '$SCRIPTS_DIR/lib/vars.sh'
        source '$SCRIPTS_DIR/lib/display.sh'
        source '$SCRIPTS_DIR/lib/auth.sh'
        source '$SCRIPTS_DIR/lib/config.sh'
        source '$SCRIPTS_DIR/lib/iterate.sh'
        source '$SCRIPTS_DIR/lib/bashrc.sh'
        source '$SCRIPTS_DIR/commands/sync.sh'
        check_sshpass()        { :; }
        ask_password()         { :; }
        ensure_user_aliases()  { :; }
        load_pods_data()       { PODS_DATA='{}'; }
        generate_ascii_files() { :; }
        collect_all_pods()     { :; }
        iterate_servers()      { :; }
        print_summary()        { :; }
        cmd_sync -q
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"Phase 1a"* ]]
    [[ "$output" != *"Phase 1b"* ]]
    [[ "$output" == *"Phase 2"* ]]
}
