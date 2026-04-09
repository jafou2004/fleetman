#!/usr/bin/env bats
# Unit tests for scripts/lib/iterate.sh

load '../../test_helper/common'

setup() {
    load_common
    # Neutralize the spinner to avoid background processes in tests
    _spin_start() { :; }
    _spin_stop()  { :; }
    # Reset counters
    success_count=0
    warn_count=0
    failure_count=0
}

# ── _IS_list_servers ───────────────────────────────────────────────────────────

@test "_IS_list_servers: array provided → iterates hostnames from the array" {
    local -a my_servers=("host1.test" "host2.test")
    run _IS_list_servers "my_servers"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "host1.test" ]
    [ "${lines[1]}" = "host2.test" ]
}

@test "_IS_list_servers: ENV='dev' → returns dev servers from config" {
    ENV="dev"
    run _IS_list_servers ""
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == *"dev"* ]]
}

@test "_IS_list_servers: ENV='' → returns all servers (5 total)" {
    ENV=""
    run _IS_list_servers ""
    [ "$status" -eq 0 ]
    # fixtures: dev(2) + test(1) + prod(2) = 5
    [ "${#lines[@]}" -eq 5 ]
}

@test "_IS_list_servers: ENV='test' → returns 1 server" {
    ENV="test"
    run _IS_list_servers ""
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "test1.fleet.test" ]
}

# ── _IS_parse_result ───────────────────────────────────────────────────────────

@test "_IS_parse_result: output with ✓ → status=ok, success_count++" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "  ✓ All good" > "$tmpfile"
    success_count=0

    local _status _detail
    _IS_parse_result "$tmpfile" 0
    rm -f "$tmpfile"

    [ "$_status" = "ok" ]
    [ "$success_count" -eq 1 ]
    [ "$failure_count" -eq 0 ]
}

@test "_IS_parse_result: output with ✗ → status=err, failure_count++" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "  ✗ Connection failed" > "$tmpfile"
    failure_count=0

    local _status _detail
    _IS_parse_result "$tmpfile" 0
    rm -f "$tmpfile"

    [ "$_status" = "err" ]
    [ "$failure_count" -eq 1 ]
    [ "$success_count" -eq 0 ]
}

@test "_IS_parse_result: output with ⚠ → status=warn, success_count++ and warn_count++" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "  ⚠ Already done" > "$tmpfile"
    success_count=0
    warn_count=0

    local _status _detail
    _IS_parse_result "$tmpfile" 0
    rm -f "$tmpfile"

    [ "$_status" = "warn" ]
    [ "$success_count" -eq 1 ]
    [ "$warn_count" -eq 1 ]
    [ "$failure_count" -eq 0 ]
}

@test "_IS_parse_result: non-zero exit code → status=err" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "some output" > "$tmpfile"
    failure_count=0

    local _status _detail
    _IS_parse_result "$tmpfile" 1
    rm -f "$tmpfile"

    [ "$_status" = "err" ]
    [ "$failure_count" -eq 1 ]
}

@test "_IS_parse_result: extracts detail from ✗ message" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "  ✗ Docker pull failed" > "$tmpfile"

    local _status _detail
    _IS_parse_result "$tmpfile" 0
    rm -f "$tmpfile"

    [ "$_detail" = "Docker pull failed" ]
}

@test "_IS_parse_result: ignores __APPEND lines in detail" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '__APPEND my_arr value1\n  ✓ All good\n' > "$tmpfile"
    success_count=0

    local _status _detail
    _IS_parse_result "$tmpfile" 0
    rm -f "$tmpfile"

    [ "$_status" = "ok" ]
    [ "$success_count" -eq 1 ]
}

# ── iterate_servers (sequential mode) ────────────────────────────────────────

@test "iterate_servers: calls local_fn for MASTER_HOST" {
    _is_local_called=0
    _is_remote_called=0
    _test_local_fn_master()  { _is_local_called=1; ok "local done"; }
    _test_remote_fn_master() { _is_remote_called=1; ok "remote done"; }

    # Force MASTER_HOST to match dev1
    MASTER_HOST="dev1.fleet.test"
    ENV="dev"

    iterate_servers _test_local_fn_master _test_remote_fn_master

    [ "$_is_local_called" -eq 1 ]
}

