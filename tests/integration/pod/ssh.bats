#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/ssh.sh
# Invoked via scripts/bin/fleetman (real entry point).

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    # dummy fleet_key to pass check_sshpass without sshpass
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/fleet_key"
    # dummy ssh to avoid any real connection attempt
    cat > "$BATS_TEST_TMPDIR/bin/ssh" << 'EOF'
#!/bin/bash
echo "SSH_MOCK:$*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
}

# ── Help ───────────────────────────────────────────────────────────────────────

@test "fleetman pod ssh -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod ssh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod ssh"* ]]
}

@test "fleetman pod ssh --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod ssh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman pod -h: lists 'ssh' as an available subcommand" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"ssh"* ]]
}

# ── Basic validation ──────────────────────────────────────────────────────────

@test "fleetman pod ssh: no -p → exit 1 + 'search term is required'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod ssh
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "fleetman pod ssh -p without argument: exit 1 + 'requires an argument'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod ssh -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "fleetman pod ssh -p api -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod ssh -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

# ── Missing pods.json ─────────────────────────────────────────────────────────

@test "fleetman pod ssh: missing pods.json → exit 1 + error message" {
    rm -f "$PODS_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" pod ssh -p api
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

# ── No results ────────────────────────────────────────────────────────────────

@test "fleetman pod ssh -p nonexistent: exit 0 + warn 'No results'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod ssh -p nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"No results"* ]]
}

@test "fleetman pod ssh -p nonexistent -e dev: exit 0 + warn 'No results'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod ssh -p nonexistent -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *"No results"* ]]
}
