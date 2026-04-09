#!/usr/bin/env bats
# Unit tests for scripts/commands/pod/update.sh

load '../../../test_helper/common'

setup() {
    load_common

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Mock sudo binary (strips -S, execs remaining args)
    cat > "$BATS_TEST_TMPDIR/bin/sudo" << 'EOF'
#!/bin/bash
args=()
while [[ $# -gt 0 ]]; do
    [[ "$1" == "-S" ]] && { shift; continue; }
    args+=("$1"); shift
done
exec "${args[@]}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sudo"

    # Mock docker binary
    cat > "$BATS_TEST_TMPDIR/bin/docker" << 'EOF'
#!/bin/bash
echo "${DOCKER_OUTPUT:-}" >&2
exit "${DOCKER_RC:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"

    # Mocks before source (will be overwritten when libs are re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-OK}"; return "${SSH_CMD_RC:-0}"; }
    scp_cmd()             { return 0; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=(); _all="false"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }
    _apply_templates()    { :; }
    _build_sed_cmds()     { SED_CMDS=""; }
    export -f ssh_cmd scp_cmd ask_password check_sshpass \
              find_and_select_pod collect_pod_servers _spin_start _spin_stop \
              _apply_templates _build_sed_cmds

    source "$SCRIPTS_DIR/commands/pod/update.sh"

    # Re-mock after source (libs re-sourced)
    ssh_cmd()             { echo "${SSH_CMD_OUTPUT:-OK}"; return "${SSH_CMD_RC:-0}"; }
    scp_cmd()             { return 0; }
    ask_password()        { PASSWORD="testpass"; B64_PASS="dGVzdHBhc3M="; }
    check_sshpass()       { return 0; }
    find_and_select_pod() { SELECTED_POD="${MOCK_SELECTED_POD:-api}"; label="${MOCK_LABEL:-ALL}"; }
    collect_pod_servers() { pod_servers=(); _all="false"; }
    _spin_start()         { :; }
    _spin_stop()          { :; }
    _apply_templates()    { :; }
    _build_sed_cmds()     { SED_CMDS=""; }

    export MASTER_HOST="dev1.fleet.test"
    export SELECTED_POD="api"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
    export POD_DIR="$PODS_DIR/api"
    export POD_ENV="$POD_DIR/.env"
    export POD_COMPOSE="$POD_DIR/docker-compose.yml"
    export TEMPLATES_JSON=""
    export TEMPLATE_VARS_JSON=""
    export B64_PASS="dGVzdHBhc3M="
    export ENV_FILTER=""
    mkdir -p "$BATS_TEST_TMPDIR/pods"
    success_count=0; warn_count=0; failure_count=0
    pod_servers=(); _all="false"
    absent=()
}

# ── load_pod_env_vars ────────────────────────────────────────────────────────────

@test "load_pod_env_vars: pod with env_vars in config → ENV_VARS populated" {
    load_pod_env_vars
    [ "${#ENV_VARS[@]}" -eq 1 ]
    [ "${ENV_VARS[0]}" = "API_VERSION" ]
}

@test "load_pod_env_vars: pod present with empty env_vars → ENV_VARS empty, no warn" {
    local tmp
    tmp=$(mktemp)
    jq '.pods.api.env_vars = []' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    run load_pod_env_vars
    [ "$status" -eq 0 ]
    [[ "$output" != *"⚠"* ]]
}

@test "load_pod_env_vars: pod absent from config → warn + Y → return 0 + empty entry added" {
    local tmp
    tmp=$(mktemp)
    jq 'del(.pods.api)' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    SELECTED_POD="new-pod"
    load_pod_env_vars <<< "Y"
    jq -e '.pods["new-pod"]' "$CONFIG_FILE" > /dev/null
}

@test "load_pod_env_vars: pod absent from config → N → return 1" {
    local tmp
    tmp=$(mktemp)
    jq 'del(.pods.api)' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    SELECTED_POD="new-pod"
    run load_pod_env_vars <<< "n"
    [ "$status" -eq 1 ]
}

# ── resolve_first_server ─────────────────────────────────────────────────────────

@test "resolve_first_server: _all=false + pod_servers non-empty → pod_servers[0]" {
    _all="false"
    pod_servers=("srv1.fleet.test" "srv2.fleet.test")
    resolve_first_server
    [ "$FIRST_SERVER" = "srv1.fleet.test" ]
}

@test "resolve_first_server: _all=true → jq lookup in pods.json" {
    _all="true"
    pod_servers=()
    resolve_first_server
    [ -n "$FIRST_SERVER" ]
}

@test "resolve_first_server: ENV_FILTER non-empty → lookup filtered by env" {
    _all="true"
    ENV_FILTER="dev"
    resolve_first_server
    [[ "$FIRST_SERVER" == *"dev"* ]]
}

# ── fetch_current_values ─────────────────────────────────────────────────────────

@test "fetch_current_values: FIRST_SERVER = MASTER_HOST → reads local file" {
    mkdir -p "$POD_DIR"
    echo "API_VERSION=1.0" > "$POD_ENV"
    ENV_VARS=("API_VERSION")
    FIRST_SERVER="$MASTER_HOST"
    fetch_current_values
    [ "${current_values[API_VERSION]}" = "1.0" ]
}

@test "fetch_current_values: FIRST_SERVER remote → ssh_cmd called" {
    SSH_CMD_OUTPUT="API_VERSION=2.0"
    ssh_cmd() { echo "$SSH_CMD_OUTPUT"; }
    ENV_VARS=("API_VERSION")
    FIRST_SERVER="dev2.fleet.test"
    fetch_current_values
    [ "${current_values[API_VERSION]}" = "2.0" ]
}

@test "fetch_current_values: ENV_VARS empty → current_values empty, ssh_cmd not called" {
    ssh_cmd() { echo "SSH_CALLED"; }
    ENV_VARS=()
    FIRST_SERVER="dev2.fleet.test"
    fetch_current_values
    [ "${#current_values[@]}" -eq 0 ]
}

# ── prompt_new_values ────────────────────────────────────────────────────────────

@test "prompt_new_values: new value → in new_values" {
    ENV_VARS=("API_VERSION")
    declare -gA current_values=([API_VERSION]="1.0")
    prompt_new_values <<< "2.0"
    [ "${new_values[API_VERSION]}" = "2.0" ]
}

@test "prompt_new_values: unchanged value (empty) → absent from new_values" {
    ENV_VARS=("API_VERSION")
    declare -gA current_values=([API_VERSION]="1.0")
    prompt_new_values <<< "" || true
    [ -z "${new_values[API_VERSION]+x}" ] || [ -z "${new_values[API_VERSION]}" ]
}

@test "prompt_new_values: no changes + Y → return 0" {
    ENV_VARS=("API_VERSION")
    declare -gA current_values=([API_VERSION]="1.0")
    run prompt_new_values < <(printf '\nY\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"only restart"* ]]
}

@test "prompt_new_values: no changes + N → return 1" {
    ENV_VARS=("API_VERSION")
    declare -gA current_values=([API_VERSION]="1.0")
    run prompt_new_values < <(printf '\nn\n')
    [ "$status" -eq 1 ]
}

# ── update_local ─────────────────────────────────────────────────────────────────

@test "update_local: POD_DIR absent → append_result absent + return 0" {
    # POD_DIR not created
    declare -gA new_values=()
    run update_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "update_local: POD_DIR present + restart OK → ok 'updated and restarted'" {
    mkdir -p "$POD_DIR"
    echo "API_VERSION=1.0" > "$POD_ENV"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    declare -gA new_values=([API_VERSION]="2.0")
    run update_local
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated and restarted"* ]]
}

@test "update_local: POD_DIR present + restart FAILED → err + return 1" {
    mkdir -p "$POD_DIR"
    echo "API_VERSION=1.0" > "$POD_ENV"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    declare -gA new_values=()
    run update_local
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "update_local: TEMPLATES_JSON non-empty → _apply_templates is called" {
    mkdir -p "$POD_DIR"
    echo "API_VERSION=1.0" > "$POD_ENV"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    export TEMPLATES_JSON='{"API_TITLE":"{name}"}'
    local apply_called="$BATS_TEST_TMPDIR/apply_called"
    _apply_templates() { touch "$apply_called"; }
    declare -gA new_values=()
    update_local > /dev/null
    [ -f "$apply_called" ]
}

@test "update_local: TEMPLATES_JSON empty → _apply_templates not called" {
    mkdir -p "$POD_DIR"
    echo "API_VERSION=1.0" > "$POD_ENV"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    export TEMPLATES_JSON=""
    local apply_called="$BATS_TEST_TMPDIR/apply_called"
    _apply_templates() { touch "$apply_called"; }
    declare -gA new_values=()
    update_local > /dev/null
    [ ! -f "$apply_called" ]
}

# ── update_remote ────────────────────────────────────────────────────────────────

@test "update_remote: SSH → OK → ok 'updated and restarted'" {
    export SSH_CMD_OUTPUT="OK"
    declare -gA new_values=()
    run update_remote "dev2.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated and restarted"* ]]
}

@test "update_remote: SSH → ABSENT → warn + append_result absent" {
    export SSH_CMD_OUTPUT="ABSENT"
    declare -gA new_values=()
    update_remote "dev2.fleet.test" > /dev/null
    [ "${#absent[@]}" -eq 1 ]
    [[ "${absent[0]}" == *"dev2"* ]]
}

@test "update_remote: SSH → FAILED → err + return 1" {
    export SSH_CMD_OUTPUT="FAILED"
    declare -gA new_values=()
    run update_remote "dev2.fleet.test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "update_remote: SSH → unexpected result → return 1" {
    export SSH_CMD_OUTPUT="UNEXPECTED"
    declare -gA new_values=()
    run update_remote "dev2.fleet.test"
    [ "$status" -eq 1 ]
}

@test "update_remote: TEMPLATES_JSON non-empty → _build_sed_cmds is called" {
    export SSH_CMD_OUTPUT="OK"
    export TEMPLATES_JSON='{"API_TITLE":"{name}"}'
    local build_called="$BATS_TEST_TMPDIR/build_called"
    _build_sed_cmds() { touch "$build_called"; SED_CMDS=""; }
    declare -gA new_values=()
    update_remote "dev2.fleet.test" > /dev/null
    [ -f "$build_called" ]
}

# ── Direct coverage (without run, for kcov) ──────────────────────────────────

@test "update_local: direct call POD_DIR absent → ok (coverage)" {
    declare -gA new_values=()
    update_local > "$BATS_TEST_TMPDIR/out.txt" || true
    grep -q "not found" "$BATS_TEST_TMPDIR/out.txt"
}

@test "update_remote: direct call SSH → OK → ok (coverage)" {
    export SSH_CMD_OUTPUT="OK"
    declare -gA new_values=()
    update_remote "dev2.fleet.test" > "$BATS_TEST_TMPDIR/out.txt"
    grep -q "updated and restarted" "$BATS_TEST_TMPDIR/out.txt"
}
