#!/usr/bin/env bats
# Unit tests for scripts/commands/sync.sh

load '../../test_helper/common'

setup() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    load_common
    # Neutralize the spinner
    _spin_start() { :; }
    _spin_stop()  { :; }
    # Neutralize ssh_cmd, scp_cmd, rsync_cmd (functions, not binaries)
    ssh_cmd() { echo "SSH:$*"; }
    scp_cmd() { echo "SCP:$*"; }
    rsync_cmd() { echo "RSYNC:$*"; }
    # Source the command file
    source "$SCRIPTS_DIR/commands/sync.sh"
    # Re-neutralize after sourcing (sync.sh may re-source them via lib)
    ssh_cmd() { echo "SSH:$*"; }
    scp_cmd() { echo "SCP:$*"; }
    rsync_cmd() { echo "RSYNC:$*"; }
    _spin_start() { :; }
    _spin_stop()  { :; }
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
    # Create required directories
    mkdir -p "$HOME/.data" "$HOME/scripts/bin"
    export DATA_DIR="$HOME/.data"
    export SCRIPTS_DIR_BIN="$HOME/scripts"
    touch "$HOME/scripts/bin/fleetman"
    export USER_ALIASES_FILE="$HOME/.bash_aliases"
}

# ── ensure_user_aliases ────────────────────────────────────────────────────────

@test "ensure_user_aliases: file absent → creates ~/.bash_aliases" {
    rm -f "$HOME/.bash_aliases"
    ensure_user_aliases
    [ -f "$HOME/.bash_aliases" ]
}

@test "ensure_user_aliases: created file contains a header comment" {
    rm -f "$HOME/.bash_aliases"
    ensure_user_aliases
    grep -q "Personal aliases" "$HOME/.bash_aliases"
}

@test "ensure_user_aliases: file present → does not modify it" {
    echo "# my custom alias" > "$HOME/.bash_aliases"
    ensure_user_aliases
    grep -q "my custom alias" "$HOME/.bash_aliases"
}

# ── generate_ascii_files ───────────────────────────────────────────────────────

@test "generate_ascii_files: creates a .ascii file for each server in config" {
    # Use `run` to avoid exit 1 from (( count++ )) when count=0 under set -e
    run generate_ascii_files
    # fixtures/config.json has 5 servers
    local count
    count=$(find "$HOME/.data" -name 'welcome_*.ascii' 2>/dev/null | wc -l)
    [ "$count" -eq 5 ]
}

@test "generate_ascii_files: .ascii files contain exactly 2 lines" {
    run generate_ascii_files
    local file lines
    file=$(find "$HOME/.data" -name 'welcome_*.ascii' | head -1)
    lines=$(wc -l < "$file")
    [ "$lines" -eq 2 ]
}

@test "generate_ascii_files: correct naming (short name of server)" {
    run generate_ascii_files
    [ -f "$HOME/.data/welcome_dev1.ascii" ]
    [ -f "$HOME/.data/welcome_prod2.ascii" ]
}

# ── sync_local ─────────────────────────────────────────────────────────────────

@test "sync_local: adds BEGIN FLEETMAN block to ~/.bashrc if absent" {
    touch "$HOME/.bashrc"
    sync_local
    grep -q '# BEGIN FLEETMAN' "$HOME/.bashrc"
    grep -q '# END FLEETMAN' "$HOME/.bashrc"
}

@test "sync_local: idempotent — does not duplicate the block" {
    touch "$HOME/.bashrc"
    sync_local
    sync_local
    local count
    count=$(grep -c '# BEGIN FLEETMAN' "$HOME/.bashrc")
    [ "$count" -eq 1 ]
}

@test "sync_local: generates ~/.data/fleetman.sh" {
    touch "$HOME/.bashrc"
    sync_local
    [ -f "$DATA_DIR/fleetman.sh" ]
}

@test "sync_local: fleetman.sh contains export PATH" {
    touch "$HOME/.bashrc"
    sync_local
    grep -q 'PATH.*scripts/bin' "$DATA_DIR/fleetman.sh"
}

@test "sync_local: affiche 'internal/*.sh made executable'" {
    touch "$HOME/.bashrc"
    run sync_local
    [[ "$output" == *"internal/*.sh made executable"* ]]
}

@test "sync_local: writes FQDN cache to DATA_DIR/fqdn" {
    touch "$HOME/.bashrc"
    sync_local
    [ -f "$DATA_DIR/fqdn" ]
}