@test "iterate_servers: calls remote_fn for remote servers" {
    local remote_calls=0
    _test_local_fn2() { ok "local"; }
    _test_remote_fn2() { remote_calls=$(( remote_calls + 1 )); ok "remote $1"; }

    MASTER_HOST="__not_a_real_host__"
    ENV="test"  # 1 serveur: test1.fleet.test

    iterate_servers _test_local_fn2 _test_remote_fn2

    [ "$remote_calls" -eq 1 ]
}

@test "iterate_servers: updates success_count and failure_count" {
    _ok_fn()  { ok "done"; }
    _err_fn() { err "fail"; }

    MASTER_HOST="__not_a_real_host__"
    ENV="test"  # 1 serveur

    iterate_servers _ok_fn _ok_fn
    [ "$success_count" -eq 1 ]
    [ "$failure_count" -eq 0 ]
}

# ── append_result ──────────────────────────────────────────────────────────────

@test "append_result: adds the value to the array" {
    local -a my_arr=()
    append_result my_arr "newval" > /dev/null
    [ "${my_arr[0]}" = "newval" ]
}

@test "append_result: emits __APPEND on stdout" {
    local -a my_arr=()
    run append_result my_arr "newval"
    [ "$status" -eq 0 ]
    [[ "$output" == *"__APPEND my_arr newval"* ]]
}

# ── iterate_pod_servers ────────────────────────────────────────────────────────

@test "iterate_pod_servers: _all=true → calls iterate_servers without pod_servers" {
    local local_calls=0 remote_calls=0
    _ipod_local()  { local_calls=$(( local_calls + 1 )); ok "local"; }
    _ipod_remote() { remote_calls=$(( remote_calls + 1 )); ok "remote"; }

    _all="true"
    MASTER_HOST="__not_a_real_host__"
    ENV="test"  # 1 serveur

    iterate_pod_servers _ipod_local _ipod_remote
    # With _all=true, iterates over full ENV
    [ $(( local_calls + remote_calls )) -eq 1 ]
}

@test "iterate_pod_servers: _all=false → calls iterate_servers with pod_servers" {
    local remote_calls=0
    _ipod2_local()  { ok "local"; }
    _ipod2_remote() { remote_calls=$(( remote_calls + 1 )); ok "remote $1"; }

    _all="false"
    declare -ga pod_servers=("test1.fleet.test")
    MASTER_HOST="__not_a_real_host__"
    ENV=""

    iterate_pod_servers _ipod2_local _ipod2_remote
    [ "$remote_calls" -eq 1 ]
}

# ── _IS_sigint_handler ─────────────────────────────────────────────────────────

@test "_IS_sigint_handler: sets _IS_stop_requested=1" {
    _IS_stop_requested=0
    _IS_active=()
    _IS_sigint_handler
    [ "$_IS_stop_requested" -eq 1 ]
}

@test "_IS_sigint_handler: removes tmpfiles for active jobs and clears _IS_active" {
    local f="$BATS_TEST_TMPDIR/fake_job_sig"
    touch "$f" "${f}.exit" "${f}.done"
    # Real process: kill returns 0. A non-existent PID returns 1 → set -e fails.
    sleep 100 &
    local fake_pid=$!
    _IS_pid_tmpfile[$fake_pid]="$f"
    _IS_active=($fake_pid)
    _SPIN_PID=""

    _IS_sigint_handler

    [ ! -f "$f" ]
    [ ! -f "${f}.exit" ]
    [ ! -f "${f}.done" ]
    [ "${#_IS_active[@]}" -eq 0 ]
}

@test "_IS_sigint_handler: kills the spinner process (_SPIN_PID)" {
    sleep 100 &
    local spin_pid=$!
    _SPIN_PID=$spin_pid
    _IS_active=()
    # wait on a killed process returns 143 (128+SIGTERM) → set -e fails.
    # Mask the builtin with a function that returns 0.
    wait() { return 0; }

    _IS_sigint_handler

    unset -f wait
    ! kill -0 "$spin_pid" 2>/dev/null
    _SPIN_PID=""
}

# ── _IS_draw_progress ──────────────────────────────────────────────────────────

@test "_IS_draw_progress: output contains [done/total]" {
    _IS_done=3
    _IS_total=7
    _IS_active=()
    run _IS_draw_progress
    [[ "$output" == *"[3/7]"* ]]
}

@test "_IS_draw_progress: output contains the active server name" {
    _IS_done=0
    _IS_total=2
    _IS_pid_short[77771]="targetserver"
    _IS_active=(77771)

    run _IS_draw_progress

    [[ "$output" == *"targetserver"* ]]
    unset "_IS_pid_short[77771]"
    _IS_active=()
}

