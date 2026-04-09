#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/up.sh

load '../../../test_helper/common'

setup() {
    load_common

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mock sudo: removes -S and executes the rest
    cat > "$BATS_TEST_TMPDIR/bin/sudo" << 'EOF'
#!/bin/bash
shift  # remove -S
exec "$@"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sudo"

    # Mock docker: returns according to $DOCKER_COMPOSE_RC (default 0)
    cat > "$BATS_TEST_TMPDIR/bin/docker" << 'EOF'
#!/bin/bash
exit "${DOCKER_COMPOSE_RC:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"

    # Mocks before source (will be overwritten when libs are re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-STARTED}"; return "${SSH_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    select_menu()         { SELECTED_IDX=0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=(); _all="false"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }
    export -f ssh_cmd ask_password check_sshpass select_menu \
              find_and_select_pod collect_pod_servers _spin_start _spin_stop

    source "$SCRIPTS_DIR/commands/pod/up.sh"

    # Re-mock after source (libs have been re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-STARTED}"; return "${SSH_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    select_menu()         { SELECTED_IDX=0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=(); _all="false"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }

    # Globals required for up_local / up_remote
    export SELECTED_POD="api"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
    export POD_DIR="$BATS_TEST_TMPDIR/pods/api"
    export POD_COMPOSE="$BATS_TEST_TMPDIR/pods/api/docker-compose.yml"
    export B64_PASS="dGVzdHBhc3M="
    mkdir -p "$BATS_TEST_TMPDIR/pods"

    # Counters required by iterate_pod_servers / print_summary
    absent=()
    success_count=0
    warn_count=0
    failure_count=0
    pod_servers=()
    _all="false"
}

# ── up_local ───────────────────────────────────────────────────────────────────

@test "up_local: POD_DIR absent → return 0 + warn 'not found'" {
    run up_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "up_local: POD_DIR absent → absent updated" {
    absent=()
    up_local > /dev/null
    [ "${#absent[@]}" -eq 1 ]
}

@test "up_local: docker compose up succeeds → return 0 + ok 'started successfully'" {
    mkdir -p "$POD_DIR"
    run up_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"started successfully"* ]]
}

@test "up_local: docker compose up fails → return 1 + err 'failed'" {
    mkdir -p "$POD_DIR"
    export DOCKER_COMPOSE_RC=1
    run up_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]]
}

# ── up_remote ──────────────────────────────────────────────────────────────────

@test "up_remote: SSH → STARTED → return 0 + ok 'started successfully'" {
    SSH_CMD_OUTPUT="STARTED"
    run up_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"started successfully"* ]]
}

@test "up_remote: SSH → ABSENT → return 0 + warn 'not found'" {
    SSH_CMD_OUTPUT="ABSENT"
    run up_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "up_remote: SSH → ABSENT → absent updated with short_name" {
    SSH_CMD_OUTPUT="ABSENT"
    absent=()
    up_remote "dev1.fleet.test" > /dev/null
    [ "${#absent[@]}" -eq 1 ]
    [[ "${absent[0]}" == *"dev1"* ]]
}

@test "up_remote: SSH → FAILED → return 1 + err 'failed'" {
    SSH_CMD_OUTPUT="FAILED"
    run up_remote "dev1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]]
}

@test "up_remote: SSH → unexpected result → return 1 + err 'failed'" {
    SSH_CMD_OUTPUT="UNEXPECTED"
    run up_remote "dev1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]]
}

# ── cmd_pod_up — validation ───────────────────────────────────────────────────

@test "cmd_pod_up: without -p → exit 1 + 'search term is required'" {
    run cmd_pod_up
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "cmd_pod_up: -p without argument → exit 1 + 'requires an argument'" {
    run cmd_pod_up -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_pod_up: unknown option -z → exit 1 + 'Unknown option'" {
    run cmd_pod_up -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_pod_up: find_and_select_pod fails → exit 1" {
    find_and_select_pod() { err "No pod matching \"nosuch\""; exit 1; }
    run cmd_pod_up -p nosuch
    [ "$status" -eq 1 ]
}

# ── cmd_pod_up — behavior ─────────────────────────────────────────────────────

@test "cmd_pod_up: section header displays SELECTED_POD and label" {
    iterate_pod_servers() { return 0; }
    run cmd_pod_up -p api
    [[ "$output" == *"api"* ]]
    [[ "$output" == *"ALL"* ]]
}

@test "cmd_pod_up: -e dev → label DEV in header" {
    MOCK_LABEL="DEV"
    iterate_pod_servers() { return 0; }
    run cmd_pod_up -p api -e dev
    [[ "$output" == *"DEV"* ]]
}

@test "cmd_pod_up: iterate_pod_servers is called" {
    iterate_pod_servers() { echo "ITERATE_CALLED"; }
    run cmd_pod_up -p api
    [[ "$output" == *"ITERATE_CALLED"* ]]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "up_local: direct call, POD_DIR absent → warn (coverage)" {
    absent=()
    up_local > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "not found" "$BATS_TEST_TMPDIR/out.txt"
}

@test "up_remote: direct call, STARTED → ok 'started' (coverage)" {
    SSH_CMD_OUTPUT="STARTED"
    absent=()
    up_remote "dev1.fleet.test" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "started" "$BATS_TEST_TMPDIR/out.txt"
}
