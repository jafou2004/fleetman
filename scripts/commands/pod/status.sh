#!/bin/bash

##
# @menu Status
# @order 2
#
# Shows Docker Compose service states for a pod on a chosen server.
# Displays a colored table with service status, uptime, and ports.
#
# Usage: fleetman pod status [-p <pod-search>] [-e <env>]
#
# When run from a pod directory, -p is optional (local status only).
#
# Options:
#   -p <pod>     Pod search term (optional if run from a pod directory)
#   -e <env>     Environment: dev, test, or prod (default: all)
#   -h, --help   Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"

_STATUS_COL_WIDTH=28

# Renders a colored table from the global _STATUS_ROWS array.
# Each entry: "ROW:<service>\t<state>\t<health>\t<uptime>\t<ports>"
render_status_table() {
    local max_svc=7
    local row stripped svc

    local -a _fields
    for row in "${_STATUS_ROWS[@]}"; do
        stripped="${row#ROW:}"
        mapfile -t _fields < <(printf '%s\n' "$stripped" | tr '\t' '\n')
        svc="${_fields[0]:-}"
        if [ "${#svc}" -gt "$max_svc" ]; then max_svc="${#svc}"; fi
    done

    local sep_len
    sep_len=$(( max_svc + 2 + _STATUS_COL_WIDTH + 2 + 12 + 2 + 24 ))
    printf "  %-${max_svc}s  %-${_STATUS_COL_WIDTH}s  %-12s  %s\n" \
        "SERVICE" "STATUS" "UPTIME" "PORTS"
    printf "  "
    printf '─%.0s' $(seq 1 "$sep_len")
    printf '\n'

    local state health uptime ports color icon status_display full_status pad
    local -a _f

    for row in "${_STATUS_ROWS[@]}"; do
        stripped="${row#ROW:}"
        mapfile -t _f < <(printf '%s\n' "$stripped" | tr '\t' '\n')
        svc="${_f[0]:-}"
        state="${_f[1]:-}"
        health="${_f[2]:-}"
        uptime="${_f[3]:-}"
        ports="${_f[4]:-}"

        case "$state" in
            running)
                if [ -n "$health" ]; then
                    if [ "$health" = "healthy" ]; then
                        color="$GREEN"; icon="✓"; status_display="running (healthy)"
                    else
                        color="$YELLOW"; icon="⚠"; status_display="running ($health)"
                    fi
                else
                    color="$GREEN"; icon="✓"; status_display="running"
                fi
                ;;
            exited*|dead)
                color="$RED"; icon="✗"; status_display="$state"
                ;;
            *)
                color="$YELLOW"; icon="⚠"; status_display="$state"
                ;;
        esac

        full_status="$icon $status_display"
        pad=$(( _STATUS_COL_WIDTH - ${#full_status} ))
        if [ "$pad" -lt 0 ]; then pad=0; fi

        printf "  %-${max_svc}s  ${color}%s${NC}%*s  %-12s  %s\n" \
            "$svc" \
            "$full_status" \
            "$pad" "" \
            "${uptime:-—}" \
            "${ports:-—}"
    done
}
# Parse JSON lines (docker compose ps --format json) into the global _STATUS_ROWS array.
# Each entry format: "ROW:<service>\t<state>\t<health>\t<uptime>\t<ports>"
# Arguments: $1 = multi-line JSON string
_parse_status_rows() {
    local raw=$1
    _STATUS_ROWS=()

    local json_line row
    while IFS= read -r json_line; do
        [ -z "$json_line" ] && continue
        row=$(printf '%s' "$json_line" | jq -r '
          (.Service) + "\t" +
          (.State // "") + "\t" +
          (.Health // "") + "\t" +
          (if (.Status // "") | startswith("Up ") then (.Status | ltrimstr("Up ") | split(" (")[0]) else "" end) + "\t" +
          ([ .Publishers[]? | select(.PublishedPort > 0) |
             (.PublishedPort | tostring) + "→" + (.TargetPort | tostring) +
             (if (.Protocol // "tcp") != "tcp" then ("/" + .Protocol) else "" end)
          ] | unique | join(", "))
        ')
        _STATUS_ROWS+=("ROW:$row")
    done <<< "$raw"
}
# Displays Docker Compose status of a pod on a local or remote server.
# Arguments: $1 = target server FQDN
show_status() {
    local server=$1
    local raw_json=""

    if [ "$server" = "$MASTER_HOST" ]; then
        if [ ! -d "$PODS_DIR/$SELECTED_POD" ]; then
            warn "$PODS_DIR/$SELECTED_POD not found"
            return 0
        fi
        raw_json=$(cd "$PODS_DIR/$SELECTED_POD" && sudo_run docker compose ps --format json 2>/dev/null) || {
            err "docker compose ps failed"
            return 1
        }
    else
        local result _rc
        result=$(ssh_cmd "$server" bash -s << ENDSSH
if [ ! -d "$PODS_DIR/$SELECTED_POD" ]; then
    echo "ABSENT"
    exit 0
fi
cd "$PODS_DIR/$SELECTED_POD"
_tmpf=\$(mktemp)
if echo "$B64_PASS" | base64 -d | sudo -S docker compose ps --format json > "\$_tmpf" 2>/dev/null; then
    cat "\$_tmpf"
    rm -f "\$_tmpf"
else
    rm -f "\$_tmpf"
    echo "FAILED"
fi
ENDSSH
        )
        _rc=$?

        if [ "$_rc" -ne 0 ]; then
            err "$(short_name "$server"): unreachable"
            return 1
        fi
        case "$result" in
            ABSENT)
                warn "$PODS_DIR/$SELECTED_POD not found"
                return 0
                ;;
            FAILED)
                err "docker compose ps failed"
                return 1
                ;;
        esac
        raw_json="$result"
    fi

    _parse_status_rows "$raw_json"

    if [ "${#_STATUS_ROWS[@]}" -eq 0 ]; then
        warn "no services found"
        return 0
    fi

    render_status_table
}

cmd_pod_status() {
    local SEARCH="" ENV_FILTER="" OPTIND=1 _opt

    while getopts ":p:e:" _opt; do
        case "$_opt" in
            p) SEARCH="$OPTARG" ;;
            e) ENV_FILTER="$OPTARG" ;;
            :) err "Option -$_opt requires an argument"
               echo "Usage: fleetman pod status -p <pod> [-e env]"
               exit 1
               ;;
            \?) err "Unknown option: -$_opt"
                echo "Usage: fleetman pod status -p <pod> [-e env]"
                exit 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # ── Mode A: -p given → find pod, select server, show status ─────────────

    if [ -n "$SEARCH" ]; then
        check_sshpass
        check_config_file
        find_and_select_pod "$SEARCH" "$ENV_FILTER" "pod status: \"$SEARCH\""
        parse_env "$ENV_FILTER"
        collect_pod_servers
        ask_password

        local target_server
        if [ "${#pod_servers[@]}" -eq 1 ]; then
            target_server="${pod_servers[0]}"
        else
            local _labels=() _s
            for _s in "${pod_servers[@]}"; do
                _labels+=("$(short_name "$_s")")
            done
            select_menu _labels
            target_server="${pod_servers[$SELECTED_IDX]}"
        fi

        section "pod status: $SELECTED_POD [$label]"
        printf "  Server: %s\n\n" "$target_server"

        show_status "$target_server"

    # ── Mode B: no -p, current dir is a pod directory ────────────────────────

    elif [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
        local _pod_name _raw_json
        _pod_name=$(basename "$(pwd)")
        ask_password
        section "pod status: $_pod_name"
        printf "  Server: %s\n\n" "$(short_name "$MASTER_HOST")"
        _raw_json=$(sudo_run docker compose ps --format json 2>/dev/null) || {
            err "docker compose ps failed"
            unset PASSWORD
            exit 1
        }
        _parse_status_rows "$_raw_json"
        if [ "${#_STATUS_ROWS[@]}" -eq 0 ]; then
            warn "no services found"
        else
            render_status_table
        fi

    # ── Mode C: neither ───────────────────────────────────────────────────────

    else
        err "-p <pod> is required when not run from a pod directory."
        echo "  Run from a pod directory, or use -p <pod-search>."
        echo "  Use -h for help."
        exit 1
    fi

    unset PASSWORD
}
