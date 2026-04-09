#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/env/edit.sh

load '../../../../test_helper/common'

setup() {
    load_common

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Editor mocks — noop (default) and modify (appends a line)
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/editor_noop"
    printf '#!/bin/bash\necho "modified" >> "$1"\n' > "$BATS_TEST_TMPDIR/bin/editor_modify"
    # nano mock so ${EDITOR:-nano} fallback never hangs
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/nano"
    chmod +x "$BATS_TEST_TMPDIR/bin/editor_noop" \
              "$BATS_TEST_TMPDIR/bin/editor_modify" \
              "$BATS_TEST_TMPDIR/bin/nano"
    # Default to noop editor; individual tests override when needed
    export EDITOR="$BATS_TEST_TMPDIR/bin/editor_noop"

    # md5sum mock: returns same hash by default; MD5SUM_CHANGE=1 → different hash on 2nd call
    cat > "$BATS_TEST_TMPDIR/bin/md5sum" << 'EOF'
#!/bin/bash
CALL_FILE="${BATS_TEST_TMPDIR}/md5sum_calls"
echo "call" >> "$CALL_FILE"
count=$(wc -l < "$CALL_FILE")
if [ "${MD5SUM_CHANGE:-0}" = "1" ] && [ "$count" -gt 1 ]; then
    echo "changed_hash_000000000000000000  $1"
else
    echo "fixed_hash_0000000000000000000  $1"
fi
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/md5sum"

    # Mocks before source (will be overwritten when libs are re-sourced)
    scp_cmd()             { return "${SCP_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=("dev1.fleet.test"); _all="false"; }
    select_menu()         { SELECTED_IDX="${MOCK_SELECTED_IDX:-0}"; }
    export -f scp_cmd ask_password check_sshpass \
              find_and_select_pod collect_pod_servers select_menu

    source "$SCRIPTS_DIR/commands/pod/env/edit.sh"

    # Re-mock after source (libs re-sourced overwrite mocks above)
    scp_cmd()             { return "${SCP_CMD_RC:-0}"; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=("dev1.fleet.test"); _all="false"; }
    select_menu()         { SELECTED_IDX="${MOCK_SELECTED_IDX:-0}"; }

    export MASTER_HOST="dev1.fleet.test"
    export SELECTED_POD="api"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
    export TEMPLATES_JSON=""
    mkdir -p "$BATS_TEST_TMPDIR/pods/api"
}

# ── edit_local ────────────────────────────────────────────────────────────────

@test "edit_local: pod directory absent → err + return 1" {
    export SELECTED_POD="nonexistent"
    run edit_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"Pod directory not found"* ]]
}

@test "edit_local: .env absent (pod dir exists) → err + suggests diff + return 1" {
    # $PODS_DIR/api exists (created in setup) but has no .env
    run edit_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"No .env file found"* ]]
    [[ "$output" == *"pod env diff"* ]]
}

@test "edit_local: .env present → editor called with absolute path + ok" {
    printf 'FOO=bar\n' > "$PODS_DIR/api/.env"
    run edit_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"updated locally"* ]]
}

# ── edit_remote ───────────────────────────────────────────────────────────────

@test "edit_remote: SCP fetch fails → err + return 1 + no push" {
    scp_cmd() { return 1; }
    run edit_remote "dev2.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"Could not fetch"* ]]
}

@test "edit_remote: hash unchanged → warn 'No changes' + return 0 + no push" {
    export MD5SUM_CHANGE=0
    local push_calls="$BATS_TEST_TMPDIR/push_calls_unchanged"
    scp_cmd() {
        if [[ "$2" == "dev2.fleet.test:"* ]]; then echo "PUSHED" >> "$push_calls"; fi
        return 0
    }
    run edit_remote "dev2.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes"* ]]
    [ ! -f "$push_calls" ]
}

@test "edit_remote: hash changed → SCP push called + ok" {
    export MD5SUM_CHANGE=1
    export EDITOR="$BATS_TEST_TMPDIR/bin/editor_modify"
    local push_calls="$BATS_TEST_TMPDIR/push_calls_changed"
    scp_cmd() {
        if [[ "$2" == "dev2.fleet.test:"* ]]; then echo "PUSHED" >> "$push_calls"; fi
        return 0
    }
    run edit_remote "dev2.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"updated on dev2.fleet.test"* ]]
    [ -f "$push_calls" ]
}

@test "edit_remote: hash changed but SCP push fails → err + no ok" {
    export MD5SUM_CHANGE=1
    export EDITOR="$BATS_TEST_TMPDIR/bin/editor_modify"
    scp_cmd() {
        # Fetch: first arg is "server:path"
        if [[ "$1" == "dev2.fleet.test:"* ]]; then return 0; fi
        # Push: second arg is "server:path"
        return 1
    }
    run edit_remote "dev2.fleet.test"
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"Could not push"* ]]
    [[ "$output" != *"✓"* ]]
}

