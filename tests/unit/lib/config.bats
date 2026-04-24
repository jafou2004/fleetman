#!/usr/bin/env bats
# Unit tests for scripts/lib/config.sh

load '../../test_helper/common'

setup() {
    load_common
}

# ── check_config_file ──────────────────────────────────────────────────────────

@test "check_config_file: file present → does nothing, returns 0" {
    # CONFIG_FILE is already copied by load_common
    run check_config_file
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "check_config_file: file absent → creates default and exit 1" {
    export CONFIG_FILE="$HOME/missing_config.json"
    rm -f "$CONFIG_FILE"
    run check_config_file
    [ "$status" -eq 1 ]
    [ -f "$CONFIG_FILE" ]
    [[ "$output" == *"⚠"* ]]
}

@test "check_config_file: default file created contains required keys" {
    export CONFIG_FILE="$HOME/default_config.json"
    rm -f "$CONFIG_FILE"
    run check_config_file
    [ -f "$CONFIG_FILE" ]
    run jq -e '.servers' "$CONFIG_FILE"
    [ "$status" -eq 0 ]
}

# ── parse_env ──────────────────────────────────────────────────────────────────

@test "parse_env: empty argument → ENV empty" {
    parse_env ""
    [ "$ENV" = "" ]
}

@test "parse_env: valid environment 'dev' → ENV='dev'" {
    parse_env "dev"
    [ "$ENV" = "dev" ]
}

@test "parse_env: valid environment 'prod' → ENV='prod'" {
    parse_env "prod"
    [ "$ENV" = "prod" ]
}

@test "parse_env: invalid environment → exit 1 with error message" {
    run parse_env "invalid_env"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"invalid_env"* ]]
}

# ── env_label ──────────────────────────────────────────────────────────────────

@test "env_label: ENV empty → 'ALL'" {
    ENV=""
    run env_label
    [ "$status" -eq 0 ]
    [ "$output" = "ALL" ]
}

@test "env_label: ENV='dev' → 'DEV'" {
    ENV="dev"
    run env_label
    [ "$status" -eq 0 ]
    [ "$output" = "DEV" ]
}

@test "env_label: ENV='prod' → 'PROD'" {
    ENV="prod"
    run env_label
    [ "$status" -eq 0 ]
    [ "$output" = "PROD" ]
}

@test "env_label: with arg 'dev' → 'DEV' (ignores ENV)" {
    ENV="prod"
    run env_label "dev"
    [ "$output" = "DEV" ]
}

@test "env_label: with empty arg → 'ALL'" {
    ENV="prod"
    run env_label ""
    [ "$output" = "ALL" ]
}

# ── parse_search_env_opts ──────────────────────────────────────────────────────

@test "parse_search_env_opts: -p myapp -e dev → SEARCH and ENV_FILTER correct" {
    parse_search_env_opts -p myapp -e dev || true
    [ "$SEARCH" = "myapp" ]
    [ "$ENV_FILTER" = "dev" ]
}

@test "parse_search_env_opts: returns the number of args to shift" {
    local shift_count
    parse_search_env_opts -p myapp -e dev || shift_count=$?
    # -p myapp -e dev = 4 args → returns 4
    [ "$shift_count" -eq 4 ]
}

@test "parse_search_env_opts: without flags → SEARCH and ENV_FILTER empty" {
    parse_search_env_opts || true
    [ "$SEARCH" = "" ]
    [ "$ENV_FILTER" = "" ]
}

@test "parse_search_env_opts: -p only → ENV_FILTER empty" {
    parse_search_env_opts -p myapp || true
    [ "$SEARCH" = "myapp" ]
    [ "$ENV_FILTER" = "" ]
}

# ── collect_server_pods ────────────────────────────────────────────────────────

@test "collect_server_pods: SEARCH='api' no filter → 4 servers (dev1, dev2, test1, prod1)" {
    SEARCH="api" ENV_FILTER=""
    collect_server_pods
    [ "${#server_order[@]}" -eq 4 ]
    [[ " ${server_order[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${server_order[*]} " == *"dev2.fleet.test"* ]]
    [[ " ${server_order[*]} " == *"test1.fleet.test"* ]]
    [[ " ${server_order[*]} " == *"prod1.fleet.test"* ]]
    [[ " ${server_order[*]} " != *"prod2.fleet.test"* ]]
}

