#!/usr/bin/env bats
# Integration tests for scripts/commands/ssh.sh
# Invoked via scripts/bin/fleetman (real entry point).

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    setup_fixtures
    # Dummy fleet_key so check_sshpass passes without sshpass
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/fleet_key"
    # Dummy ssh to avoid real connection attempts
    cat > "$BATS_TEST_TMPDIR/bin/ssh" << 'EOF'
#!/bin/bash
echo "SSH_MOCK:$*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "fleetman ssh -h: exit 0 + shows Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" ssh -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"fleetman ssh"* ]]
}

@test "fleetman ssh --help: exit 0 + shows Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" ssh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman -h: lists 'ssh' as a command" {
    run bash "$SCRIPTS_DIR/bin/fleetman" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"ssh"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "fleetman ssh -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" ssh -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

@test "fleetman ssh -e without argument: exit 1 + 'requires an argument'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" ssh -e
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

# ── No results ────────────────────────────────────────────────────────────────

@test "fleetman ssh -s nonexistent: exit 0 + warn 'No servers found'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" ssh -s nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"No servers found"* ]]
}

@test "fleetman ssh -e dev -s nonexistent: exit 0 + warn" {
    run bash "$SCRIPTS_DIR/bin/fleetman" ssh -e dev -s nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"No servers found"* ]]
}