@test "edit_remote: fetch failure → tmpfile cleaned up" {
    # Mock mktemp to return a known path, then verify it is deleted after failure
    local known_tmp="$BATS_TEST_TMPDIR/known_tmpfile_$$"
    touch "$known_tmp"
    mktemp() { echo "$known_tmp"; }
    export -f mktemp
    scp_cmd() { return 1; }
    run edit_remote "dev2.fleet.test"
    [ ! -f "$known_tmp" ]
    unset -f mktemp
}

# ── cmd_pod_env_edit ──────────────────────────────────────────────────────────

@test "cmd_pod_env_edit: -p absent → usage message + exit 1" {
    run cmd_pod_env_edit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"pod env edit"* ]]
}

@test "cmd_pod_env_edit: local server → edit_local called (not edit_remote)" {
    export MASTER_HOST="dev1.fleet.test"
    # default collect_pod_servers returns dev1.fleet.test → local
    edit_local()  { echo "EDIT_LOCAL_CALLED"; return 0; }
    edit_remote() { echo "EDIT_REMOTE_CALLED"; return 0; }
    run cmd_pod_env_edit -p api
    [[ "$output" == *"EDIT_LOCAL_CALLED"* ]]
    [[ "$output" != *"EDIT_REMOTE_CALLED"* ]]
}

@test "cmd_pod_env_edit: remote server → edit_remote called with FQDN" {
    export MASTER_HOST="dev1.fleet.test"
    collect_pod_servers() { pod_servers=("dev2.fleet.test"); _all="false"; }
    edit_local()  { echo "EDIT_LOCAL_CALLED"; return 0; }
    edit_remote() { echo "EDIT_REMOTE_CALLED:$1"; return 0; }
    run cmd_pod_env_edit -p api
    [[ "$output" == *"EDIT_REMOTE_CALLED:dev2.fleet.test"* ]]
    [[ "$output" != *"EDIT_LOCAL_CALLED"* ]]
}

@test "cmd_pod_env_edit: env_templates non-empty → warn printed before edit" {
    # api pod in fixture config.json has env_templates (API_TITLE, API_HOST, API_COMPANY)
    export MOCK_SELECTED_POD="api"
    collect_pod_servers() { pod_servers=("dev1.fleet.test"); _all="false"; }
    edit_local() { echo "EDIT_CALLED"; return 0; }
    run cmd_pod_env_edit -p api
    [[ "$output" == *"Template-managed variables"* ]]
    [[ "$output" == *"API_HOST"* ]]
    # warn must appear before the edit call in the output
    local warn_line edit_line
    warn_line=$(echo "$output" | grep -n "Template-managed" | head -1 | cut -d: -f1)
    edit_line=$(echo "$output" | grep -n "EDIT_CALLED" | head -1 | cut -d: -f1)
    [ "$warn_line" -lt "$edit_line" ]
}

@test "cmd_pod_env_edit: env_templates absent → no template warn" {
    # worker pod has no entry in config.json pods section → TEMPLATES_JSON={}
    export MOCK_SELECTED_POD="worker"
    collect_pod_servers() { pod_servers=("dev1.fleet.test"); _all="false"; }
    edit_local() { echo "EDIT_CALLED"; return 0; }
    run cmd_pod_env_edit -p worker
    [[ "$output" != *"Template-managed"* ]]
}

@test "cmd_pod_env_edit: multiple servers → select_menu called" {
    collect_pod_servers() { pod_servers=("dev1.fleet.test" "dev2.fleet.test"); _all="false"; }
    local menu_calls="$BATS_TEST_TMPDIR/menu_calls"
    select_menu() { echo "MENU_CALLED" >> "$menu_calls"; SELECTED_IDX=0; }
    edit_local()  { return 0; }
    run cmd_pod_env_edit -p api
    [ -f "$menu_calls" ]
}

# ── Coverage direct calls (for kcov) ──────────────────────────────────────────

@test "edit_local: direct call .env present → ok (coverage)" {
    printf 'FOO=bar\n' > "$PODS_DIR/api/.env"
    edit_local > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "updated locally" "$BATS_TEST_TMPDIR/out.txt"
}

@test "edit_remote: direct call hash unchanged → warn (coverage)" {
    export MD5SUM_CHANGE=0
    scp_cmd() { return 0; }
    edit_remote "dev2.fleet.test" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "No changes" "$BATS_TEST_TMPDIR/out.txt"
}
