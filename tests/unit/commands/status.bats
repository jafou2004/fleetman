#!/usr/bin/env bats
# Unit tests for scripts/commands/status.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    load_common

    # Neutralize the spinner
    _spin_start() { :; }
    _spin_stop()  { :; }

    # Mock ask_password: avoids interactive prompt
    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }

    # Mock ssh_cmd: returns $SSH_RESULT, exits $SSH_RC
    ssh_cmd() { echo "$SSH_RESULT"; return "${SSH_RC:-0}"; }

    # Mock sudo_run: simulates docker info / docker inspect
    sudo_run() {
        if [[ "$*" == *"docker info"* ]]; then
            return "${DOCKER_INFO_RC:-0}"
        elif [[ "$*" == *"docker inspect"* ]]; then
            echo "${CONTAINER_STATUS:-running}"
        fi
    }

    # fleet_key present → check_sshpass is no-op
    touch "$HOME/.ssh/fleet_key"
    export FLEET_KEY="$HOME/.ssh/fleet_key"

    source "$SCRIPTS_DIR/commands/status.sh"

    # Re-mock after sourcing (libs re-sourced by status.sh)
    ask_password() { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    ssh_cmd()      { echo "$SSH_RESULT"; return "${SSH_RC:-0}"; }
    sudo_run() {
        if [[ "$*" == *"docker info"* ]]; then
            return "${DOCKER_INFO_RC:-0}"
        elif [[ "$*" == *"docker inspect"* ]]; then
            echo "${CONTAINER_STATUS:-running}"
        fi
    }
    _spin_start() { :; }
    _spin_stop()  { :; }

    # MASTER_HOST outside the test fleet → all servers are "remote"
    export MASTER_HOST="master.local"
}

# ── Option validation ────────────────────────────────────────────────────────

@test "cmd_status: unknown option → exit 1 + error message" {
    run cmd_status -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_status: option -e without argument → exit 1 + error message" {
    run cmd_status -e
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_status: -e invalid → exit 1" {
    run cmd_status -e nosuchenv
    [ "$status" -eq 1 ]
}

# ── Section header ────────────────────────────────────────────────────────────

@test "cmd_status: displays the 'Fleet status' header" {
    run cmd_status -e test
    [[ "$output" == *"Fleet status"* ]]
}

@test "cmd_status: -e test → label TEST in header" {
    run cmd_status -e test
    [[ "$output" == *"TEST"* ]]
}

@test "cmd_status: without -e → label ALL in the header" {
    run cmd_status
    [[ "$output" == *"ALL"* ]]
}

# ── status_local: Docker ok ───────────────────────────────────────────────────

@test "status_local: Docker ok → ok 'SSH: local'" {
    export DOCKER_INFO_RC=0
    run status_local
    [[ "$output" == *"SSH: local"* ]]
}

@test "status_local: Docker ok → ok 'Docker: running'" {
    export DOCKER_INFO_RC=0
    run status_local
    [[ "$output" == *"Docker: running"* ]]
}

@test "status_local: container running → ok '<name>: running'" {
    export DOCKER_INFO_RC=0
    export CONTAINER_STATUS="running"
    run status_local
    [[ "$output" == *"nginx: running"* ]]
    [[ "$output" == *"app: running"* ]]
}

@test "status_local: container stopped → warn with state 'exited'" {
    export DOCKER_INFO_RC=0
    export CONTAINER_STATUS="exited"
    run status_local
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"exited"* ]]
}

@test "status_local: container absent → warn '<name>: not found'" {
    export DOCKER_INFO_RC=0
    sudo_run() {
        if [[ "$*" == *"docker info"* ]]; then return 0; fi
        if [[ "$*" == *"docker inspect"* ]]; then echo ""; fi
    }
    run status_local
    [[ "$output" == *"not found"* ]]
}

@test "status_local: all ok → ok 'Status: ok' at end + exit 0" {
    export DOCKER_INFO_RC=0
    export CONTAINER_STATUS="running"
    run status_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"Status: ok"* ]]
}

# ── status_local: Docker ko ───────────────────────────────────────────────────

@test "status_local: Docker ko → err 'Docker: not running'" {
    export DOCKER_INFO_RC=1
    run status_local
    [[ "$output" == *"Docker: not running"* ]]
}

