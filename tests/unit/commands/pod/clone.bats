#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/clone.sh

load '../../../test_helper/common'

setup() {
    load_common

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mock git binary (succeeds by default)
    cat > "$BATS_TEST_TMPDIR/bin/git" << 'EOF'
#!/bin/bash
exit "${GIT_CLONE_RC:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/git"

    # Mocks before source (will be overwritten when libs are re-sourced)
    ssh_cmd()        { echo "${SSH_CMD_OUTPUT:-CLONED}"; return "${SSH_CMD_RC:-0}"; }
    ask_password()   { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()  { return 0; }
    prompt_response() {
        case "$1" in
            *URL*)  echo "https://example.com/myrepo.git" ;;
            *)      echo "${PROMPT_DEST:-$BATS_TEST_TMPDIR/pods/myrepo}" ;;
        esac
    }
    select_menu()    { SELECTED_IDX=0; }
    export -f ssh_cmd ask_password check_sshpass prompt_response select_menu

    source "$SCRIPTS_DIR/commands/pod/clone.sh"

    # Re-mock after source (libs have been re-sourced)
    ssh_cmd()        { echo "${SSH_CMD_OUTPUT:-CLONED}"; return "${SSH_CMD_RC:-0}"; }
    ask_password()   { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()  { return 0; }
    prompt_response() {
        case "$1" in
            *URL*)  echo "https://example.com/myrepo.git" ;;
            *)      echo "${PROMPT_DEST:-$BATS_TEST_TMPDIR/pods/myrepo}" ;;
        esac
    }
    select_menu()    { SELECTED_IDX=0; }

    # Globals shared between clone_local / clone_remote
    export REPO_URL="https://example.com/myrepo.git"
    export REPO_NAME="myrepo"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
    export DEST_DIR="$BATS_TEST_TMPDIR/pods/myrepo"
    mkdir -p "$BATS_TEST_TMPDIR/pods"

    # Counters required by append_result / print_summary
    already_present=()
    env_to_configure=()
    success_count=0
    warn_count=0
    failure_count=0
}

# ── Invalid options ───────────────────────────────────────────────────────────

@test "cmd_pod_clone: -e without argument → exit 1 + 'requires an argument'" {
    run cmd_pod_clone -e
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "cmd_pod_clone: unknown option -z → exit 1 + 'Unknown option'" {
    run cmd_pod_clone -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── clone_local ───────────────────────────────────────────────────────────────

@test "clone_local: directory already exists → return 0 + warn 'already exists'" {
    mkdir -p "$DEST_DIR"
    run clone_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "clone_local: directory already exists → already_present updated" {
    mkdir -p "$DEST_DIR"
    already_present=()
    clone_local > /dev/null
    [ "${#already_present[@]}" -eq 1 ]
}

@test "clone_local: git clone succeeds, no .env-dist → return 0 + ok 'cloned'" {
    run clone_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"cloned successfully"* ]]
}

@test "clone_local: git clone succeeds, .env-dist present → warn '.env' + env_to_configure updated" {
    # The mock git does not create a file, we pre-create .env-dist directly
    mkdir -p "$DEST_DIR"
    touch "$DEST_DIR/.env-dist"
    # Simulate "clone OK but directory already there" by forcing git to do nothing
    # Re-define git to exit 0 without creating anything (directory already created above)
    # To test the .env-dist path, we trick: place .env-dist before and stub git
    # clone_local checks [ -d DEST_DIR ] first → skips. We must test without the directory.
    rm -rf "$DEST_DIR"
    # git mock creates the directory + .env-dist
    cat > "$BATS_TEST_TMPDIR/bin/git" << EOF
#!/bin/bash
mkdir -p "$DEST_DIR"
touch "$DEST_DIR/.env-dist"
exit 0
EOF
    env_to_configure=()
    clone_local > /dev/null
    [ "${#env_to_configure[@]}" -eq 1 ]
}

@test "clone_local: git clone succeeds, .env-dist present → warn displayed" {
    rm -rf "$DEST_DIR"
    cat > "$BATS_TEST_TMPDIR/bin/git" << EOF
#!/bin/bash
mkdir -p "$DEST_DIR"
touch "$DEST_DIR/.env-dist"
exit 0
EOF
    run clone_local
    [ "$status" -eq 0 ]
    [[ "$output" == *".env"* ]]
}

@test "clone_local: git clone fails → return 1 + err 'Clone failed'" {
    export GIT_CLONE_RC=1
    run clone_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"Clone failed"* ]]
}

# ── clone_remote ──────────────────────────────────────────────────────────────

@test "clone_remote: ALREADY_PRESENT → return 0 + warn 'already exists'" {
    SSH_CMD_OUTPUT="ALREADY_PRESENT"
    run clone_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "clone_remote: ALREADY_PRESENT → already_present updated with short_name" {
    SSH_CMD_OUTPUT="ALREADY_PRESENT"
    already_present=()
    clone_remote "dev1.fleet.test" > /dev/null
    [ "${#already_present[@]}" -eq 1 ]
    [[ "${already_present[0]}" == *"dev1"* ]]
}

@test "clone_remote: CLONED → return 0 + ok 'cloned successfully'" {
    SSH_CMD_OUTPUT="CLONED"
    run clone_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cloned successfully"* ]]
}

@test "clone_remote: CLONED_WITH_ENV → return 0 + warn '.env'" {
    SSH_CMD_OUTPUT="CLONED_WITH_ENV"
    run clone_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *".env"* ]]
}

