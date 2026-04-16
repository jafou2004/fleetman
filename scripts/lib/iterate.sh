#!/bin/bash

# Server iteration engine — sequential and parallel modes.
[[ -n "${_FLEETMAN_ITERATE_LOADED:-}" ]] && return 0
_FLEETMAN_ITERATE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"
source "$(dirname "${BASH_SOURCE[0]}")/display.sh"
source "$(dirname "${BASH_SOURCE[0]}")/spinner.sh"

declare -A _IS_pid_short _IS_pid_tmpfile
declare -a _IS_active
_IS_spin_i=0
_IS_done=0
_IS_total=0
_IS_SF=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
_IS_stop_requested=0

# Signal handler: kills spinner + all active background jobs, cleans up tmpfiles.
# Sets _IS_stop_requested so loops can break cleanly. Triggered by Ctrl+C.
_IS_sigint_handler() {
    _IS_stop_requested=1
    printf "\r\033[K"
    # Kill spinner if active (sequential mode)
    [ -n "${_SPIN_PID:-}" ] && { kill "$_SPIN_PID" 2>/dev/null; wait "$_SPIN_PID" 2>/dev/null; }
    # Kill and clean up all background jobs (parallel mode)
    local _p _t
    for _p in "${_IS_active[@]}"; do
        kill "$_p" 2>/dev/null
        _t="${_IS_pid_tmpfile[$_p]:-}"
        [ -n "$_t" ] && rm -f "$_t" "${_t}.exit" "${_t}.done"
    done
    _IS_active=()
}

# Redraws the single progress line in-place (no newline).
_IS_draw_progress() {
    local _names="" _p
    for _p in "${_IS_active[@]}"; do _names+="  ${_IS_pid_short[$_p]}"; done
    printf "\r\033[K  %s  [%d/%d]%s" "${_IS_SF[$_IS_spin_i]}" "$_IS_done" "$_IS_total" "$_names"
    _IS_spin_i=$(( (_IS_spin_i + 1) % 10 ))
}

# Parses function output to determine status and detail.
# Reads output from $1 (tmpfile path), exit code from $2.
# Sets caller-scope variables: _status, _detail.
# Increments caller-scope counters: success_count, warn_count, failure_count.
_IS_parse_result() {
    local _tmpfile=$1 _exit_code=$2
    local _output _has_err _has_warn
    _output=$(grep -v '^__APPEND ' "$_tmpfile" 2>/dev/null || true)
    _has_err=0; printf '%s' "$_output" | grep -q '✗' && _has_err=1
    _has_warn=0; printf '%s' "$_output" | grep -q '⚠' && _has_warn=1

    if [ "$_exit_code" -ne 0 ] || [ "$_has_err" -eq 1 ]; then
        _detail=$(printf '%s' "$_output" | grep '✗' | tail -1 | \
            sed 's/\x1b\[[0-9;]*m//g; s/^[[:space:]]*✗[[:space:]]*//')
        [ -z "$_detail" ] && _detail="failed"
        _status="err"; failure_count=$(( failure_count + 1 ))
    elif [ "$_has_warn" -eq 1 ]; then
        _detail=$(printf '%s' "$_output" | grep '⚠' | tail -1 | \
            sed 's/\x1b\[[0-9;]*m//g; s/^[[:space:]]*⚠[[:space:]]*//')
        [ -z "$_detail" ] && _detail="skipped"
        _status="warn"; success_count=$(( success_count + 1 )); warn_count=$(( warn_count + 1 ))
    else
        _detail=$(printf '%s' "$_output" | grep '✓' | tail -1 | \
            sed 's/\x1b\[[0-9;]*m//g; s/^[[:space:]]*✓[[:space:]]*//')
        [ -z "$_detail" ] && _detail="ok"
        _status="ok"; success_count=$(( success_count + 1 ))
    fi
}

# Processes a completed background job: applies __APPEND mutations,
# parses result via _IS_parse_result, prints result line, redraws progress.
_IS_collect_result() {
    local _pid=$1 _short _tmpfile _exit_code _line
    _short="${_IS_pid_short[$_pid]}"
    _tmpfile="${_IS_pid_tmpfile[$_pid]}"
    _exit_code=0
    [ -f "${_tmpfile}.exit" ] && _exit_code=$(cat "${_tmpfile}.exit")

    # Apply __APPEND protocol: restore variable mutations across subshell boundary
    while IFS= read -r _line; do
        [[ "$_line" =~ ^__APPEND[[:space:]]+([^[:space:]]+)[[:space:]]+(.*) ]] || continue
        eval "${BASH_REMATCH[1]}+=(\"\${BASH_REMATCH[2]}\")"
    done < "$_tmpfile"

    local _status _detail
    _IS_parse_result "$_tmpfile" "$_exit_code"

    _IS_done=$(( _IS_done + 1 ))
    rm -f "$_tmpfile" "${_tmpfile}.exit" "${_tmpfile}.done"
    unset "_IS_pid_short[$_pid]" "_IS_pid_tmpfile[$_pid]"

    local -a _new=()
    local _p
    for _p in "${_IS_active[@]}"; do [ "$_p" != "$_pid" ] && _new+=("$_p"); done
    _IS_active=("${_new[@]}")

    printf "\r\033[K"
    case "$_status" in
        ok)   echo -e "  ${GREEN}✓${NC}  $(printf '%-22s' "$_short")  $_detail" ;;
        warn) echo -e "  ${YELLOW}⚠${NC}  $(printf '%-22s' "$_short")  $_detail" ;;
        err)  echo -e "  ${RED}✗${NC}  $(printf '%-22s' "$_short")  $_detail" ;;
    esac
    _IS_draw_progress
}

