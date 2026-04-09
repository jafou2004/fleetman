#!/usr/bin/env bats
# Integration tests for scripts/commands/status.sh
# Invoked via scripts/bin/fleetman (real entry point).

load '../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    setup_fixtures

    # Mock openssl: silent password decryption
    cat > "$BATS_TEST_TMPDIR/bin/openssl" << 'EOF'
#!/bin/bash
printf 'testpassword'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/openssl"

    # Mock ssh: simulates Docker/container checks based on $SSH_RESULT_MODE
    cat > "$BATS_TEST_TMPDIR/bin/ssh" << 'EOF'
#!/bin/bash
# Filter SSH options (-i key, -o ...) to isolate host + command
args=()
skip_next=0
for arg in "$@"; do
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    case "$arg" in
        -i|-o|-p) skip_next=1 ;;
        -*)       ;;
        *)        args+=("$arg") ;;
    esac
done
case "${SSH_RESULT_MODE:-ok}" in
    ok)           printf 'docker:ok\npod_ok:nginx\npod_ok:app\n' ;;
    docker_error) echo "docker:error" ;;
    pod_missing)  printf 'docker:ok\npod_missing:nginx\npod_ok:app\n' ;;
    pod_warn)     printf 'docker:ok\npod_warn:nginx:exited\npod_ok:app\n' ;;
esac
exit "${SSH_EXIT_CODE:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"

    # Fleet key + passfile → silent ask_password, check_sshpass no-op
    touch "$HOME/.ssh/fleet_key" "$HOME/.fleet_pass.enc"
    export FLEET_KEY="$HOME/.ssh/fleet_key"
    export FLEET_PASS_FILE="$HOME/.fleet_pass.enc"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "fleetman status -h: displays the docblock (Usage)" {
    run bash "$SCRIPTS_DIR/bin/fleetman" status -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"status"* ]]
}

@test "fleetman status --help: exit 0 and displays the docblock" {
    run bash "$SCRIPTS_DIR/bin/fleetman" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ── Validation ────────────────────────────────────────────────────────────────

@test "fleetman status: unknown option → exit 1 + error message" {
    run bash "$SCRIPTS_DIR/bin/fleetman" status -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "fleetman status: invalid -e → exit 1" {
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e nosuchenv
    [ "$status" -eq 1 ]
}

# ── Output format ─────────────────────────────────────────────────────────────

@test "fleetman status -e test: displays the 'Fleet status' header" {
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [[ "$output" == *"Fleet status"* ]]
    [[ "$output" == *"TEST"* ]]
}

@test "fleetman status: no -e → ALL label in header" {
    run bash "$SCRIPTS_DIR/bin/fleetman" status
    [[ "$output" == *"ALL"* ]]
}

# ── Nominal remote path ───────────────────────────────────────────────────────

@test "fleetman status -e test: Docker and containers ok → exit 0" {
    export SSH_RESULT_MODE=ok
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [ "$status" -eq 0 ]
}

@test "fleetman status -e test: all ok → summary displays ✓" {
    export SSH_RESULT_MODE=ok
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [[ "$output" == *"✓"* ]]
}

@test "fleetman status: iterates over all environments (dev, test, prod)" {
    export SSH_RESULT_MODE=ok
    run bash "$SCRIPTS_DIR/bin/fleetman" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
}

# ── Path remote: Docker error ─────────────────────────────────────────────────

@test "fleetman status -e test: docker:error → exit non-zero" {
    export SSH_RESULT_MODE=docker_error
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [ "$status" -ne 0 ]
}

@test "fleetman status -e test: docker:error → summary displays ✗" {
    export SSH_RESULT_MODE=docker_error
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [[ "$output" == *"✗"* ]]
}

# ── Remote path: SSH unreachable ──────────────────────────────────────────────

@test "fleetman status -e test: SSH fails (rc=255) → exit non-zero" {
    export SSH_EXIT_CODE=255
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [ "$status" -ne 0 ]
}

@test "fleetman status -e test: SSH fails (rc=255) → summary displays ✗" {
    export SSH_EXIT_CODE=255
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [[ "$output" == *"✗"* ]]
}

# ── Remote path: containers with warning ──────────────────────────────────────

@test "fleetman status -e test: pod_missing → summary displays ⚠" {
    export SSH_RESULT_MODE=pod_missing
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [[ "$output" == *"⚠"* ]]
}

@test "fleetman status -e test: pod_warn:nginx:exited → summary displays ⚠" {
    export SSH_RESULT_MODE=pod_warn
    run bash "$SCRIPTS_DIR/bin/fleetman" status -e test
    [[ "$output" == *"⚠"* ]]
}