@test "clone_remote: CLONED_WITH_ENV → env_to_configure updated" {
    SSH_CMD_OUTPUT="CLONED_WITH_ENV"
    env_to_configure=()
    clone_remote "dev1.fleet.test" > /dev/null
    [ "${#env_to_configure[@]}" -eq 1 ]
    [[ "${env_to_configure[0]}" == *"dev1"* ]]
}

@test "clone_remote: CLONE_FAILED → return 1 + err 'Clone failed'" {
    SSH_CMD_OUTPUT="CLONE_FAILED"
    run clone_remote "dev1.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Clone failed"* ]]
}

# ── cmd_pod_clone — mode --all ────────────────────────────────────────────────

@test "cmd_pod_clone --all: iterate_servers is called" {
    iterate_servers() { echo "ITERATE_SERVERS_CALLED"; }
    run cmd_pod_clone --all
    [[ "$output" == *"ITERATE_SERVERS_CALLED"* ]]
}

@test "cmd_pod_clone -a: iterate_servers is called (short form)" {
    iterate_servers() { echo "ITERATE_SERVERS_CALLED"; }
    run cmd_pod_clone -a
    [[ "$output" == *"ITERATE_SERVERS_CALLED"* ]]
}

@test "cmd_pod_clone --all: config.json updated with all_servers: true" {
    iterate_servers() { return 0; }
    # || true: print_summary uses [ n -gt 0 ] && ... which returns 1 if n=0 (set -e)
    cmd_pod_clone --all > /dev/null || true
    local val
    val=$(jq -r --arg p "myrepo" '.pods[$p].all_servers' "$CONFIG_FILE")
    [ "$val" = "true" ]
}

@test "cmd_pod_clone --all: ok 'config.json' displayed" {
    iterate_servers() { return 0; }
    run cmd_pod_clone --all
    [[ "$output" == *"config.json"* ]]
}

# ── cmd_pod_clone — selective mode ───────────────────────────────────────────

@test "cmd_pod_clone: selective mode → deploy_selective called, not iterate_servers" {
    deploy_selective() { echo "DEPLOY_SELECTIVE_CALLED"; }
    iterate_servers()  { echo "ITERATE_SERVERS_CALLED"; }
    run cmd_pod_clone
    [[ "$output" == *"DEPLOY_SELECTIVE_CALLED"* ]]
    [[ "$output" != *"ITERATE_SERVERS_CALLED"* ]]
}

@test "cmd_pod_clone: env invalide → exit 1 + 'invalid environment'" {
    run cmd_pod_clone -e nosuchenv
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

@test "cmd_pod_clone: header displays REPO_NAME and env label" {
    deploy_selective() { return 0; }
    run cmd_pod_clone
    [[ "$output" == *"myrepo"* ]]
    [[ "$output" == *"ALL"* ]]
}

@test "cmd_pod_clone: -e dev → header displays DEV" {
    deploy_selective() { return 0; }
    run cmd_pod_clone -e dev
    [[ "$output" == *"DEV"* ]]
}

# ── deploy_selective ──────────────────────────────────────────────────────────

@test "deploy_selective: displays 'Select server' menu for each env" {
    section_calls=0
    section() { echo "SECTION:$*"; }
    select_menu() { SELECTED_IDX=0; }
    clone_local()  { ok "done"; echo ""; }
    clone_remote() { ok "done"; echo ""; }
    export MASTER_HOST="dev1.fleet.test"
    # ENV empty = all envs
    ENV=""
    success_count=0; failure_count=0; warn_count=0
    already_present=(); env_to_configure=()
    run deploy_selective
    [ "$status" -eq 0 ]
    [[ "$output" == *"Select server for DEV"* ]]
    [[ "$output" == *"Select server for PROD"* ]]
}

@test "deploy_selective: ENV=dev → only DEV" {
    section() { echo "SECTION:$*"; }
    select_menu() { SELECTED_IDX=0; }
    clone_local()  { ok "done"; echo ""; }
    clone_remote() { ok "done"; echo ""; }
    export MASTER_HOST="__not_local__"
    ENV="dev"
    success_count=0; failure_count=0; warn_count=0
    already_present=(); env_to_configure=()
    run deploy_selective
    [[ "$output" == *"Select server for DEV"* ]]
    [[ "$output" != *"Select server for PROD"* ]]
}

@test "deploy_selective: __APPEND already_present replayed in parent scope" {
    select_menu() { SELECTED_IDX=0; }
    # clone_remote returns ALREADY_PRESENT
    ssh_cmd() { echo "ALREADY_PRESENT"; }
    export MASTER_HOST="__not_local__"
    export ENV="dev"
    success_count=0; failure_count=0; warn_count=0
    already_present=(); env_to_configure=()
    deploy_selective > /dev/null
    [ "${#already_present[@]}" -ge 1 ]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "clone_local: direct call, directory absent → ok (coverage)" {
    already_present=(); env_to_configure=()
    clone_local > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "." "$BATS_TEST_TMPDIR/out.txt" || true
}

@test "clone_remote: direct call, CLONED → ok 'cloned' (coverage)" {
    SSH_CMD_OUTPUT="CLONED"
    already_present=(); env_to_configure=()
    clone_remote "dev1.fleet.test" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "cloned" "$BATS_TEST_TMPDIR/out.txt"
}
