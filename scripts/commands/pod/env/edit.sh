#!/bin/bash

##
# @menu Edit .env
# @order 3
#
# Edits the .env file of a pod locally, using $EDITOR.
# For remote pods, fetches the file via SCP, opens it in $EDITOR, then pushes it back if modified.
#
# Usage: fleetman pod env edit -p <pod-search> [-e <env>]
#
# Options:
#   -p <pod>       Pod search term (required)
#   -e <env>       Environment: dev, test, or prod (default: all)
#   -h, --help     Show this help
#
# Examples:
#   fleetman pod env edit -p my-service
#   fleetman pod env edit -p my-service -e prod
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"

edit_local() {
    local pod_dir="$PODS_DIR/$SELECTED_POD"
    if [ ! -d "$pod_dir" ]; then
        err "Pod directory not found: $pod_dir"
        return 1
    fi
    if [ ! -f "$pod_dir/.env" ]; then
        err "No .env file found. Use \"fleetman pod env diff\" to create it."
        return 1
    fi
    ${EDITOR:-nano} "$pod_dir/.env"
    ok ".env updated locally."
}

edit_remote() {
    local server="$1"
    local tmpfile
    tmpfile=$(mktemp)
    if ! scp_cmd "$server:$PODS_DIR/$SELECTED_POD/.env" "$tmpfile" > /dev/null 2>&1; then
        err "Could not fetch .env from $server."
        rm -f "$tmpfile"
        return 1
    fi
    local hash_before hash_after
    hash_before=$(md5sum "$tmpfile" | cut -d' ' -f1)
    ${EDITOR:-nano} "$tmpfile"
    hash_after=$(md5sum "$tmpfile" | cut -d' ' -f1)
    if [ "$hash_before" = "$hash_after" ]; then
        warn "No changes made."
        rm -f "$tmpfile"
        return 0
    fi
    if scp_cmd "$tmpfile" "$server:$PODS_DIR/$SELECTED_POD/.env" > /dev/null 2>&1; then
        ok ".env updated on $server."
    else
        err "Could not push .env to $server."
    fi
    rm -f "$tmpfile"
}

cmd_pod_env_edit() {
    local SEARCH="" ENV_FILTER="" opt
    OPTIND=1
    while getopts ":p:e:h" opt; do
        case "$opt" in
            p) SEARCH="$OPTARG" ;;
            e) ENV_FILTER="$OPTARG" ;;
            h) ;;
            :) err "Option -${OPTARG} requires an argument."; exit 1 ;;
            \?) err "Unknown option: -${OPTARG}"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ -z "$SEARCH" ]; then
        err "Error: a search term is required"
        echo "Usage: fleetman pod env edit -p <pod> [-e <env>]"
        exit 1
    fi

    check_sshpass
    check_config_file
    find_and_select_pod "$SEARCH" "$ENV_FILTER" "pod env edit: \"$SEARCH\""
    parse_env "$ENV_FILTER"
    collect_pod_servers

    local TEMPLATES_JSON
    TEMPLATES_JSON=$(jq -r --arg pod "$SELECTED_POD" \
        '.pods[$pod].env_templates // empty' "$CONFIG_FILE")

    ask_password

    # Server selection — show menu if multiple servers hosting the pod
    local server
    if [ "${#pod_servers[@]}" -gt 1 ]; then
        local -a srv_labels=()
        local s
        for s in "${pod_servers[@]}"; do srv_labels+=("$(short_name "$s")"); done
        section "pod env edit: \"$SEARCH\" [$label]"
        echo ""
        select_menu srv_labels
        echo ""
        server="${pod_servers[$SELECTED_IDX]}"
    else
        server="${pod_servers[0]}"
    fi

    # Warn about template-managed variables
    if [ -n "$TEMPLATES_JSON" ]; then
        local tmpl_vars
        tmpl_vars=$(jq -r 'keys | join(", ")' <<< "$TEMPLATES_JSON")
        warn "Template-managed variables (do not edit manually): $tmpl_vars"
    fi

    section "pod env edit: $(short_name "$server") → $SELECTED_POD"
    echo ""

    # Dispatch — local or remote (directional: single server, no iterate_pod_servers)
    if is_local_server "$server"; then
        edit_local
    else
        edit_remote "$server"
    fi

    unset PASSWORD
}
