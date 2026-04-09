#!/bin/bash

##
# @menu Clone repo
# @order 9
#
# Clones a git repository to servers under the pods directory.
# Prompts for the repository URL and destination path.
# Creates .env from .env-dist automatically if present.
#
# Usage: fleetman pod clone [-e <env>] [-a]
#
# Options:
#   -e <env>       Environment: dev, test, or prod (default: all)
#   -a, --all      Deploy to all servers (default: select one per environment)
#   -h, --help     Show this help
#
# Examples:
#   fleetman pod clone
#   fleetman pod clone -e dev
#   fleetman pod clone -e dev -a
#   fleetman pod clone --all
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"
source "$_LIB/iterate.sh"

# Clone the repository on the local server.
clone_local() {
    if [ -d "$DEST_DIR" ]; then
        warn "Directory already exists, skipping"
        echo ""
        append_result already_present "$(short_name "$MASTER_HOST") (local)"
        return 0
    fi

    mkdir -p "$(dirname "$DEST_DIR")" 2>/dev/null
    if git clone "$REPO_URL" "$DEST_DIR" 2>/dev/null; then
        ok "Repository cloned successfully"
        if [ -f "$DEST_DIR/.env-dist" ]; then
            cp "$DEST_DIR/.env-dist" "$DEST_DIR/.env"
            warn ".env file created from .env-dist — remember to configure it"
            append_result env_to_configure "$(short_name "$MASTER_HOST") (local)"
        fi
        echo ""
        return 0
    else
        err "Clone failed"
        echo ""
        return 1
    fi
}

# Clone the repository on a remote server via SSH.
clone_remote() {
    local server=$1
    local result

    result=$(ssh_cmd "$server" bash -s << ENDSSH
if [ -d "$DEST_DIR" ]; then
    echo "ALREADY_PRESENT"
else
    mkdir -p "\$(dirname "$DEST_DIR")" 2>/dev/null
    if git clone "$REPO_URL" "$DEST_DIR" 2>/dev/null; then
        if [ -f "$DEST_DIR/.env-dist" ]; then
            cp "$DEST_DIR/.env-dist" "$DEST_DIR/.env"
            echo "CLONED_WITH_ENV"
        else
            echo "CLONED"
        fi
    else
        echo "CLONE_FAILED"
    fi
fi
ENDSSH
)

    case "$result" in
        ALREADY_PRESENT)
            warn "Directory already exists, skipping"
            echo ""
            append_result already_present "$(short_name "$server")"
            return 0
            ;;
        CLONED_WITH_ENV)
            ok "Repository cloned successfully"
            warn ".env file created from .env-dist — remember to configure it"
            echo ""
            append_result env_to_configure "$(short_name "$server")"
            return 0
            ;;
        CLONED)
            ok "Repository cloned successfully"
            echo ""
            return 0
            ;;
        *)
            err "Clone failed"
            echo ""
            return 1
            ;;
    esac
}

# Select one server per environment via interactive menu, then clone.
# Called when ALL_SERVERS=0. Handles __APPEND protocol manually since
# clone_local/clone_remote are called directly (not via iterate_servers).
deploy_selective() {
    local pre_selection=0
    local envs=()
    if [ -n "$ENV" ]; then
        envs=("$ENV")
    else
        mapfile -t envs < <(jq -r '.servers | keys[]' "$CONFIG_FILE")
    fi

    for env in "${envs[@]}"; do
        local server_fqdns=()
        mapfile -t server_fqdns < <(jq -r --arg e "$env" '.servers[$e][]' "$CONFIG_FILE")
        local labels=()
        local s
        for s in "${server_fqdns[@]}"; do labels+=("$(short_name "$s")"); done

        section "Select server for ${env^^}"
        echo ""
        select_menu labels "$pre_selection"
        echo ""
        pre_selection=$SELECTED_IDX
        local server="${server_fqdns[$SELECTED_IDX]}"

        local tmpfile rc
        tmpfile=$(mktemp)
        rc=0
        if [ "$server" = "$MASTER_HOST" ]; then
            clone_local > "$tmpfile" 2>&1 || rc=$?
        else
            clone_remote "$server" > "$tmpfile" 2>&1 || rc=$?
        fi

        # Print visible output; replay __APPEND mutations into parent scope
        local _line
        while IFS= read -r _line; do
            if [[ "$_line" == "__APPEND "* ]]; then
                local _arr _val
                read -r _ _arr _val <<< "$_line"
                eval "${_arr}+=(\"${_val}\")"
            else
                echo "$_line"
            fi
        done < "$tmpfile"
        rm -f "$tmpfile"

        if [ "$rc" -eq 0 ]; then
            success_count=$(( success_count + 1 ))
        else
            failure_count=$(( failure_count + 1 ))
        fi
    done
}

cmd_pod_clone() {
    # Pre-scan: convert --all to -a (getopts doesn't handle long options)
    local _filtered_args=()
    local _arg
    for _arg in "$@"; do
        case "$_arg" in
            --all) _filtered_args+=("-a") ;;
            *)     _filtered_args+=("$_arg") ;;
        esac
    done
    set -- "${_filtered_args[@]}"

    local ENV_FILTER="" ALL_SERVERS=0

    while getopts ":e:a" opt; do
        case $opt in
            e) ENV_FILTER="$OPTARG" ;;
            a) ALL_SERVERS=1 ;;
            :) err "Option -$OPTARG requires an argument."; exit 1 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_sshpass
    check_config_file
    parse_env "$ENV_FILTER"

    REPO_URL=$(prompt_response "Git repository URL")
    REPO_NAME=$(basename "$REPO_URL" .git)
    DEST_DIR=$(prompt_response "Destination directory" "$PODS_DIR/$REPO_NAME")

    echo ""
    section "Deploying '$REPO_NAME' to '$DEST_DIR' [$(env_label)]"
    echo ""

    ask_password

    already_present=()
    env_to_configure=()
    success_count=0
    # shellcheck disable=SC2034  # warn_count read by print_summary
    warn_count=0
    failure_count=0

    if [ "$ALL_SERVERS" -eq 1 ]; then
        iterate_servers clone_local clone_remote
        local updated
        updated=$(jq --arg p "$REPO_NAME" '
            if .pods[$p] then .pods[$p].all_servers = true
            else .pods[$p] = {"all_servers": true}
            end
        ' "$CONFIG_FILE")
        echo "$updated" > "$CONFIG_FILE"
        ok "config.json: $REPO_NAME → \"all_servers\": true"
    else
        deploy_selective
    fi

    print_summary "deployed"

    if [ ${#already_present[@]} -gt 0 ]; then
        echo ""
        warn "Directories already present (skipped) on:"
        for s in "${already_present[@]}"; do
            echo "    • $s"
        done
    fi

    if [ ${#env_to_configure[@]} -gt 0 ]; then
        echo ""
        warn ".env files to configure on:"
        for s in "${env_to_configure[@]}"; do
            echo "    • $s → $DEST_DIR/.env"
        done
    fi

    unset PASSWORD
}