@test "sync_local: writes git_server to GIT_SERVER_FILE if .git present" {
    touch "$HOME/.bashrc"
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/fleetman"
    mkdir -p "$FLEETMAN_DIR/.git"
    sync_local
    [ -f "$GIT_SERVER_FILE" ]
}

@test "sync_local: does not create GIT_SERVER_FILE if no local .git" {
    touch "$HOME/.bashrc"
    export FLEETMAN_DIR="$BATS_TEST_TMPDIR/no-clone"
    rm -f "$GIT_SERVER_FILE"
    sync_local
    [ ! -f "$GIT_SERVER_FILE" ]
}

@test "sync_local: welcome.enabled=false → fleetman.sh sans welcome.sh" {
    local updated
    updated=$(jq '.welcome = {"enabled": false}' "$CONFIG_FILE")
    printf '%s\n' "$updated" > "$CONFIG_FILE"
    touch "$HOME/.bashrc"
    sync_local
    ! grep -q 'welcome\.sh' "$DATA_DIR/fleetman.sh"
}

# ── sync_remote ────────────────────────────────────────────────────────────────

@test "sync_remote: output contains expected ✓ messages" {
    touch "$HOME/.bash_aliases"
    rsync_cmd() { return 0; }
    ssh_cmd() { echo "F_ADDED"; }

    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
}

@test "sync_remote: result F_ADDED → ok message 'block added'" {
    touch "$HOME/.bash_aliases"
    rsync_cmd() { return 0; }
    ssh_cmd() { echo "F_ADDED"; }
    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"block added"* ]]
}

@test "sync_remote: runs hostname -f to cache the remote FQDN" {
    touch "$HOME/.bash_aliases"
    local ssh_log="$BATS_TEST_TMPDIR/ssh_log"
    rsync_cmd() { return 0; }
    ssh_cmd() { echo "$*" >> "$ssh_log"; echo "F_ADDED"; }
    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    grep -q 'hostname -f' "$ssh_log"
}

@test "sync_remote: no F_ADDED → no 'block added' message" {
    touch "$HOME/.bash_aliases"
    rsync_cmd() { return 0; }
    ssh_cmd() { return 0; }
    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" != *"block added"* ]]
}

@test "sync_remote: calls rsync_cmd with --delete for scripts/" {
    touch "$HOME/.bash_aliases"
    local rsync_log="$BATS_TEST_TMPDIR/rsync_log"
    rsync_cmd() { echo "$*" >> "$rsync_log"; return 0; }
    ssh_cmd() { echo "F_ADDED"; }

    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    grep -q -- '--delete' "$rsync_log"
}

@test "sync_remote: calls rsync_cmd with --exclude=fqdn for .data/" {
    touch "$HOME/.bash_aliases"
    local rsync_log="$BATS_TEST_TMPDIR/rsync_log"
    rsync_cmd() { echo "$*" >> "$rsync_log"; return 0; }
    ssh_cmd() { echo "F_ADDED"; }

    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    grep -q -- '--exclude=fqdn' "$rsync_log"
}

@test "sync_remote: always syncs scripts/ even with QUICK_MODE=true" {
    QUICK_MODE=true
    touch "$HOME/.bash_aliases"
    local rsync_log="$BATS_TEST_TMPDIR/rsync_log"
    rsync_cmd() { echo "$*" >> "$rsync_log"; return 0; }
    ssh_cmd() { echo "F_ADDED"; }

    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    grep -q -- '--delete' "$rsync_log"
}

@test "sync_remote: output contains 'scripts/ synced'" {
    touch "$HOME/.bash_aliases"
    rsync_cmd() { return 0; }
    ssh_cmd() { echo "F_ADDED"; }

    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"scripts/ synced"* ]]
}

@test "sync_remote: fleet_key + passfile present → fleet key deployed" {
    touch "$HOME/.bash_aliases"
    touch "$FLEET_KEY"
    touch "$FLEET_PASS_FILE"
    rsync_cmd() { return 0; }
    ssh_cmd() { echo "F_ADDED"; }
    local scp_log="$BATS_TEST_TMPDIR/scp_log"
    scp_cmd() { echo "$*" >> "$scp_log"; return 0; }

    run sync_remote "dev1.fleet.test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fleet key"* ]]
}

# ── parse_args ─────────────────────────────────────────────────────────────────