@test "collect_server_pods: SEARCH='api' → server_pods[dev1.fleet.test]='api'" {
    SEARCH="api" ENV_FILTER=""
    collect_server_pods
    [ "${server_pods["dev1.fleet.test"]}" = "api" ]
}

@test "collect_server_pods: SEARCH='worker' no filter → 3 servers (dev1, test1, prod2)" {
    SEARCH="worker" ENV_FILTER=""
    collect_server_pods
    [ "${#server_order[@]}" -eq 3 ]
    [[ " ${server_order[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${server_order[*]} " == *"test1.fleet.test"* ]]
    [[ " ${server_order[*]} " == *"prod2.fleet.test"* ]]
    [[ " ${server_order[*]} " != *"dev2.fleet.test"* ]]
}

@test "collect_server_pods: SEARCH='api' ENV_FILTER='dev' → 2 servers (dev1, dev2)" {
    SEARCH="api" ENV_FILTER="dev"
    collect_server_pods
    [ "${#server_order[@]}" -eq 2 ]
    [[ " ${server_order[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${server_order[*]} " == *"dev2.fleet.test"* ]]
    [[ " ${server_order[*]} " != *"test1.fleet.test"* ]]
}

@test "collect_server_pods: no filter → 5 servers, dev1 has 2 pods" {
    SEARCH="" ENV_FILTER=""
    collect_server_pods
    [ "${#server_order[@]}" -eq 5 ]
    [ "${server_pods["dev1.fleet.test"]}" = "api worker" ]
}

@test "collect_server_pods: SEARCH='nonexistent' → server_order empty" {
    SEARCH="nonexistent" ENV_FILTER=""
    collect_server_pods
    [ "${#server_order[@]}" -eq 0 ]
}

@test "collect_server_pods: SEARCH='api' ENV_FILTER='prod' → prod1 only" {
    SEARCH="api" ENV_FILTER="prod"
    collect_server_pods
    [ "${#server_order[@]}" -eq 1 ]
    [ "${server_order[0]}" = "prod1.fleet.test" ]
    [ "${server_pods["prod1.fleet.test"]}" = "api" ]
}

@test "collect_server_pods: direct call (coverage) → no error" {
    SEARCH="api" ENV_FILTER=""
    collect_server_pods > "$BATS_TEST_TMPDIR/out.txt"
    [ "${#server_order[@]}" -gt 0 ]
}

# ── find_and_select_pod ────────────────────────────────────────────────────────

@test "find_and_select_pod: search='api' without filter → SELECTED_POD='api'" {
    select_menu() { SELECTED_IDX=0; }
    find_and_select_pod "api" "" "title"
    [ "$SELECTED_POD" = "api" ]
}

@test "find_and_select_pod: search='worker' without filter → SELECTED_POD='worker'" {
    select_menu() { SELECTED_IDX=0; }
    find_and_select_pod "worker" "" "title"
    [ "$SELECTED_POD" = "worker" ]
}

@test "find_and_select_pod: search='api' env_filter='dev' → SELECTED_POD='api'" {
    select_menu() { SELECTED_IDX=0; }
    find_and_select_pod "api" "dev" "title"
    [ "$SELECTED_POD" = "api" ]
}

@test "find_and_select_pod: without env filter → label='ALL'" {
    select_menu() { SELECTED_IDX=0; }
    find_and_select_pod "api" "" "title"
    [ "$label" = "ALL" ]
}

@test "find_and_select_pod: env_filter='dev' → label='DEV'" {
    select_menu() { SELECTED_IDX=0; }
    find_and_select_pod "api" "dev" "title"
    [ "$label" = "DEV" ]
}

@test "find_and_select_pod: search='nonexistent' → exit 1 + 'No pod matching'" {
    run find_and_select_pod "nonexistent" "" "title"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pod matching"* ]]
}

@test "find_and_select_pod: invalid env_filter → exit 1 + 'invalid environment'" {
    run find_and_select_pod "api" "nosuchenv" "title"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
}

@test "find_and_select_pod: pods.json absent → exit 1" {
    rm -f "$PODS_FILE"
    run find_and_select_pod "api" "" "title"
    [ "$status" -eq 1 ]
}

