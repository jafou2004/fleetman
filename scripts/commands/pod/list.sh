#!/bin/bash

##
# @menu List pods
# @order 6
#
# Lists pods from pods.json, optionally filtered by search term and/or environment.
#
# Usage: fleetman pod list [-p <search>] [-e <env>]
#
# Options:
#   -p <search>   Pod name search term (optional, default: all pods)
#   -e <env>      Environment: dev, test, or prod (default: all)
#   -h, --help    Show this help
#
# Examples:
#   fleetman pod list
#   fleetman pod list -e prod
#   fleetman pod list -p api
#   fleetman pod list -p worker -e dev
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/config.sh"

cmd_pod_list() {
    parse_search_env_opts "$@" || true
    shift $((OPTIND - 1))

    check_pods_file
    validate_env_filter

    local label
    label=$(env_label "$ENV_FILTER")
    if [ -n "$SEARCH" ]; then
        section "Search: \"$SEARCH\" [$label]"
    else
        section "Pods [$label]"
    fi

    local total=0
    local -a found_envs=()
    local env

    while IFS= read -r env; do
        local results
        if [ -n "$SEARCH" ]; then
            results=$(jq -r --arg e "$env" --arg s "$SEARCH" \
                '.[$e] | to_entries[] | .key as $server | .value[] | select(contains($s)) | [$server, .] | @tsv' \
                "$PODS_FILE" 2>/dev/null)
        else
            results=$(jq -r --arg e "$env" \
                '.[$e] | to_entries[] | .key as $server | .value[] | [$server, .] | @tsv' \
                "$PODS_FILE" 2>/dev/null)
        fi

        if [ -n "$results" ]; then
            found_envs+=("$env")
            echo ""
            echo -e "${BLUE}── ${env^^} ─────────────────────────────────────────────────${NC}"
            while IFS=$'\t' read -r server pod; do
                printf "  %-30s %s\n" "$(short_name "$server")" "$pod"
                total=$(( total + 1 ))
            done <<< "$results"
        fi
    done < <(
        if [ -n "$ENV_FILTER" ]; then
            echo "$ENV_FILTER"
        else
            jq -r 'keys[]' "$PODS_FILE"
        fi
    )

    echo ""
    if [ "$total" -eq 0 ]; then
        if [ -n "$SEARCH" ]; then
            warn "No results for \"$SEARCH\""
        else
            warn "No pods found"
        fi
    else
        ok "$total pod(s) across ${#found_envs[@]} environment(s)"
    fi
}