@test "status_local: Docker ko → exit 1" {
    export DOCKER_INFO_RC=1
    run status_local
    [ "$status" -eq 1 ]
}

@test "status_local: Docker ko → no 'Status: ok'" {
    export DOCKER_INFO_RC=1
    run status_local
    [[ "$output" != *"Status: ok"* ]]
}

# ── status_remote: SSH ────────────────────────────────────────────────────────

@test "status_remote: SSH unreachable (rc=255) → err 'SSH: unreachable' + exit 1" {
    export SSH_RC=255
    export SSH_RESULT=""
    run status_remote "remote1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SSH: unreachable"* ]]
}

@test "status_remote: empty SSH result (rc=0) → SSH: ok without error" {
    export SSH_RC=0
    export SSH_RESULT=""
    run status_remote "remote1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH: ok"* ]]
}

@test "status_remote: SSH ok → ok 'SSH: ok'" {
    export SSH_RC=0
    export SSH_RESULT=$'docker:ok\npod_ok:nginx\npod_ok:app'
    run status_remote "remote1.fleet.test"
    [[ "$output" == *"SSH: ok"* ]]
}

# ── status_remote: Docker ─────────────────────────────────────────────────────

@test "status_remote: docker:ok → ok 'Docker: running'" {
    export SSH_RC=0
    export SSH_RESULT="docker:ok"
    run status_remote "remote1.fleet.test"
    [[ "$output" == *"Docker: running"* ]]
}

@test "status_remote: docker:error → err 'Docker: not running' + exit 1" {
    export SSH_RC=0
    export SSH_RESULT="docker:error"
    run status_remote "remote1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Docker: not running"* ]]
}

# ── status_remote: containers ─────────────────────────────────────────────────

@test "status_remote: pod_ok:nginx → ok 'nginx: running'" {
    export SSH_RC=0
    export SSH_RESULT=$'docker:ok\npod_ok:nginx\npod_ok:app'
    run status_remote "remote1.fleet.test"
    [[ "$output" == *"nginx: running"* ]]
    [[ "$output" == *"app: running"* ]]
}

@test "status_remote: pod_missing:nginx → warn 'nginx: not found'" {
    export SSH_RC=0
    export SSH_RESULT=$'docker:ok\npod_missing:nginx'
    run status_remote "remote1.fleet.test"
    [[ "$output" == *"nginx: not found"* ]]
    [[ "$output" == *"⚠"* ]]
}

@test "status_remote: pod_warn:nginx:exited → warn 'nginx: exited'" {
    export SSH_RC=0
    export SSH_RESULT=$'docker:ok\npod_warn:nginx:exited'
    run status_remote "remote1.fleet.test"
    [[ "$output" == *"nginx: exited"* ]]
    [[ "$output" == *"⚠"* ]]
}

@test "status_remote: all ok → ok 'Status: ok' + exit 0" {
    export SSH_RC=0
    export SSH_RESULT=$'docker:ok\npod_ok:nginx\npod_ok:app'
    run status_remote "remote1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Status: ok"* ]]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "status_remote: direct call → ssh_cmd called (coverage)" {
    ssh_cmd() { echo "SSH_DIRECT:$1" >> "$BATS_TEST_TMPDIR/ssh_calls"; echo "docker:ok"; }
    status_remote "test1.fleet.test" > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "SSH_DIRECT:test1.fleet.test" "$BATS_TEST_TMPDIR/ssh_calls"
}

@test "status_local: direct call → sudo_run called (coverage)" {
    export DOCKER_INFO_RC=0
    export CONTAINER_STATUS="running"
    status_local > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "Docker: running" "$BATS_TEST_TMPDIR/out.txt"
}

# ── cmd_status: git clone server display ─────────────────────────────────────

@test "cmd_status: displays the git clone server if GIT_SERVER_FILE present" {
    mkdir -p "$HOME/.data"
    echo "git.server.test" > "$GIT_SERVER_FILE"
    run cmd_status
    [[ "$output" == *"Git clone: git"* ]]
}

@test "cmd_status: does not display git clone if GIT_SERVER_FILE absent" {
    rm -f "$GIT_SERVER_FILE"
    run cmd_status
    [[ "$output" != *"Git clone:"* ]]
}