@test "find_and_select_pod: multiple matching names → select_menu called, SELECTED_POD per SELECTED_IDX" {
    # temporary pods.json with two pods matching 'api'
    cat > "$BATS_TEST_TMPDIR/multi.json" << 'EOF'
{ "dev": { "dev1.fleet.test": ["api-v1", "api-v2"] } }
EOF
    export PODS_FILE="$BATS_TEST_TMPDIR/multi.json"
    select_menu() { SELECTED_IDX=1; }
    find_and_select_pod "api" "" "title"
    [ "$SELECTED_POD" = "api-v2" ]
}

@test "find_and_select_pod: single match → select_menu not called" {
    local menu_called=0
    select_menu() { menu_called=1; SELECTED_IDX=0; }
    find_and_select_pod "api" "" "title"
    [ "$menu_called" -eq 0 ]
}

# ── collect_pod_servers ────────────────────────────────────────────────────────

@test "collect_pod_servers: SELECTED_POD='api' ENV='' → 4 servers (dev1, dev2, test1, prod1)" {
    SELECTED_POD="api" ENV=""
    collect_pod_servers
    [ "${#pod_servers[@]}" -eq 4 ]
    [[ " ${pod_servers[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${pod_servers[*]} " == *"dev2.fleet.test"* ]]
    [[ " ${pod_servers[*]} " == *"test1.fleet.test"* ]]
    [[ " ${pod_servers[*]} " == *"prod1.fleet.test"* ]]
    [[ " ${pod_servers[*]} " != *"prod2.fleet.test"* ]]
}

@test "collect_pod_servers: SELECTED_POD='worker' ENV='' → 3 servers (dev1, test1, prod2)" {
    SELECTED_POD="worker" ENV=""
    collect_pod_servers
    [ "${#pod_servers[@]}" -eq 3 ]
    [[ " ${pod_servers[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${pod_servers[*]} " == *"test1.fleet.test"* ]]
    [[ " ${pod_servers[*]} " == *"prod2.fleet.test"* ]]
    [[ " ${pod_servers[*]} " != *"dev2.fleet.test"* ]]
}

@test "collect_pod_servers: SELECTED_POD='api' ENV='dev' → 2 servers (dev1, dev2)" {
    SELECTED_POD="api" ENV="dev"
    collect_pod_servers
    [ "${#pod_servers[@]}" -eq 2 ]
    [[ " ${pod_servers[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${pod_servers[*]} " == *"dev2.fleet.test"* ]]
    [[ " ${pod_servers[*]} " != *"test1.fleet.test"* ]]
}

@test "collect_pod_servers: SELECTED_POD='api' ENV='prod' → prod1 only" {
    SELECTED_POD="api" ENV="prod"
    collect_pod_servers
    [ "${#pod_servers[@]}" -eq 1 ]
    [ "${pod_servers[0]}" = "prod1.fleet.test" ]
}

@test "collect_pod_servers: SELECTED_POD='nonexistent' → pod_servers empty" {
    SELECTED_POD="nonexistent" ENV=""
    collect_pod_servers
    [ "${#pod_servers[@]}" -eq 0 ]
}

@test "collect_pod_servers: _all is always 'false'" {
    SELECTED_POD="api" ENV=""
    collect_pod_servers
    [ "$_all" = "false" ]
}

# ── parse_server_filter_opts ───────────────────────────────────────────────────

@test "parse_server_filter_opts: -s srv -e dev → SERVER_FILTER='srv' ENV_FILTER='dev'" {
    parse_server_filter_opts -s srv -e dev || true
    [ "$SERVER_FILTER" = "srv" ]
    [ "$ENV_FILTER" = "dev" ]
}

@test "parse_server_filter_opts: no flags → SERVER_FILTER and ENV_FILTER empty" {
    parse_server_filter_opts || true
    [ "$SERVER_FILTER" = "" ]
    [ "$ENV_FILTER" = "" ]
}

@test "parse_server_filter_opts: -e only → SERVER_FILTER empty, ENV_FILTER set" {
    parse_server_filter_opts -e prod || true
    [ "$SERVER_FILTER" = "" ]
    [ "$ENV_FILTER" = "prod" ]
}

@test "parse_server_filter_opts: -s only → ENV_FILTER empty, SERVER_FILTER set" {
    parse_server_filter_opts -s prod || true
    [ "$ENV_FILTER" = "" ]
    [ "$SERVER_FILTER" = "prod" ]
}