@test "parse_args: no argument → success" {
    run parse_args
    [ "$status" -eq 0 ]
}

@test "parse_args: unknown option → exit 1 with error message" {
    run parse_args -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "parse_args: -q → exit 0" {
    run parse_args -q
    [ "$status" -eq 0 ]
}

@test "parse_args: --quick → exit 0" {
    run parse_args --quick
    [ "$status" -eq 0 ]
}

@test "parse_args: -q sets QUICK_MODE=true" {
    QUICK_MODE=false
    parse_args -q
    [ "$QUICK_MODE" = "true" ]
}

@test "parse_args: --quick sets QUICK_MODE=true" {
    QUICK_MODE=false
    parse_args --quick
    [ "$QUICK_MODE" = "true" ]
}

@test "parse_args: no quick flag → QUICK_MODE stays false" {
    QUICK_MODE=false
    parse_args
    [ "$QUICK_MODE" = "false" ]
}

@test "parse_args: -f → FULL_MODE=true" {
    FULL_MODE=false
    parse_args -f
    [ "$FULL_MODE" = "true" ]
}

@test "parse_args: --full → FULL_MODE=true" {
    FULL_MODE=false
    parse_args --full
    [ "$FULL_MODE" = "true" ]
}

@test "parse_args: -f alone does not modify QUICK_MODE" {
    QUICK_MODE=false
    parse_args -f
    [ "$QUICK_MODE" = "false" ]
}

@test "parse_args: -q -f → exit 1 with incompatibility message" {
    run parse_args -q -f
    [ "$status" -eq 1 ]
    [[ "$output" == *"incompatibles"* ]]
}

# ── load_pods_data ─────────────────────────────────────────────────────────────

@test "load_pods_data: pods.json absent → PODS_DATA equals {}" {
    rm -f "$PODS_FILE"
    load_pods_data
    [ "$PODS_DATA" = "{}" ]
}

@test "load_pods_data: pods.json present → loads content into PODS_DATA" {
    load_pods_data
    echo "$PODS_DATA" | jq -e '.dev' > /dev/null
}

@test "load_pods_data: creates DATA_DIR if absent" {
    rm -rf "$DATA_DIR"
    rm -f "$PODS_FILE"
    load_pods_data
    [ -d "$DATA_DIR" ]
}

# ── collect_env ────────────────────────────────────────────────────────────────

@test "collect_env: adds env key into PODS_DATA with servers" {
    PODS_DATA="{}"
    MASTER_HOST="notaserver"
    ssh_cmd() { echo "api"; echo "worker"; }
    collect_env "dev"
    count=$(echo "$PODS_DATA" | jq '.dev | keys | length')
    [ "$count" -eq 2 ]
}

@test "collect_env: empty pods → sets [] for that server" {
    PODS_DATA="{}"
    MASTER_HOST="notaserver"
    ssh_cmd() { return 0; }
    collect_env "dev"
    result=$(echo "$PODS_DATA" | jq -r '.dev["dev1.fleet.test"]')
    [ "$result" = "[]" ]
}

@test "collect_env: local server (MASTER_HOST) → pods collected via local find" {
    PODS_DATA="{}"
    export MASTER_HOST="dev1.fleet.test"
    mkdir -p "$BATS_TEST_TMPDIR/pods/api" "$BATS_TEST_TMPDIR/pods/worker"
    export PODS_DIR="$BATS_TEST_TMPDIR/pods"
    ssh_cmd() { echo "remote-pod"; }
    collect_env "dev"
    result=$(echo "$PODS_DATA" | jq -r '.dev["dev1.fleet.test"] | sort | join(",")')
    [ "$result" = "api,worker" ]
}

# ── collect_env : pods_ignore ─────────────────────────────────────────────────

@test "collect_env: pods_ignore empty → no pod filtered" {
    PODS_DATA="{}"
    MASTER_HOST="notaserver"
    local updated
    updated=$(jq '.pods_ignore = []' "$CONFIG_FILE")
    echo "$updated" > "$CONFIG_FILE"
    ssh_cmd() { echo "api"; echo "worker"; }
    collect_env "dev"
    result=$(echo "$PODS_DATA" | jq -r '.dev["dev1.fleet.test"] | sort | join(",")')
    [ "$result" = "api,worker" ]
}

@test "collect_env: pods_ignore filters pods matching the regex" {
    PODS_DATA="{}"
    MASTER_HOST="notaserver"
    local updated
    updated=$(jq '.pods_ignore = ["^tmp-"]' "$CONFIG_FILE")
    echo "$updated" > "$CONFIG_FILE"
    ssh_cmd() { echo "api"; echo "tmp-debug"; echo "worker"; }
    collect_env "dev"
    result=$(echo "$PODS_DATA" | jq -r '.dev["dev1.fleet.test"] | sort | join(",")')
    [ "$result" = "api,worker" ]
}

@test "collect_env: pods_ignore with multiple regex → all matching pods filtered" {
    PODS_DATA="{}"
    MASTER_HOST="notaserver"
    local updated
    updated=$(jq '.pods_ignore = ["^tmp-", "-test$"]' "$CONFIG_FILE")
    echo "$updated" > "$CONFIG_FILE"
    ssh_cmd() { echo "api"; echo "tmp-debug"; echo "worker-test"; echo "worker"; }
    collect_env "dev"
    result=$(echo "$PODS_DATA" | jq -r '.dev["dev1.fleet.test"] | sort | join(",")')
    [ "$result" = "api,worker" ]
}

@test "collect_env: pods_ignore absent from config → no pod filtered" {
    PODS_DATA="{}"
    MASTER_HOST="notaserver"
    local updated
    updated=$(jq 'del(.pods_ignore)' "$CONFIG_FILE")
    echo "$updated" > "$CONFIG_FILE"
    ssh_cmd() { echo "api"; echo "worker"; }
    collect_env "dev"
    result=$(echo "$PODS_DATA" | jq -r '.dev["dev1.fleet.test"] | sort | join(",")')
    [ "$result" = "api,worker" ]
}

@test "collect_env: SSH failure → server skipped, other server still processed" {
    PODS_DATA='{"dev":{"dev1.fleet.test":["old-pod"],"dev2.fleet.test":["old-pod2"]}}'
    MASTER_HOST="notaserver"
    ssh_cmd() {
        if [[ "$*" == *"dev1"* ]]; then return 1; fi
        echo "new-pod"
    }
    collect_env "dev" || true
    # dev1 failure → existing data preserved
    dev1=$(echo "$PODS_DATA" | jq -r '.dev["dev1.fleet.test"] | join(",")')
    [ "$dev1" = "old-pod" ]
    # dev2 success → data updated
    dev2=$(echo "$PODS_DATA" | jq -r '.dev["dev2.fleet.test"] | join(",")')
    [ "$dev2" = "new-pod" ]
}

# ── check_all_servers_flag ─────────────────────────────────────────────────────

@test "check_all_servers_flag: no pod on all servers → no warning" {
    # api on dev1 only, worker on dev2 only → none is on both servers
    PODS_DATA='{"dev": {"dev1.fleet.test": ["api"], "dev2.fleet.test": ["worker"]}}'
    ENV=""
    run check_all_servers_flag
    [ "$status" -eq 0 ]
    [[ "$output" != *"all_servers"* ]]
}

@test "check_all_servers_flag: pod on all servers not flagged → displays a warning" {
    # api on both dev servers (2/2) → should be flagged
    PODS_DATA='{"dev": {"dev1.fleet.test": ["api"], "dev2.fleet.test": ["api"]}}'
    ENV=""
    run check_all_servers_flag <<< 'n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"api"* ]]
}

@test "check_all_servers_flag: response Y → updates all_servers in config.json" {
    PODS_DATA='{"dev": {"dev1.fleet.test": ["api"], "dev2.fleet.test": ["api"]}}'
    ENV=""
    run check_all_servers_flag <<< 'Y'
    result=$(jq -r '.pods.api.all_servers' "$CONFIG_FILE")
    [ "$result" = "true" ]
}

@test "check_all_servers_flag: response n → config.json left unchanged" {
    PODS_DATA='{"dev": {"dev1.fleet.test": ["api"], "dev2.fleet.test": ["api"]}}'
    ENV=""
    local before
    before=$(cat "$CONFIG_FILE")
    run check_all_servers_flag <<< 'n'
    local after
    after=$(cat "$CONFIG_FILE")
    [ "$before" = "$after" ]
}

@test "check_all_servers_flag: pod already flagged all_servers:true → no warning" {
    PODS_DATA='{"dev": {"dev1.fleet.test": ["api"], "dev2.fleet.test": ["api"]}}'
    ENV=""
    local updated
    updated=$(jq '.pods.api = {"all_servers": true}' "$CONFIG_FILE")
    echo "$updated" > "$CONFIG_FILE"
    run check_all_servers_flag
    [ "$status" -eq 0 ]
    [[ "$output" != *"api"* ]]
}

# ── collect_all_pods ───────────────────────────────────────────────────────────

@test "collect_all_pods: writes PODS_FILE after collection" {
    PODS_DATA="{}"
    ENV=""
    collect_env() { :; }
    check_all_servers_flag() { :; }
    rm -f "$PODS_FILE"
    collect_all_pods
    [ -f "$PODS_FILE" ]
}

@test "collect_all_pods: creates last_sync.txt in DATA_DIR" {
    PODS_DATA="{}"
    ENV=""
    collect_env() { :; }
    check_all_servers_flag() { :; }
    rm -f "$DATA_DIR/last_sync.txt"
    collect_all_pods
    [ -f "$DATA_DIR/last_sync.txt" ]
}

@test "collect_all_pods: last_sync.txt has format YYYY-MM-DD HH:MM" {
    PODS_DATA="{}"
    ENV=""
    collect_env() { :; }
    check_all_servers_flag() { :; }
    collect_all_pods
    content=$(cat "$DATA_DIR/last_sync.txt")
    [[ "$content" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]
}

@test "collect_all_pods: ENV empty → calls collect_env for each env in config" {
    PODS_DATA="{}"
    ENV=""
    collect_env() { echo "CALLED" >> "$BATS_TEST_TMPDIR/env_calls"; }
    check_all_servers_flag() { :; }
    collect_all_pods
    # config.json has 3 envs: dev, test, prod
    count=$(wc -l < "$BATS_TEST_TMPDIR/env_calls")
    [ "$count" -eq 3 ]
}

@test "collect_all_pods: ENV non-empty → calls collect_env only once" {
    PODS_DATA="{}"
    ENV="dev"
    collect_env() { echo "CALLED" >> "$BATS_TEST_TMPDIR/env_calls"; }
    check_all_servers_flag() { :; }
    collect_all_pods
    count=$(wc -l < "$BATS_TEST_TMPDIR/env_calls")
    [ "$count" -eq 1 ]
}

@test "collect_all_pods: stdin non-TTY (bats) → check_all_servers_flag not called" {
    PODS_DATA="{}"
    ENV=""
    collect_env() { :; }
    check_all_servers_flag() { echo "CALLED" > "$BATS_TEST_TMPDIR/flag_called"; }
    collect_all_pods
    [ ! -f "$BATS_TEST_TMPDIR/flag_called" ]
}

# ── collect_services_local ────────────────────────────────────────────────────

@test "collect_services_local: pod without compose file → absent from result" {
    mkdir -p "$BATS_TEST_TMPDIR/pods/no-compose"
    PODS_DIR="$BATS_TEST_TMPDIR/pods"
    local result
    result=$(collect_services_local '["no-compose"]')
    [ "$(printf '%s' "$result" | jq 'has("no-compose")')" = "false" ]
}

@test "collect_services_local: JSON Lines → normalized to array" {
    mkdir -p "$BATS_TEST_TMPDIR/pods/api"
    touch "$BATS_TEST_TMPDIR/pods/api/docker-compose.yml"
    printf '#!/bin/bash\nprintf '"'"'{"Name":"s1"}\n{"Name":"s2"}\n'"'"'\n' \
        > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    PODS_DIR="$BATS_TEST_TMPDIR/pods"
    local result
    result=$(collect_services_local '["api"]')
    [ "$(printf '%s' "$result" | jq '.api | type')" = '"array"' ]
    [ "$(printf '%s' "$result" | jq '.api | length')" = "2" ]
}

@test "collect_services_local: JSON Array → unchanged" {
    mkdir -p "$BATS_TEST_TMPDIR/pods/api"
    touch "$BATS_TEST_TMPDIR/pods/api/docker-compose.yml"
    printf '#!/bin/bash\nprintf '"'"'[{"Name":"s1"},{"Name":"s2"}]\n'"'"'\n' \
        > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    PODS_DIR="$BATS_TEST_TMPDIR/pods"
    local result
    result=$(collect_services_local '["api"]')
    [ "$(printf '%s' "$result" | jq '.api | length')" = "2" ]
}

@test "collect_services_local: docker compose ps on error → [] for that pod" {
    mkdir -p "$BATS_TEST_TMPDIR/pods/api"
    touch "$BATS_TEST_TMPDIR/pods/api/docker-compose.yml"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    PODS_DIR="$BATS_TEST_TMPDIR/pods"
    local result
    result=$(collect_services_local '["api"]')
    [ "$(printf '%s' "$result" | jq '.api')" = "[]" ]
}

@test "collect_services_local: empty pods_json → returns {}" {
    PODS_DIR="$BATS_TEST_TMPDIR/pods"
    local result
    result=$(collect_services_local '[]')
    [ "$(printf '%s' "$result" | jq '.')" = "{}" ]
}

# ── collect_services_env ──────────────────────────────────────────────────────

@test "collect_services_env: local server (MASTER_HOST) → ssh_cmd not called" {
    # Use the 'test' env which has only one server in config.json
    export MASTER_HOST="test1.fleet.test"
    PODS_DATA='{"test":{"test1.fleet.test":[]}}'
    SERVICES_DATA="{}"
    ssh_cmd() { echo "SSH" >> "$BATS_TEST_TMPDIR/ssh_calls"; echo "{}"; }
    collect_services_env "test"
    [ ! -f "$BATS_TEST_TMPDIR/ssh_calls" ]
}

@test "collect_services_env: remote server → ssh_cmd called once per server" {
    MASTER_HOST="notaserver"
    PODS_DATA='{"dev":{"dev1.fleet.test":[],"dev2.fleet.test":[]}}'
    SERVICES_DATA="{}"
    ssh_cmd() { echo "SSH" >> "$BATS_TEST_TMPDIR/ssh_calls"; echo "{}"; }
    collect_services_env "dev"
    count=$(wc -l < "$BATS_TEST_TMPDIR/ssh_calls")
    [ "$count" -eq 2 ]
}

@test "collect_services_env: SERVICES_DATA has correct structure after call" {
    MASTER_HOST="notaserver"
    SERVICES_DATA="{}"
    PODS_DATA='{"dev":{"dev1.fleet.test":["api"]}}'
    ssh_cmd() { echo '{"api":[]}'; }
    collect_services_env "dev"
    result=$(printf '%s' "$SERVICES_DATA" | jq -r '.dev["dev1.fleet.test"] | type')
    [ "$result" = "object" ]
}

@test "collect_services_env: pods absent from PODS_DATA → each server gets pods_json []" {
    MASTER_HOST="notaserver"
    SERVICES_DATA="{}"
    PODS_DATA='{"dev":{}}'
    ssh_cmd() { echo "{}"; }
    collect_services_env "dev"
    # Both dev servers (config.json: dev1, dev2) have been processed
    result=$(printf '%s' "$SERVICES_DATA" | jq '.dev | keys | length')
    [ "$result" -eq 2 ]
}

@test "collect_services_env: SSH failure → server skipped, other server still processed" {
    MASTER_HOST="notaserver"
    SERVICES_DATA='{"dev":{"dev1.fleet.test":{"old-svc":[]},"dev2.fleet.test":{"old-svc2":[]}}}'
    PODS_DATA='{"dev":{"dev1.fleet.test":["api"],"dev2.fleet.test":["api"]}}'
    ssh_cmd() {
        if [[ "$*" == *"dev1"* ]]; then return 1; fi
        echo '{"new-svc":[]}'
    }
    collect_services_env "dev" || true
    # dev1 failure → existing data preserved
    dev1=$(printf '%s' "$SERVICES_DATA" | jq -r '.dev["dev1.fleet.test"] | keys[0]')
    [ "$dev1" = "old-svc" ]
    # dev2 success → data updated
    dev2=$(printf '%s' "$SERVICES_DATA" | jq -r '.dev["dev2.fleet.test"] | keys[0]')
    [ "$dev2" = "new-svc" ]
}

# ── collect_all_services ──────────────────────────────────────────────────────

@test "collect_all_services: writes SERVICES_FILE to DATA_DIR" {
    ENV=""
    collect_services_env() { :; }
    rm -f "$SERVICES_FILE"
    collect_all_services
    [ -f "$SERVICES_FILE" ]
}

@test "collect_all_services: resets SERVICES_DATA to {} at start" {
    ENV=""
    SERVICES_DATA='{"stale":"data"}'
    collect_services_env() { :; }
    collect_all_services
    [ "$(printf '%s' "$SERVICES_DATA" | jq '.')" = "{}" ]
}

@test "collect_all_services: ENV empty → calls collect_services_env for each env" {
    ENV=""
    collect_services_env() { echo "CALLED" >> "$BATS_TEST_TMPDIR/calls"; }
    collect_all_services
    # fixtures/config.json has 3 envs: dev, test, prod
    count=$(wc -l < "$BATS_TEST_TMPDIR/calls")
    [ "$count" -eq 3 ]
}

@test "collect_all_services: ENV non-empty → calls collect_services_env only once" {
    ENV="dev"
    collect_services_env() { echo "CALLED" >> "$BATS_TEST_TMPDIR/calls"; }
    collect_all_services
    count=$(wc -l < "$BATS_TEST_TMPDIR/calls")
    [ "$count" -eq 1 ]
}

@test "collect_all_services: produced JSON is valid" {
    ENV=""
    MASTER_HOST="notaserver"
    PODS_DATA='{"dev":{"dev1.fleet.test":[],"dev2.fleet.test":[]},"test":{"test1.fleet.test":[]},"prod":{"prod1.fleet.test":[],"prod2.fleet.test":[]}}'
    ssh_cmd() { echo "{}"; }
    collect_all_services
    run jq '.' "$SERVICES_FILE"
    [ "$status" -eq 0 ]
}

# ── cmd_sync ───────────────────────────────────────────────────────────────────

@test "cmd_sync: unknown option → exit 1 with error message" {
    run cmd_sync -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "cmd_sync: calls generate_ascii_files and collect_all_pods" {
    check_sshpass()        { :; }
    check_config_file()    { :; }
    ask_password()         { :; }
    ensure_user_aliases()  { :; }
    load_pods_data()       { PODS_DATA="{}"; }
    generate_ascii_files() { echo "GEN" > "$BATS_TEST_TMPDIR/gen_called"; }
    collect_all_pods()     { echo "COL" > "$BATS_TEST_TMPDIR/col_called"; }
    iterate_servers()      { :; }
    print_summary()        { :; }
    cmd_sync
    [ -f "$BATS_TEST_TMPDIR/gen_called" ]
    [ -f "$BATS_TEST_TMPDIR/col_called" ]
}

@test "cmd_sync: displays section headers Phase 1a, 1b and 2" {
    check_sshpass()        { :; }
    check_config_file()    { :; }
    ask_password()         { :; }
    ensure_user_aliases()  { :; }
    load_pods_data()       { PODS_DATA="{}"; }
    generate_ascii_files() { :; }
    collect_all_pods()     { :; }
    iterate_servers()      { :; }
    print_summary()        { :; }
    output=$(cmd_sync 2>&1)
    [[ "$output" == *"Phase 1a"* ]]
    [[ "$output" == *"Phase 1b"* ]]
    [[ "$output" == *"Phase 2"* ]]
}

@test "cmd_sync: clears PASSWORD after execution" {
    check_sshpass()        { :; }
    check_config_file()    { :; }
    ask_password()         { PASSWORD="secret"; }
    ensure_user_aliases()  { :; }
    load_pods_data()       { PODS_DATA="{}"; }
    generate_ascii_files() { :; }
    collect_all_pods()     { :; }
    iterate_servers()      { :; }
    print_summary()        { :; }
    cmd_sync
    [ -z "${PASSWORD+x}" ]
}

@test "cmd_sync: -q → generate_ascii_files and collect_all_pods not called" {
    check_sshpass()        { :; }
    check_config_file()    { :; }
    ask_password()         { :; }
    ensure_user_aliases()  { :; }
    load_pods_data()       { PODS_DATA="{}"; }
    generate_ascii_files() { echo "GEN" > "$BATS_TEST_TMPDIR/gen_called"; }
    collect_all_pods()     { echo "COL" > "$BATS_TEST_TMPDIR/col_called"; }
    iterate_servers()      { :; }
    print_summary()        { :; }
    cmd_sync -q
    [ ! -f "$BATS_TEST_TMPDIR/gen_called" ]
    [ ! -f "$BATS_TEST_TMPDIR/col_called" ]
}

@test "cmd_sync: --quick → generate_ascii_files and collect_all_pods not called" {
    check_sshpass()        { :; }
    check_config_file()    { :; }
    ask_password()         { :; }
    ensure_user_aliases()  { :; }
    load_pods_data()       { PODS_DATA="{}"; }
    generate_ascii_files() { echo "GEN" > "$BATS_TEST_TMPDIR/gen_called"; }
    collect_all_pods()     { echo "COL" > "$BATS_TEST_TMPDIR/col_called"; }
    iterate_servers()      { :; }
    print_summary()        { :; }
    cmd_sync --quick
    [ ! -f "$BATS_TEST_TMPDIR/gen_called" ]
    [ ! -f "$BATS_TEST_TMPDIR/col_called" ]
}

@test "cmd_sync: -f → collect_all_services called" {
    check_sshpass()           { :; }
    check_config_file()       { :; }
    ask_password()            { :; }
    ensure_user_aliases()     { :; }
    load_pods_data()          { PODS_DATA="{}"; }
    generate_ascii_files()    { :; }
    collect_all_pods()        { :; }
    collect_all_services()    { echo "SVC" > "$BATS_TEST_TMPDIR/svc_called"; }
    iterate_servers()         { :; }
    print_summary()           { :; }
    cmd_sync -f
    [ -f "$BATS_TEST_TMPDIR/svc_called" ]
}

@test "cmd_sync: without -f → collect_all_services not called" {
    check_sshpass()           { :; }
    check_config_file()       { :; }
    ask_password()            { :; }
    ensure_user_aliases()     { :; }
    load_pods_data()          { PODS_DATA="{}"; }
    generate_ascii_files()    { :; }
    collect_all_pods()        { :; }
    collect_all_services()    { echo "SVC" > "$BATS_TEST_TMPDIR/svc_called"; }
    iterate_servers()         { :; }
    print_summary()           { :; }
    cmd_sync
    [ ! -f "$BATS_TEST_TMPDIR/svc_called" ]
}

@test "cmd_sync: -f → displays Phase 1a, Phase 1b, Phase 1c and Phase 2" {
    check_sshpass()           { :; }
    check_config_file()       { :; }
    ask_password()            { :; }
    ensure_user_aliases()     { :; }
    load_pods_data()          { PODS_DATA="{}"; }
    generate_ascii_files()    { :; }
    collect_all_pods()        { :; }
    collect_all_services()    { :; }
    iterate_servers()         { :; }
    print_summary()           { :; }
    output=$(cmd_sync -f 2>&1)
    [[ "$output" == *"Phase 1a"* ]]
    [[ "$output" == *"Phase 1b"* ]]
    [[ "$output" == *"Phase 1c"* ]]
    [[ "$output" == *"Phase 2"* ]]
}

@test "cmd_sync: -q → collect_all_services not called even with FULL_MODE" {
    check_sshpass()           { :; }
    check_config_file()       { :; }
    ask_password()            { :; }
    ensure_user_aliases()     { :; }
    load_pods_data()          { PODS_DATA="{}"; }
    generate_ascii_files()    { :; }
    collect_all_pods()        { :; }
    collect_all_services()    { echo "SVC" > "$BATS_TEST_TMPDIR/svc_called"; }
    iterate_servers()         { :; }
    print_summary()           { :; }
    cmd_sync -q
    [ ! -f "$BATS_TEST_TMPDIR/svc_called" ]
}

@test "cmd_sync: -q → displays Phase 2 but not Phase 1a nor Phase 1b" {
    check_sshpass()        { :; }
    check_config_file()    { :; }
    ask_password()         { :; }
    ensure_user_aliases()  { :; }
    load_pods_data()       { PODS_DATA="{}"; }
    generate_ascii_files() { :; }
    collect_all_pods()     { :; }
    iterate_servers()      { :; }
    print_summary()        { :; }
    output=$(cmd_sync -q 2>&1)
    [[ "$output" != *"Phase 1a"* ]]
    [[ "$output" != *"Phase 1b"* ]]
    [[ "$output" == *"Phase 2"* ]]
}

# ── vars: new variables ───────────────────────────────────────────────────────

@test "vars: FQDN_FILE is defined as DATA_DIR/fqdn" {
    [[ "$FQDN_FILE" == "$DATA_DIR/fqdn" ]]
}

@test "vars: GIT_SERVER_FILE is defined as DATA_DIR/git_server" {
    [[ "$GIT_SERVER_FILE" == "$DATA_DIR/git_server" ]]
}

@test "vars: SERVICES_FILE is defined as DATA_DIR/services.json" {
    [[ "$SERVICES_FILE" == "$DATA_DIR/services.json" ]]
}

