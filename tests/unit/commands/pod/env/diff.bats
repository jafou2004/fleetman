#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/env/diff.sh

load '../../../../test_helper/common'

setup() {
    load_common

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mocks before source (will be overwritten when libs are re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-}"; return "${SSH_CMD_RC:-0}"; }
    scp_cmd()             { return "${SCP_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=("dev1.fleet.test"); _all="false"; }
    select_menu()         { SELECTED_IDX="${MOCK_SELECTED_IDX:-0}"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }
    export -f ssh_cmd scp_cmd ask_password check_sshpass \
              find_and_select_pod collect_pod_servers select_menu _spin_start _spin_stop

    source "$SCRIPTS_DIR/commands/pod/env/diff.sh"

    # Re-mock after source (libs re-sourced overwrite the mocks)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-}"; return "${SSH_CMD_RC:-0}"; }
    scp_cmd()             { return "${SCP_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=("dev1.fleet.test"); _all="false"; }
    select_menu()         { SELECTED_IDX="${MOCK_SELECTED_IDX:-0}"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }

    export MASTER_HOST="dev1.fleet.test"
    export SELECTED_POD="api"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
    export POD_DIR="$PODS_DIR/api"
    export POD_ENV_DIST="$POD_DIR/.env-dist"
    export POD_ENV="$POD_DIR/.env"
    export TEMPLATES_JSON=""
    export TEMPLATE_VARS_JSON=""
    export SERVER=""
    _DIFF_WRITTEN=0
    mkdir -p "$BATS_TEST_TMPDIR/pods/api"
}

# ── run_diff — base cases ─────────────────────────────────────────────────────

@test "run_diff: files in sync → ok + return 0" {
    printf 'FOO=bar\nBAR=baz\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\nBAR=baz\n' > "$POD_ENV"
    run run_diff "$POD_ENV_DIST" "$POD_ENV"
    [ "$status" -eq 0 ]
    [[ "$output" == *"in sync"* ]]
}

@test "run_diff: .env-dist absent → err + return 1" {
    run run_diff "$POD_ENV_DIST" "$POD_ENV"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "run_diff: .env absent → offers to create → creates + return 1" {
    printf 'FOO=bar\n' > "$POD_ENV_DIST"
    run run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "Y"
    [ "$status" -eq 1 ]
    [ -f "$POD_ENV" ]
    [[ "$output" == *".env created"* ]]
}

@test "run_diff: .env absent → declines → no creation + return 1" {
    printf 'FOO=bar\n' > "$POD_ENV_DIST"
    run run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "n"
    [ "$status" -eq 1 ]
    [ ! -f "$POD_ENV" ]
}

@test "run_diff: missing variable (no template) → accepts → added + return 1" {
    printf 'FOO=bar\nBAR=missing\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\n' > "$POD_ENV"
    run run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "Y"
    [ "$status" -eq 1 ]
    grep -q "^BAR=" "$POD_ENV"
}

@test "run_diff: missing variable → declines → no change" {
    printf 'FOO=bar\nBAR=missing\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\n' > "$POD_ENV"
    run run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "n"
    [ "$status" -eq 1 ]
    ! grep -q "^BAR=" "$POD_ENV"
}

@test "run_diff: extra variable → accepts → removed + return 1" {
    printf 'FOO=bar\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\nEXTRA=oops\n' > "$POD_ENV"
    run run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "Y"
    [ "$status" -eq 1 ]
    ! grep -q "^EXTRA=" "$POD_ENV"
}

@test "run_diff: extra variable → declines → unchanged" {
    printf 'FOO=bar\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\nEXTRA=oops\n' > "$POD_ENV"
    run run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "n"
    [ "$status" -eq 1 ]
    grep -q "^EXTRA=" "$POD_ENV"
}

@test "run_diff: missing variable → [template] annotation displayed if in TEMPLATES_JSON" {
    printf 'FOO=bar\nAPI_HOST=default\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\n' > "$POD_ENV"
    export TEMPLATES_JSON='{"API_HOST":"{hostname}"}'
    run run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "n"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[template]"* ]]
}

# ── run_diff — template awareness ─────────────────────────────────────────────

@test "run_diff: missing variable with template + SERVER set → computed value (not .env-dist)" {
    printf 'API_HOST=dist-default\n' > "$POD_ENV_DIST"
    printf '' > "$POD_ENV"
    export TEMPLATES_JSON='{"API_HOST":"{hostname}"}'
    export TEMPLATE_VARS_JSON=''
    export SERVER="dev1.fleet.test"
    run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "Y" || true
    grep -q "^API_HOST=dev1.fleet.test" "$POD_ENV"
    ! grep -q "dist-default" "$POD_ENV"
}

@test "run_diff: missing variable with template + SERVER empty → value from .env-dist" {
    printf 'API_HOST=dist-default\n' > "$POD_ENV_DIST"
    printf '' > "$POD_ENV"
    export TEMPLATES_JSON='{"API_HOST":"{hostname}"}'
    export SERVER=""
    run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "Y" || true
    grep -q "^API_HOST=dist-default" "$POD_ENV"
}

@test "run_diff: variable outside TEMPLATES_JSON → value from .env-dist even if TEMPLATES_JSON defined" {
    printf 'FOO=from-dist\nAPI_HOST=host-dist\n' > "$POD_ENV_DIST"
    printf 'API_HOST=existing\n' > "$POD_ENV"
    export TEMPLATES_JSON='{"API_HOST":"{hostname}"}'
    export SERVER="dev1.fleet.test"
    # FOO is missing but NOT in TEMPLATES_JSON → .env-dist value
    run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "Y" || true
    grep -q "^FOO=from-dist" "$POD_ENV"
}

# ── diff_local ────────────────────────────────────────────────────────────────

@test "diff_local: POD_DIR absent → return 1 + err" {
    export POD_DIR="$BATS_TEST_TMPDIR/nonexistent"
    run diff_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "diff_local: calls run_diff with paths from POD_DIR" {
    printf 'FOO=bar\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\n' > "$POD_ENV"
    run_diff() { echo "RUN_DIFF:$1:$2"; return 0; }
    run diff_local
    [[ "$output" == *"RUN_DIFF:"*".env-dist"* ]]
    [[ "$output" == *".env"* ]]
}

# ── diff_remote ───────────────────────────────────────────────────────────────

@test "diff_remote: scp .env-dist fails → return 1 + err" {
    scp_cmd() {
        if [[ "$1" == *":$POD_ENV_DIST" ]]; then return 1; fi
        return 0
    }
    export SERVER="dev2.fleet.test"
    run diff_remote
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "diff_remote: run_diff return 0, _DIFF_WRITTEN=0 → no push-back in output" {
    scp_cmd() { return 0; }
    run_diff() { _DIFF_WRITTEN=0; return 0; }
    export SERVER="dev2.fleet.test"
    run diff_remote
    [ "$status" -eq 0 ]
    [[ "$output" != *"pushed back"* ]]
    [[ "$output" != *"push .env"* ]]
}

@test "diff_remote: _DIFF_WRITTEN=1 → push-back via scp + ok" {
    scp_cmd() { return 0; }
    run_diff() {
        _DIFF_WRITTEN=1
        printf 'FOO=new\n' > "$2"
        return 1
    }
    export SERVER="dev2.fleet.test"
    run diff_remote
    [[ "$output" == *"pushed back"* ]]
}

@test "diff_remote: push-back scp fails → err" {
    scp_cmd() {
        # Push-back: destination is SERVER:... (second arg starts with server FQDN)
        if [[ "$2" == "$SERVER:"* ]]; then return 1; fi
        return 0
    }
    run_diff() {
        _DIFF_WRITTEN=1
        printf 'FOO=new\n' > "$2"
        return 1
    }
    export SERVER="dev2.fleet.test"
    run diff_remote
    [[ "$output" == *"✗"* ]]
}

# ── cmd_pod_env_diff ──────────────────────────────────────────────────────────

@test "cmd_pod_env_diff: Mode C (no -p, no local files) → exit 1 + message" {
    cd "$BATS_TEST_TMPDIR"
    run cmd_pod_env_diff
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a pod directory"* ]]
}

@test "cmd_pod_env_diff: Mode C with -e only (SEARCH empty) → exit 1" {
    cd "$BATS_TEST_TMPDIR"
    run cmd_pod_env_diff -e dev
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a pod directory"* ]]
}

@test "cmd_pod_env_diff: Mode B (.env-dist present in current directory) → run_diff called" {
    local tmpd="$BATS_TEST_TMPDIR/mypod"
    mkdir -p "$tmpd"
    printf 'FOO=bar\n' > "$tmpd/.env-dist"
    printf 'FOO=bar\n' > "$tmpd/.env"
    run_diff() { echo "RUN_DIFF_CALLED"; return 0; }
    cd "$tmpd"
    run cmd_pod_env_diff
    [[ "$output" == *"RUN_DIFF_CALLED"* ]]
}

@test "cmd_pod_env_diff: Mode A -p api → diff_local called (local server = MASTER_HOST)" {
    diff_local()  { echo "DIFF_LOCAL_CALLED"; return 0; }
    diff_remote() { echo "DIFF_REMOTE_CALLED"; return 0; }
    run cmd_pod_env_diff -p api
    # pod_servers[0] = dev1.fleet.test = MASTER_HOST → diff_local
    [[ "$output" == *"DIFF_LOCAL_CALLED"* ]]
}

@test "cmd_pod_env_diff: Mode A multiple servers → select_menu called" {
    collect_pod_servers() { pod_servers=("dev1.fleet.test" "dev2.fleet.test"); _all="false"; }
    diff_local()  { return 0; }
    diff_remote() { return 0; }
    select_menu() { echo "SELECT_MENU_CALLED"; SELECTED_IDX=0; }
    run cmd_pod_env_diff -p api
    [[ "$output" == *"SELECT_MENU_CALLED"* ]]
}

# ── Direct coverage (without run, for kcov) ───────────────────────────────────

@test "run_diff: direct call sync → ok (coverage)" {
    printf 'FOO=bar\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\n' > "$POD_ENV"
    run_diff "$POD_ENV_DIST" "$POD_ENV" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "in sync" "$BATS_TEST_TMPDIR/out.txt"
}

@test "run_diff: _DIFF_WRITTEN set to 1 after adding missing variable" {
    printf 'FOO=bar\nBAR=missing\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\n' > "$POD_ENV"
    _DIFF_WRITTEN=0
    run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "Y" || true
    [ "$_DIFF_WRITTEN" -eq 1 ]
}

@test "run_diff: _DIFF_WRITTEN set to 1 after removing extra variable" {
    printf 'FOO=bar\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\nEXTRA=oops\n' > "$POD_ENV"
    _DIFF_WRITTEN=0
    run_diff "$POD_ENV_DIST" "$POD_ENV" <<< "Y" || true
    [ "$_DIFF_WRITTEN" -eq 1 ]
}

@test "run_diff: extra + missing simultaneously → two prompts, both accepted" {
    printf 'FOO=bar\nNEW=added\n' > "$POD_ENV_DIST"
    printf 'FOO=bar\nEXTRA=oops\n' > "$POD_ENV"
    _DIFF_WRITTEN=0
    run_diff "$POD_ENV_DIST" "$POD_ENV" < <(printf 'Y\nY\n') || true
    ! grep -q "^EXTRA=" "$POD_ENV"
    grep -q "^NEW=" "$POD_ENV"
    [ "$_DIFF_WRITTEN" -eq 1 ]
}