@test "parse_server_filter_opts: returns the number of parsed args to shift" {
    local shift_count
    parse_server_filter_opts -s srv -e dev || shift_count=$?
    [ "$shift_count" -eq 4 ]
}

@test "parse_server_filter_opts: -e without argument → exit 1 + 'requires an argument'" {
    run parse_server_filter_opts -e
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "parse_server_filter_opts: unknown flag → exit 1 + 'Unknown option'" {
    run parse_server_filter_opts -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── collect_servers ────────────────────────────────────────────────────────────

@test "collect_servers: no filter → 5 servers from all envs" {
    SERVER_FILTER="" ENV_FILTER=""
    collect_servers
    [ "${#server_list[@]}" -eq 5 ]
    [[ " ${server_list[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${server_list[*]} " == *"dev2.fleet.test"* ]]
    [[ " ${server_list[*]} " == *"test1.fleet.test"* ]]
    [[ " ${server_list[*]} " == *"prod1.fleet.test"* ]]
    [[ " ${server_list[*]} " == *"prod2.fleet.test"* ]]
}

@test "collect_servers: ENV_FILTER='dev' → 2 servers" {
    SERVER_FILTER="" ENV_FILTER="dev"
    collect_servers
    [ "${#server_list[@]}" -eq 2 ]
    [[ " ${server_list[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${server_list[*]} " == *"dev2.fleet.test"* ]]
    [[ " ${server_list[*]} " != *"test1.fleet.test"* ]]
}

@test "collect_servers: SERVER_FILTER='prod' → 2 servers (prod1, prod2)" {
    SERVER_FILTER="prod" ENV_FILTER=""
    collect_servers
    [ "${#server_list[@]}" -eq 2 ]
    [[ " ${server_list[*]} " == *"prod1.fleet.test"* ]]
    [[ " ${server_list[*]} " == *"prod2.fleet.test"* ]]
    [[ " ${server_list[*]} " != *"dev1.fleet.test"* ]]
}

@test "collect_servers: SERVER_FILTER='1' → 3 servers (dev1, test1, prod1)" {
    SERVER_FILTER="1" ENV_FILTER=""
    collect_servers
    [ "${#server_list[@]}" -eq 3 ]
    [[ " ${server_list[*]} " == *"dev1.fleet.test"* ]]
    [[ " ${server_list[*]} " == *"test1.fleet.test"* ]]
    [[ " ${server_list[*]} " == *"prod1.fleet.test"* ]]
    [[ " ${server_list[*]} " != *"dev2.fleet.test"* ]]
}

@test "collect_servers: ENV_FILTER='prod' SERVER_FILTER='prod1' → 1 server" {
    SERVER_FILTER="prod1" ENV_FILTER="prod"
    collect_servers
    [ "${#server_list[@]}" -eq 1 ]
    [ "${server_list[0]}" = "prod1.fleet.test" ]
}

@test "collect_servers: server_envs maps fqdn to env" {
    SERVER_FILTER="" ENV_FILTER="dev"
    collect_servers
    [ "${server_envs["dev1.fleet.test"]}" = "dev" ]
    [ "${server_envs["dev2.fleet.test"]}" = "dev" ]
}

@test "collect_servers: invalid ENV_FILTER → exit 1 + 'invalid environment'" {
    SERVER_FILTER="" ENV_FILTER="nosuchenv"
    run collect_servers
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid environment"* ]]
    [[ "$output" == *"nosuchenv"* ]]
}

@test "collect_servers: SERVER_FILTER='nonexistent' → server_list empty" {
    SERVER_FILTER="nonexistent" ENV_FILTER=""
    collect_servers
    [ "${#server_list[@]}" -eq 0 ]
}

# ── get_git_server ─────────────────────────────────────────────────────────────

@test "get_git_server: file present → returns FQDN" {
    mkdir -p "$HOME/.data"
    echo "git1.fleet.test" > "$HOME/.data/git_server"
    export GIT_SERVER_FILE="$HOME/.data/git_server"
    run get_git_server
    [ "$status" -eq 0 ]
    [ "$output" = "git1.fleet.test" ]
}

@test "get_git_server: file absent → returns empty" {
    export GIT_SERVER_FILE="$HOME/.data/git_server_absent"
    run get_git_server
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