# ── _IS_collect_result ─────────────────────────────────────────────────────────

@test "_IS_collect_result: increments _IS_done and success_count" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "  ✓ Deployed" > "$tmpfile"
    echo 0 > "${tmpfile}.exit"
    touch "${tmpfile}.done"
    _IS_pid_short[55551]="srv1"
    _IS_pid_tmpfile[55551]="$tmpfile"
    _IS_active=(55551)
    _IS_done=0
    success_count=0

    _IS_collect_result 55551 > /dev/null

    [ "$_IS_done" -eq 1 ]
    [ "$success_count" -eq 1 ]
}

@test "_IS_collect_result: removes tmpfile after processing" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "  ✓ Done" > "$tmpfile"
    echo 0 > "${tmpfile}.exit"
    touch "${tmpfile}.done"
    _IS_pid_short[55552]="srv2"
    _IS_pid_tmpfile[55552]="$tmpfile"
    _IS_active=(55552)
    _IS_done=0

    _IS_collect_result 55552 > /dev/null

    [ ! -f "$tmpfile" ]
    [ ! -f "${tmpfile}.exit" ]
    [ ! -f "${tmpfile}.done" ]
}

@test "_IS_collect_result: applique __APPEND protocol" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '__APPEND _cr_collected srv-appended\n  ✓ Done\n' > "$tmpfile"
    echo 0 > "${tmpfile}.exit"
    touch "${tmpfile}.done"
    _IS_pid_short[55553]="srv3"
    _IS_pid_tmpfile[55553]="$tmpfile"
    _IS_active=(55553)
    _IS_done=0
    declare -ga _cr_collected=()

    _IS_collect_result 55553 > /dev/null

    [ "${_cr_collected[0]}" = "srv-appended" ]
}

@test "_IS_collect_result: displays ✓ result line with detail" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "  ✓ Deployed OK" > "$tmpfile"
    echo 0 > "${tmpfile}.exit"
    touch "${tmpfile}.done"
    _IS_pid_short[55554]="frontserver"
    _IS_pid_tmpfile[55554]="$tmpfile"
    _IS_active=(55554)
    _IS_done=0

    run _IS_collect_result 55554

    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"frontserver"* ]]
    [[ "$output" == *"Deployed OK"* ]]
}

# ── iterate_servers (parallel mode) ──────────────────────────────────────────

_make_parallel_cfg() {
    local cfg="$BATS_TEST_TMPDIR/cfg_parallel.json"
    printf '{"parallel":2,"pods_dir":"/pods","env_colors":{},"status_checks":{},"pods":{},"servers":{"dev":["dev1.fleet.test","dev2.fleet.test"]}}' > "$cfg"
    echo "$cfg"
}

@test "iterate_servers: parallel mode → executes functions on all servers" {
    export CONFIG_FILE
    CONFIG_FILE=$(_make_parallel_cfg)
    MASTER_HOST="__not_a_real_host__"
    ENV="dev"

    local flag1="$BATS_TEST_TMPDIR/pflag_dev1"
    local flag2="$BATS_TEST_TMPDIR/pflag_dev2"
    _pll_remote() {
        case "$1" in
            dev1*) touch "$flag1"; ok "dev1 done" ;;
            dev2*) touch "$flag2"; ok "dev2 done" ;;
        esac
    }
    _pll_local() { ok "local"; }

    iterate_servers _pll_local _pll_remote

    [ -f "$flag1" ]
    [ -f "$flag2" ]
}

@test "iterate_servers: parallel mode → updates success_count" {
    export CONFIG_FILE
    CONFIG_FILE=$(_make_parallel_cfg)
    MASTER_HOST="__not_a_real_host__"
    ENV="dev"
    success_count=0

    _pll2_local()  { ok "local"; }
    _pll2_remote() { ok "remote $1"; }

    iterate_servers _pll2_local _pll2_remote

    [ "$success_count" -eq 2 ]
}

@test "iterate_servers: parallel mode → applies __APPEND protocol" {
    export CONFIG_FILE
    CONFIG_FILE=$(_make_parallel_cfg)
    MASTER_HOST="__not_a_real_host__"
    ENV="dev"
    declare -ga _pll_collected=()

    _pll3_local()  { echo "__APPEND _pll_collected local_host"; ok "done"; }
    _pll3_remote() { echo "__APPEND _pll_collected $1"; ok "done"; }

    iterate_servers _pll3_local _pll3_remote

    [ "${#_pll_collected[@]}" -eq 2 ]
}
