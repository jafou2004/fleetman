#!/usr/bin/env bats
# Integration tests for scripts/commands/pod/logs.sh
# Invoked via scripts/bin/fleetman (real entry point).
# Covers only error paths and help — interactive streaming
# (docker compose logs -f) cannot be exercised in CI.

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
    # fleet_pass.enc + openssl mock so that ask_password is silent
    # (reached only if results > 0; included as a safety measure)
    touch "$HOME/.fleet_pass.enc"
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
echo "testpass"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"
}

@test "fleetman pod logs -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod logs"* ]]
}

@test "fleetman pod logs --help: exit 0 and displays Usage" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fleetman pod logs -h: -s described as optional in help" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"service"* ]]
    [[ "$output" == *"[-s"* ]]
}

@test "fleetman pod -h: lists 'logs' as an available subcommand" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"logs"* ]]
}

@test "fleetman pod logs: no -p → exit 1 + 'search term is required'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "fleetman pod logs -p without argument: exit 1 + 'requires an argument'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "fleetman pod logs -p api -e nosuchenv: exit 1 + 'invalid environment'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -p api -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

@test "fleetman pod logs: missing pods.json → exit 1 + error message" {
    rm -f "$PODS_FILE"
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -p api
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "fleetman pod logs -p nonexistent: exit 0 + warn 'No results'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -p nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"No results"* ]]
}

@test "fleetman pod logs -p nonexistent -e dev: exit 0 + warn 'No results'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -p nonexistent -e dev
    [ "$status" -eq 0 ]
    [[ "$output" == *"No results"* ]]
}

@test "fleetman pod logs -p nonexistent -s: exit 0 + warn 'No results' (pre-scan OK)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -p nonexistent -s
    [ "$status" -eq 0 ]
    [[ "$output" == *"No results"* ]]
}

@test "fleetman pod logs -p nonexistent -s worker: exit 0 + warn 'No results'" {
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -p nonexistent -s worker
    [ "$status" -eq 0 ]
    [[ "$output" == *"No results"* ]]
}

@test "fleetman pod logs -s without argument: no 'requires an argument' error" {
    # -s without value must no longer trigger the getopts error (pre-scan intercepts)
    run bash "$SCRIPTS_DIR/bin/fleetman" pod logs -p nonexistent -s
    [[ "$output" != *"requires an argument"* ]]
}
