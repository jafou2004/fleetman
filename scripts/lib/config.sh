#!/bin/bash

# Configuration helpers — config.json parsing and validation.
[[ -n "${_FLEETMAN_CONFIG_LOADED:-}" ]] && return 0
_FLEETMAN_CONFIG_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"
source "$(dirname "${BASH_SOURCE[0]}")/display.sh"

check_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "parallel": 4,
  "pods_dir": "",
  "env_colors": {},
  "status_checks": { "containers": [] },
  "pods": {},
  "servers": {}
}
EOF
        warn "No config file found — a default one was created at $CONFIG_FILE"
        echo "  Edit it to declare your environments and servers, then re-run."
        exit 1
    fi
}

# Validates the environment argument and sets $ENV.
# If absent, ENV="" => all servers will be processed.
# Must be called after check_config_file.
# Usage: parse_env "$ENV_FILTER"
parse_env() {
    local arg="$1"
    if [ -z "$arg" ]; then
        ENV=""
        return 0
    fi
    if ! jq -e --arg env "$arg" '.servers | has($env)' "$CONFIG_FILE" > /dev/null 2>&1; then
        local valid_envs
        valid_envs=$(jq -r '[.servers | keys[]] | join(", ")' "$CONFIG_FILE")
        err "Error: invalid environment '$arg'. Accepted values: $valid_envs"
        exit 1
    fi
    ENV="$arg"
}

# Returns the given environment in uppercase, or "ALL" if empty.
# With no arg: uses the global $ENV (set by parse_env).
# With one arg: uses that value — e.g. env_label "$ENV_FILTER".
env_label() {
    local _e="${1-$ENV}"
    [ -n "$_e" ] && echo "${_e^^}" || echo "ALL"
}

# Parses flags -p, -e, -h from the caller's "$@".
# Sets globals SEARCH="" and ENV_FILTER="".
# Usage in main(): parse_search_env_opts "$@" ; shift $?
parse_search_env_opts() {
    SEARCH="" ENV_FILTER=""
    local opt
    OPTIND=1
    while getopts ":p:e:h" opt "$@"; do
      case $opt in
        p) SEARCH="$OPTARG" ;;
        e) ENV_FILTER="$OPTARG" ;;
        h) help; exit 0 ;;
        :) err "Option -$OPTARG requires an argument."; exit 1 ;;
        \?) err "Unknown option: -$OPTARG"; exit 1 ;;
      esac
    done
    return $((OPTIND - 1))
}

# Exits with error if $PODS_FILE does not exist.
# Call in scripts that query pods.json without going through find_and_select_pod.
check_pods_file() {
    if [ ! -f "$PODS_FILE" ]; then
        err "Error: $PODS_FILE not found — run 'fleetman sync' first"
        exit 1
    fi
}

# Validates $ENV_FILTER against the keys of $PODS_FILE; exits on mismatch.
# No-op if ENV_FILTER is empty. Must be called after check_pods_file.
validate_env_filter() {
    [ -z "$ENV_FILTER" ] && return 0
    if ! jq -e --arg env "$ENV_FILTER" 'has($env)' "$PODS_FILE" > /dev/null 2>&1; then
        local valid_envs
        valid_envs=$(jq -r '[keys[]] | join(", ")' "$PODS_FILE")
        err "Error: invalid environment '$ENV_FILTER'. Accepted values: $valid_envs"
        exit 1
    fi
}

