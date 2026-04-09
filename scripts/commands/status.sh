#!/bin/bash

##
# Checks fleet health: SSH reachability, Docker daemon, and container states
# listed in config.json status_checks.containers.
#
# Usage: fleetman status [-e <env>] [-h]
#
# Options:
#   -e <env>     Target environment: dev, test, or prod (default: all)
#   -h, --help   Show this help
#
# Examples:
#   fleetman status
#   fleetman status -e prod
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/iterate.sh
source "$_LIB/iterate.sh"

status_local() {
    local docker_ok=false

    if sudo_run docker info > /dev/null 2>&1; then
        docker_ok=true
    fi

    ok "SSH: local"
    if $docker_ok; then
        ok "Docker: running"
        while IFS= read -r container; do
            local cstatus
            # shellcheck disable=SC1083
            cstatus=$(sudo_run docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
            if [ "$cstatus" = "running" ]; then
                ok "$container: running"
            elif [ -n "$cstatus" ]; then
                warn "$container: $cstatus"
            else
                warn "$container: not found"
            fi
        done < <(jq -r '.status_checks.containers // [] | .[]' "$CONFIG_FILE" 2>/dev/null)
        ok "Status: ok"
    else
        err "Docker: not running"
        return 1
    fi
}

status_remote() {
    local server=$1
    local result _ssh_rc
    local check_containers
    check_containers=$(jq -r '.status_checks.containers // [] | .[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ')

    result=$(ssh_cmd "$server" bash -s << ENDSSH 2>/dev/null
docker_ok=false
if echo "$B64_PASS" | base64 -d | sudo -S docker info > /dev/null 2>&1; then
    docker_ok=true
fi
if \$docker_ok; then
    echo "docker:ok"
    for container in $check_containers; do
        cstatus=\$(echo "$B64_PASS" | base64 -d | sudo -S docker inspect --format='{{.State.Status}}' "\$container" 2>/dev/null)
        if [ "\$cstatus" = "running" ]; then
            echo "pod_ok:\$container"
        elif [ -n "\$cstatus" ]; then
            echo "pod_warn:\$container:\$cstatus"
        else
            echo "pod_missing:\$container"
        fi
    done
else
    echo "docker:error"
fi
ENDSSH
    )
    _ssh_rc=$?

    if [[ "$_ssh_rc" -eq 255 ]]; then
        err "SSH: unreachable"
        return 1
    fi

    ok "SSH: ok"
    while IFS= read -r line; do
        case "$line" in
            docker:ok)     ok   "Docker: running" ;;
            docker:error)  err  "Docker: not running"; return 1 ;;
            pod_ok:*)      ok   "${line#pod_ok:}: running" ;;
            pod_missing:*) warn "${line#pod_missing:}: not found" ;;
            pod_warn:*)
                local rest="${line#pod_warn:}"
                warn "${rest%%:*}: ${rest#*:}" ;;
        esac
    done <<< "$result"

    ok "Status: ok"
}

cmd_status() {
    local ENV_FILTER=""
    local OPTIND=1
    local _opt
    while getopts ":e:" _opt "$@"; do
        case "$_opt" in
            e) ENV_FILTER="$OPTARG" ;;
            :) err "Option -$OPTARG requires an argument"; exit 1 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_sshpass
    check_config_file
    parse_env "$ENV_FILTER"
    ask_password

    section "Fleet status [$(env_label)]"
    if [[ -s "$GIT_SERVER_FILE" ]]; then
        ok "Git clone: $(short_name "$(< "$GIT_SERVER_FILE")")"
        echo ""
    fi
    iterate_servers status_local status_remote
    print_summary
    [ "$failure_count" -eq 0 ]
}
