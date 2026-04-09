#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/pull.sh

load '../../../test_helper/common'

setup() {
    load_common

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mock git: returns according to $GIT_PULL_RC (default 0)
    cat > "$BATS_TEST_TMPDIR/bin/git" << 'EOF'
#!/bin/bash
exit "${GIT_PULL_RC:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/git"

    # Mocks before source (will be overwritten when libs are re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-OK}"; return "${SSH_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    select_menu()         { SELECTED_IDX=0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=(); _all="false"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }
    export -f ssh_cmd ask_password check_sshpass select_menu \
              find_and_select_pod collect_pod_servers _spin_start _spin_stop

    source "$SCRIPTS_DIR/commands/pod/pull.sh"

    # Re-mock after source (libs have been re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-OK}"; return "${SSH_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    select_menu()         { SELECTED_IDX=0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=(); _all="false"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }

    # Globals required for pull_local / pull_remote
    export SELECTED_POD="api"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
    export POD_DIR="$BATS_TEST_TMPDIR/pods/api"
    export B64_PASS="dGVzdHBhc3M="
    mkdir -p "$BATS_TEST_TMPDIR/pods"

    # Counters required by iterate_pod_servers / print_summary
    # No absent=() — pull.sh does not use this array
    success_count=0
    warn_count=0
    failure_count=0
    pod_servers=()
    _all="false"
}

# ── pull_local ─────────────────────────────────────────────────────────────────

@test "pull_local: POD_DIR absent → return 0 + warn 'not found'" {
    run pull_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "pull_local: POD_DIR absent → absent array not modified (append_result not called)" {
    absent=()
    pull_local > /dev/null
    [ "${#absent[@]}" -eq 0 ]
}

@test "pull_local: git pull succeeds → return 0 + ok 'git pull successful'" {
    mkdir -p "$POD_DIR"
    run pull_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"git pull successful"* ]]
}

@test "pull_local: git pull fails → return 1 + err 'failed'" {
    mkdir -p "$POD_DIR"
    export GIT_PULL_RC=1
    run pull_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]]
}

# ── pull_remote ────────────────────────────────────────────────────────────────

@test "pull_remote: SSH → OK → return 0 + ok 'git pull successful'" {
    SSH_CMD_OUTPUT="OK"
    run pull_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git pull successful"* ]]
}

@test "pull_remote: SSH → ABSENT → return 0 + warn 'not found'" {
    SSH_CMD_OUTPUT="ABSENT"
    run pull_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "pull_remote: SSH → FAILED → return 1 + err 'failed'" {
    SSH_CMD_OUTPUT="FAILED"
    run pull_remote "dev1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]]
}

@test "pull_remote: SSH → unexpected result → return 1 + err 'failed'" {
    SSH_CMD_OUTPUT="UNEXPECTED"
    run pull_remote "dev1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed"* ]]
}

# ── cmd_pod_pull — validation ──────────────────────────────────────────────────

@test "cmd_pod_pull: sans -p → exit 1 + 'search term is required'" {
    run cmd_pod_pull
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "cmd_pod_pull: -p sans argument → exit 1 + 'requires an argument'" {
    run cmd_pod_pull -p
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_pod_pull: option inconnue -z → exit 1 + 'Unknown option'" {
    run cmd_pod_pull -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_pod_pull: find_and_select_pod fails → exit 1" {
    find_and_select_pod() { err "No pod matching \"nosuch\""; exit 1; }
    run cmd_pod_pull -p nosuch
    [ "$status" -eq 1 ]
}

# ── cmd_pod_pull — behavior ───────────────────────────────────────────────────

@test "cmd_pod_pull: section header displays SELECTED_POD and label" {
    iterate_pod_servers() { return 0; }
    run cmd_pod_pull -p api
    [[ "$output" == *"api"* ]]
    [[ "$output" == *"ALL"* ]]
}

@test "cmd_pod_pull: -e dev → label DEV in the header" {
    MOCK_LABEL="DEV"
    iterate_pod_servers() { return 0; }
    run cmd_pod_pull -p api -e dev
    [[ "$output" == *"DEV"* ]]
}

@test "cmd_pod_pull: iterate_pod_servers is called" {
    iterate_pod_servers() { echo "ITERATE_CALLED"; }
    run cmd_pod_pull -p api
    [[ "$output" == *"ITERATE_CALLED"* ]]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "pull_local: direct call, POD_DIR absent → warn (coverage)" {
    pull_local > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "not found" "$BATS_TEST_TMPDIR/out.txt"
}

@test "pull_remote: direct call, OK → ok 'git pull successful' (coverage)" {
    SSH_CMD_OUTPUT="OK"
    pull_remote "dev1.fleet.test" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "git pull successful" "$BATS_TEST_TMPDIR/out.txt"
}