# Collects all pod names matching $search in $env_filter scope.
# Validates search + pods.json + env_filter; shows interactive menu if multiple match.
# Sets globals: SELECTED_POD, label.
# Exits on error (pods.json missing, invalid env_filter, no match).
# Requires select_menu from ui.sh to be loaded by the caller.
# Usage: find_and_select_pod "$SEARCH" "$ENV_FILTER" "menu title"
find_and_select_pod() {
    local search=$1 env_filter=$2 menu_title=$3

    if [ -z "$search" ]; then
        err "Error: a search term is required"
        exit 1
    fi

    check_pods_file

    if [ -n "$env_filter" ]; then
        if ! jq -e --arg env "$env_filter" 'has($env)' "$PODS_FILE" > /dev/null 2>&1; then
            local valid_envs
            valid_envs=$(jq -r '[keys[]] | join(", ")' "$PODS_FILE")
            err "Error: invalid environment '$env_filter'. Accepted values: $valid_envs"
            exit 1
        fi
    fi

    local envs
    if [ -n "$env_filter" ]; then
        envs="$env_filter"
    else
        envs=$(jq -r 'keys[]' "$PODS_FILE")
    fi

    local pod_names=() pod found p
    while IFS= read -r env; do
        while IFS= read -r pod; do
            [ -z "$pod" ] && continue
            found=false
            for p in "${pod_names[@]}"; do [ "$p" = "$pod" ] && found=true && break; done
            if ! $found; then pod_names+=("$pod"); fi
        done < <(jq -r --arg e "$env" --arg s "$search" \
            '.[$e] | to_entries[] | .value[] | select(contains($s))' \
            "$PODS_FILE" 2>/dev/null)
    done <<< "$envs"

    if [ "${#pod_names[@]}" -eq 0 ]; then
        err "No pod matching \"$search\""
        exit 1
    fi

    if [ "${#pod_names[@]}" -eq 1 ]; then
        SELECTED_POD="${pod_names[0]}"
    else
        section "$menu_title"
        echo ""
        select_menu pod_names
        echo ""
        SELECTED_POD="${pod_names[$SELECTED_IDX]}"
    fi

    label=$([ -n "$env_filter" ] && echo "${env_filter^^}" || echo "ALL")
}

# Sets globals: pod_servers (array of FQDNs hosting $SELECTED_POD in $ENV scope),
# _all="false" (iterate_pod_servers always uses pod_servers list).
# Must be called after find_and_select_pod + parse_env.
collect_pod_servers() {
    pod_servers=()
    _all="false"

    local envs
    if [ -n "$ENV" ]; then
        envs="$ENV"
    else
        envs=$(jq -r 'keys[]' "$PODS_FILE")
    fi

    local env server
    while IFS= read -r env; do
        while IFS= read -r server; do
            [ -n "$server" ] && pod_servers+=("$server")
        done < <(jq -r --arg e "$env" --arg p "$SELECTED_POD" \
            '.[$e] | to_entries[] | select(.value[] == $p) | .key' \
            "$PODS_FILE" 2>/dev/null)
    done <<< "$envs"
}

# Collects servers and their matching pods for $SEARCH / $ENV_FILTER.
# Sets globals: server_pods (assoc: server → space-sep pods), server_order (indexed array).
# Must be called after check_pods_file + validate_env_filter.
collect_server_pods() {
    declare -gA server_pods=()
    server_order=()

    local envs
    if [ -n "$ENV_FILTER" ]; then
        envs="$ENV_FILTER"
    else
        envs=$(jq -r 'keys[]' "$PODS_FILE")
    fi

    local env
    while IFS= read -r env; do
        local results
        if [ -n "$SEARCH" ]; then
            results=$(jq -r --arg e "$env" --arg s "$SEARCH" \
                '.[$e] | to_entries[] | {k:.key, pods:[.value[]|select(contains($s))]} | select(.pods|length>0) | [.k, (.pods|join(" "))] | @tsv' \
                "$PODS_FILE" 2>/dev/null)
        else
            results=$(jq -r --arg e "$env" \
                '.[$e] | to_entries[] | [.key, (.value|join(" "))] | @tsv' \
                "$PODS_FILE" 2>/dev/null)
        fi

        if [ -n "$results" ]; then
            while IFS=$'\t' read -r server pods; do
                server_pods["$server"]="$pods"
                server_order+=("$server")
            done <<< "$results"
        fi
    done <<< "$envs"
}
