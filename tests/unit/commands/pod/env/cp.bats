#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/env/cp.sh

load '../../../../test_helper/common'

setup() {
    load_common

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mocks before source (will be overwritten when libs are re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-UPDATED}"; return "${SSH_CMD_RC:-0}"; }
    scp_cmd()             { return "${SCP_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=(); _all="false"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }
    export -f ssh_cmd scp_cmd ask_password check_sshpass \
              find_and_select_pod collect_pod_servers _spin_start _spin_stop

    source "$SCRIPTS_DIR/commands/pod/env/cp.sh"

    # Re-mock after source (libs re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-UPDATED}"; return "${SSH_CMD_RC:-0}"; }
    scp_cmd()             { return "${SCP_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=(); _all="false"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }

    # Globals for tests — MASTER_HOST must be in pods.json fixture
    export MASTER_HOST="dev1.fleet.test"
    export SELECTED_POD="api"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
    export POD_DIR="$PODS_DIR/api"
    export POD_ENV="$POD_DIR/.env"
    export TEMPLATES_JSON=""
    export TEMPLATE_VARS_JSON=""
    export B64_PASS="dGVzdHBhc3M="
    mkdir -p "$BATS_TEST_TMPDIR/pods"

    success_count=0
    warn_count=0
    failure_count=0
    pod_servers=()
    _all="false"
}

# ── cp_local ────────────────────────────────────────────────────────────────────

@test "cp_local: TEMPLATES_JSON empty → return 0 + '.env already local'" {
    export TEMPLATES_JSON=""
    run cp_local
    [ "$status" -eq 0 ]
    [[ "$output" == *".env already local"* ]]
}

@test "cp_local: templates present + .env exists → return 0 + '.env updated'" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    mkdir -p "$POD_DIR"
    echo "MY_VAR=old" > "$POD_ENV"
    run cp_local
    [ "$status" -eq 0 ]
    [[ "$output" == *".env updated"* ]]
}

@test "cp_local: templates present + .env absent → return 1 + err" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    # POD_DIR not created → POD_ENV does not exist
    run cp_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "cp_local: templates applied → variable updated in file (coverage)" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    mkdir -p "$POD_DIR"
    echo "MY_VAR=old" > "$POD_ENV"
    cp_local > /dev/null
    grep -q "MY_VAR=dev1.fleet.test" "$POD_ENV"
}

# ── cp_remote ───────────────────────────────────────────────────────────────────

@test "cp_remote: scp fails → return 1 + 'Failed to copy'" {
    export SCP_CMD_RC=1
    run cp_remote "dev2.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to copy"* ]]
}

@test "cp_remote: TEMPLATES_JSON empty + scp ok → return 0 + '.env propagated'" {
    export TEMPLATES_JSON=""
    run cp_remote "dev2.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *".env propagated"* ]]
}

@test "cp_remote: SSH → UPDATED → return 0 + 'templates applied'" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    export SSH_CMD_OUTPUT="UPDATED"
    run cp_remote "dev2.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"templates applied"* ]]
}

@test "cp_remote: SSH → SED_FAILED → return 1 + err" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    export SSH_CMD_OUTPUT="SED_FAILED"
    run cp_remote "dev2.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "cp_remote: SSH → unexpected result → return 1 + err" {
    export TEMPLATES_JSON='{"MY_VAR":"{hostname}"}'
    export SSH_CMD_OUTPUT="UNEXPECTED"
    run cp_remote "dev2.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

# ── cmd_pod_env_cp ──────────────────────────────────────────────────────────────

@test "cmd_pod_env_cp: without -p → exit 1 + 'search term is required'" {
    run cmd_pod_env_cp
    [ "$status" -eq 1 ]
    [[ "$output" == *"search term is required"* ]]
}

@test "cmd_pod_env_cp: .env absent → exit 1 before ask_password" {
    ask_password() { echo "ASK_PASSWORD_CALLED"; }
    # POD_DIR not created → POD_ENV does not exist
    run cmd_pod_env_cp -p api
    [ "$status" -eq 1 ]
    [[ "$output" != *"ASK_PASSWORD_CALLED"* ]]
}

@test "cmd_pod_env_cp: iterate_pod_servers is called" {
    mkdir -p "$POD_DIR"
    echo "MY_VAR=old" > "$POD_ENV"
    iterate_pod_servers() { echo "ITERATE_CALLED"; }
    run cmd_pod_env_cp -p api
    [[ "$output" == *"ITERATE_CALLED"* ]]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "cp_local: direct call without templates → ok (coverage)" {
    export TEMPLATES_JSON=""
    cp_local > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q ".env already local" "$BATS_TEST_TMPDIR/out.txt"
}

@test "cp_remote: direct call scp ok without templates → ok (coverage)" {
    export TEMPLATES_JSON=""
    cp_remote "dev2.fleet.test" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q ".env propagated" "$BATS_TEST_TMPDIR/out.txt"
}