# Outputs the server list: uses array variable <var_name> if provided,
# otherwise falls back to config.json filtered by $ENV.
_IS_list_servers() {
    local _var="$1"
    if [ -n "$_var" ]; then
        local -n _arr="$_var"
        if [ "${#_arr[@]}" -gt 0 ]; then printf '%s\n' "${_arr[@]}"; fi
    elif [ -n "$ENV" ]; then
        jq -r --arg env "$ENV" '.servers[$env] | .[]' "$CONFIG_FILE"
    else
        jq -r '.servers[] | .[]' "$CONFIG_FILE"
    fi
}

# Iterates over servers from CONFIG_FILE (config.json) or an explicit list.
# Calls $1 (no args) for the local server (MASTER_HOST),
# and $2 "$server" for each remote server.
# Optional $3: name of a bash array variable with a custom server list.
# Optional $4: set to 1 to process the local server last (after all remotes).
#              Prevents race conditions where local uninstall deletes credentials
#              needed for remote SSH (e.g. fleet_key) before remotes complete.
# Sequential mode (parallel=1): animated spinner per server, result line on completion.
# Parallel mode (parallel=N>1): global progress line, results print as jobs complete.
# Updates globals: success_count, warn_count, failure_count.
iterate_servers() {
    local local_fn=$1 remote_fn=$2 _servers_var=${3:-""} _local_last=${4:-0}
    success_count=0; warn_count=0; failure_count=0

    local max_jobs
    max_jobs=$(jq -r '.parallel // 1' "$CONFIG_FILE" 2>/dev/null)
    [[ "$max_jobs" =~ ^[0-9]+$ ]] && [ "$max_jobs" -gt 0 ] || max_jobs=1

    # ── Sequential mode ────────────────────────────────────────────────────────
    if [ "$max_jobs" -le 1 ]; then
        local tmpfile _deferred_server=""
        tmpfile=$(mktemp)
        _IS_stop_requested=0
        trap '_IS_sigint_handler' INT

        while IFS= read -r server <&3; do
            [ "$_IS_stop_requested" = 1 ] && break

            # Defer local server to end when local_last=1
            if [ "$_local_last" = "1" ] && \
               { [ "$server" = "$MASTER_HOST" ] || [ "$(short_name "$server")" = "$(short_name "$MASTER_HOST")" ]; }; then
                _deferred_server="$server"
                continue
            fi

            local short
            short=$(short_name "$server")
            _spin_start "$short"

            if [ "$server" = "$MASTER_HOST" ] || [ "$(short_name "$server")" = "$(short_name "$MASTER_HOST")" ]; then
                $local_fn > "$tmpfile" 2>/dev/null
            else
                $remote_fn "$server" > "$tmpfile" 2>/dev/null
            fi
            local fn_exit=$?

            [ "$_IS_stop_requested" = 1 ] && { _spin_stop "$short" "warn" "interrupted"; break; }

            local _status _detail
            _IS_parse_result "$tmpfile" "$fn_exit"

            _spin_stop "$short" "$_status" "$_detail"

        done 3< <(_IS_list_servers "$_servers_var")

        # Process deferred local server last (after all remotes)
        if [ -n "$_deferred_server" ] && [ "$_IS_stop_requested" != "1" ]; then
            local short
            short=$(short_name "$_deferred_server")
            _spin_start "$short"
            $local_fn > "$tmpfile" 2>/dev/null
            local fn_exit=$?
            if [ "$_IS_stop_requested" = 1 ]; then
                _spin_stop "$short" "warn" "interrupted"
            else
                local _status _detail
                _IS_parse_result "$tmpfile" "$fn_exit"
                _spin_stop "$short" "$_status" "$_detail"
            fi
        fi

        rm -f "$tmpfile"
        trap - INT
        if [ "$_IS_stop_requested" = 1 ]; then
            warn "Interrupted — remaining servers skipped"
            return 1
        fi
        return
    fi

    # ── Parallel mode ──────────────────────────────────────────────────────────
    _IS_pid_short=(); _IS_pid_tmpfile=(); _IS_active=()
    _IS_spin_i=0; _IS_done=0; _IS_stop_requested=0
    trap '_IS_sigint_handler' INT
    _IS_total=$(_IS_list_servers "$_servers_var" | wc -l)

    local _deferred_server=""

    while IFS= read -r server <&3; do
        # Defer local server to end when local_last=1
        if [ "$_local_last" = "1" ] && \
           { [ "$server" = "$MASTER_HOST" ] || [ "$(short_name "$server")" = "$(short_name "$MASTER_HOST")" ]; }; then
            _deferred_server="$server"
            _IS_total=$(( _IS_total - 1 ))
            continue
        fi

        local short _tmpfile _pid
        short=$(short_name "$server")

        # If pool full, poll until one job finishes (animating spinner while waiting)
        if [ "${#_IS_active[@]}" -ge "$max_jobs" ]; then
            local _done_pid=""
            until [ -n "$_done_pid" ] || [ "$_IS_stop_requested" = 1 ]; do
                for _p in "${_IS_active[@]}"; do
                    [ -f "${_IS_pid_tmpfile[$_p]}.done" ] && { wait "$_p" 2>/dev/null; _done_pid="$_p"; break; }
                done
                [ -z "$_done_pid" ] && { _IS_draw_progress; sleep 0.1; }
            done
            [ "$_IS_stop_requested" = 1 ] && break
            _IS_collect_result "$_done_pid"
        fi

        # Launch job in background; capture stdout + exit code to tmpfiles
        _tmpfile=$(mktemp)
        if [ "$server" = "$MASTER_HOST" ] || [ "$(short_name "$server")" = "$(short_name "$MASTER_HOST")" ]; then
            ( $local_fn > "$_tmpfile" 2>/dev/null; echo $? > "${_tmpfile}.exit"; touch "${_tmpfile}.done" ) &
        else
            ( $remote_fn "$server" > "$_tmpfile" 2>/dev/null; echo $? > "${_tmpfile}.exit"; touch "${_tmpfile}.done" ) &
        fi
        _pid=$!
        _IS_pid_short[$_pid]="$short"
        _IS_pid_tmpfile[$_pid]="$_tmpfile"
        _IS_active+=("$_pid")
        _IS_draw_progress

    done 3< <(_IS_list_servers "$_servers_var")

    # Drain all remote jobs
    while [ "${#_IS_active[@]}" -gt 0 ]; do
        [ "$_IS_stop_requested" = 1 ] && break
        local _done_pid=""
        until [ -n "$_done_pid" ] || [ "$_IS_stop_requested" = 1 ]; do
            for _p in "${_IS_active[@]}"; do
                [ -f "${_IS_pid_tmpfile[$_p]}.done" ] && { wait "$_p" 2>/dev/null; _done_pid="$_p"; break; }
            done
            [ -z "$_done_pid" ] && { _IS_draw_progress; sleep 0.1; }
        done
        [ "$_IS_stop_requested" = 1 ] && break
        _IS_collect_result "$_done_pid"
    done

    # Process deferred local server after all remotes are done
    if [ -n "$_deferred_server" ] && [ "$_IS_stop_requested" != "1" ]; then
        local short _tmpfile fn_exit _status _detail
        short=$(short_name "$_deferred_server")
        _tmpfile=$(mktemp)
        printf "\r\033[K"
        _spin_start "$short"
        $local_fn > "$_tmpfile" 2>/dev/null
        fn_exit=$?
        _IS_parse_result "$_tmpfile" "$fn_exit"
        _spin_stop "$short" "$_status" "$_detail"
        rm -f "$_tmpfile"
    fi

    printf "\r\033[K"
    trap - INT
    if [ "$_IS_stop_requested" = 1 ]; then
        warn "Interrupted — remaining servers skipped"
        return 1
    fi
}

# Appends a value to a named array and emits the __APPEND protocol line
# so parallel jobs can propagate the mutation to the parent scope.
# Usage: append_result <array_name> <value>
append_result() {
    local arr_name=$1
    local value=$2
    local -n _arr_ref=$arr_name
    _arr_ref+=("$value")
    echo "__APPEND $arr_name $value"
}

# Calls iterate_servers using pod_servers when _all is false, all servers otherwise.
# Requires collect_pod_servers to have been called beforehand.
# Usage: iterate_pod_servers <local_fn> <remote_fn>
iterate_pod_servers() {
    local local_fn=$1
    local remote_fn=$2
    if [ "$_all" = "true" ]; then
        iterate_servers "$local_fn" "$remote_fn"
    else
        iterate_servers "$local_fn" "$remote_fn" pod_servers
    fi
}
