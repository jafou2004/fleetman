#!/bin/bash

##
# @menu Update pod
# @order 7
#
# Updates .env variables for a pod on all servers hosting it, then restarts it.
# Variables to prompt for are declared in config.json .pods.<pod>.env_vars.
# After updating, re-applies env_templates from config.json per-server.
#
# Usage: fleetman pod update -p <pod-search> [-e <env>]
#
# Options:
#   -p <pod>       Pod search term (required)
#   -e <env>       Environment: dev, test, or prod (default: all)
#   -h, --help     Show this help
#
# Examples:
#   fleetman pod update -p my-service
#   fleetman pod update -p my-service -e prod
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"
source "$_LIB/iterate.sh"
source "$_LIB/templates.sh"

# Script-level globals
TEMPLATES_JSON=""
TEMPLATE_VARS_JSON=""
USER_SED_CMDS=""
POD_DIR=""
POD_ENV=""
POD_COMPOSE=""
FIRST_SERVER=""
ENV_VARS=()
declare -A current_values=()
declare -A new_values=()

# Builds USER_SED_CMDS (semicolon-separated sed expression) from new_values.
_build_user_sed_cmds() {
    USER_SED_CMDS=""
    local var val_escaped
    for var in "${!new_values[@]}"; do
        val_escaped=$(_escape_for_sed "${new_values[$var]}")
        USER_SED_CMDS="${USER_SED_CMDS:+$USER_SED_CMDS;}s|^${var}=.*|${var}=${val_escaped}|"
    done
}

# Loads env_vars for $SELECTED_POD from $CONFIG_FILE into the global ENV_VARS array.
# If the pod has no config entry, warns and prompts to continue; adds an empty entry on yes.
# Returns 1 if the user aborts, 0 otherwise.
load_pod_env_vars() {
    ENV_VARS=()
    while IFS= read -r var; do
        [ -n "$var" ] && ENV_VARS+=("$var")
    done < <(jq -r --arg pod "$SELECTED_POD" '.pods[$pod].env_vars // [] | .[]' "$CONFIG_FILE" 2>/dev/null)

    if [ "${#ENV_VARS[@]}" -eq 0 ] && ! jq -e --arg pod "$SELECTED_POD" 'has("pods") and (.pods | has($pod))' "$CONFIG_FILE" > /dev/null 2>&1; then
        warn "No .env configuration found for \"$SELECTED_POD\" — this pod may have no variables to update."
        if ! prompt_confirm "Continue anyway?"; then
            return 1
        fi
        local tmp
        tmp=$(mktemp)
        jq --arg pod "$SELECTED_POD" '.pods[$pod] = { "env_vars": [] }' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        ok "Added empty config for \"$SELECTED_POD\" in config.json"
        echo ""
    fi
    return 0
}

# Determines which server to read the current .env values from.
# Sets global FIRST_SERVER (FQDN or empty).
resolve_first_server() {
    FIRST_SERVER=""
    if [ "$_all" != "true" ] && [ "${#pod_servers[@]}" -gt 0 ]; then
        FIRST_SERVER="${pod_servers[0]}"
    else
        FIRST_SERVER=$(
            if [ -n "$ENV_FILTER" ]; then
                jq -r --arg e "$ENV_FILTER" --arg pod "$SELECTED_POD" \
                    '.[$e] | to_entries[] | select(.value[] == $pod) | .key' "$PODS_FILE" 2>/dev/null
            else
                jq -r --arg pod "$SELECTED_POD" \
                    '.[] | to_entries[] | select(.value[] == $pod) | .key' "$PODS_FILE" 2>/dev/null
            fi | head -1
        )
    fi
}

# Reads current .env variable values from $FIRST_SERVER.
# Sets global associative array current_values (var → value).
fetch_current_values() {
    current_values=()
    local env_content
    if [ -n "$FIRST_SERVER" ] && [ "${#ENV_VARS[@]}" -gt 0 ]; then
        if is_local_server "$FIRST_SERVER"; then
            env_content=$(cat "$POD_ENV" 2>/dev/null)
        else
            env_content=$(ssh_cmd "$FIRST_SERVER" "cat \"$POD_ENV\" 2>/dev/null")
        fi
        local var
        for var in "${ENV_VARS[@]}"; do
            current_values[$var]=$(printf '%s\n' "$env_content" | grep -E "^${var}=" | cut -d= -f2-)
        done
    fi
}

# Interactively prompts the user for new values for each ENV_VAR.
# Populates global new_values (only changed vars).
# Returns 1 if no changes and user declines restart, 0 otherwise.
# shellcheck disable=SC2059
prompt_new_values() {
    section "Updating $SELECTED_POD [$label]"
    echo ""

    new_values=()
    if [ "${#ENV_VARS[@]}" -gt 0 ]; then
        echo -e "  ${YELLOW}Enter new values (leave empty to keep current):${NC}"
        echo ""
        local var current input
        for var in "${ENV_VARS[@]}"; do
            current="${current_values[$var]:-}"
            printf "  %-30s [current: %s] : " "$var" "$current"
            read -r input
            if [ -n "$input" ] && [ "$input" != "$current" ]; then
                new_values[$var]="$input"
            fi
        done
        echo ""

        if [ "${#new_values[@]}" -eq 0 ]; then
            warn "No changes — will only restart the pod (docker compose up -d)"
            if ! prompt_confirm "Continue?"; then
                return 1
            fi
            echo ""
        fi
    fi
    return 0
}

update_local() {
    if [ ! -d "$POD_DIR" ]; then
        warn "$POD_DIR not found, skipping"
        echo ""
        append_result absent "$(short_name "$MASTER_HOST") (local)"
        return 0
    fi

    local var val_escaped
    for var in "${!new_values[@]}"; do
        val_escaped=$(_escape_for_sed "${new_values[$var]}")
        if ! sed -i "s|^${var}=.*|${var}=${val_escaped}|" "$POD_ENV"; then
            err "Failed to update $var in $POD_ENV"
            echo ""
            return 1
        fi
    done

    if [ -n "$TEMPLATES_JSON" ]; then
        _apply_templates "$MASTER_HOST" "$POD_ENV"
    fi

    if sudo_run docker compose -f "$POD_COMPOSE" up -d; then
        ok "updated and restarted"
        echo ""
        return 0
    else
        err "docker compose up -d failed"
        echo ""
        return 1
    fi
}

update_remote() {
    local server="$1"
    local result

    if [ -n "$TEMPLATES_JSON" ]; then
        _build_sed_cmds "$server"
    fi

    result=$(ssh_cmd "$server" bash -s << ENDSSH
if [ ! -d "$POD_DIR" ]; then
    echo "ABSENT"
else
    if [ -n "$USER_SED_CMDS" ]; then sed -i "$USER_SED_CMDS" "$POD_ENV"; fi
    if [ -n "$SED_CMDS" ]; then sed -i "$SED_CMDS" "$POD_ENV"; fi
    if echo "$B64_PASS" | base64 -d | sudo -S docker compose -f "$POD_COMPOSE" up -d >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
    fi
fi
ENDSSH
)

    case "$result" in
        OK)
            ok "updated and restarted"
            echo ""
            return 0
            ;;
        ABSENT)
            warn "$POD_DIR not found, skipping"
            echo ""
            append_result absent "$(short_name "$server")"
            return 0
            ;;
        *)
            err "docker compose up -d failed"
            echo ""
            return 1
            ;;
    esac
}

cmd_pod_update() {
    parse_search_env_opts "$@" || true
    shift $((OPTIND - 1))

    if [ -z "$SEARCH" ]; then
        err "Error: a search term is required"
        echo "Usage: fleetman pod update -p <search> [-e env]"
        exit 1
    fi

    check_sshpass
    check_config_file
    find_and_select_pod "$SEARCH" "$ENV_FILTER" "pod update: \"$SEARCH\""

    POD_DIR="$PODS_DIR/$SELECTED_POD"
    POD_ENV="$POD_DIR/.env"
    POD_COMPOSE="$POD_DIR/docker-compose.yml"
    load_pod_templates "$SELECTED_POD"

    load_pod_env_vars || return 0

    parse_env "$ENV_FILTER"
    collect_pod_servers
    ask_password

    resolve_first_server
    fetch_current_values
    prompt_new_values || return 0

    _build_user_sed_cmds
    absent=()
    iterate_pod_servers update_local update_remote
    print_summary
    unset PASSWORD
}
