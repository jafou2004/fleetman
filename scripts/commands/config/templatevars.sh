#!/bin/bash

##
# @menu Template vars
# @order 7
#
# Manages template variables used in pod .env template substitution.
#
# Usage: fleetman config templatevars
#
# Options:
#   -h, --help   Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/ui.sh
source "$_LIB/ui.sh"

# Atomic write helper. Runs jq with given options+filter against CONFIG_FILE.
# Usage: _tvars_write [jq-options...] <filter>
# Convention: filter is always the last argument; options come before it.
_tvars_write() {
    local _tmp
    _tmp=$(mktemp)
    if ! jq "$@" "$CONFIG_FILE" > "$_tmp" || ! mv "$_tmp" "$CONFIG_FILE"; then
        rm -f "$_tmp"
        err "Failed to write config"
        exit 1
    fi
}

# Displays all template_vars entries. Caller must ensure at least one exists.
_tvars_display_all() {
    local _vn _vtype _vval
    while IFS= read -r _vn; do
        _vtype=$(jq -r --arg k "$_vn" '.template_vars[$k] | type' "$CONFIG_FILE")
        if [ "$_vtype" = "object" ]; then
            local _display="" _ek _ev
            while IFS=$'\t' read -r _ek _ev; do
                if [ -n "$_display" ]; then _display+="  |  "; fi
                _display+="$_ek → \"${_ev,,}\""
            done < <(jq -r --arg k "$_vn" \
                '.template_vars[$k] | to_entries[] | "\(.key)\t\(.value)"' "$CONFIG_FILE")
            ok "$_vn = $_display"
        else
            _vval=$(jq -r --arg k "$_vn" '.template_vars[$k]' "$CONFIG_FILE")
            ok "$_vn = \"${_vval,,}\""
        fi
    done < <(jq -r '.template_vars // {} | keys[]' "$CONFIG_FILE")
}

# Adds a new template variable (simple string or scoped object).
# Sets parent-scope `changed=true` on success (bash dynamic scoping).
_tvars_add() {
    local _name
    _name=$(prompt_response "Variable name")

    local _exists
    _exists=$(jq -r --arg k "$_name" '.template_vars // {} | has($k)' "$CONFIG_FILE")
    if [ "$_exists" = "true" ]; then
        warn "Variable already defined: $_name"
        return 0
    fi

    local _star_val
    _star_val=$(prompt_response "Value * (fallback)")

    local -a _env_names
    mapfile -t _env_names < <(jq -r '.servers | keys[]' "$CONFIG_FILE")

    local -A _overrides
    local _add_more
    while true; do
        printf "  Add an env override? [y/N] "
        read -r _add_more
        _add_more="${_add_more:-N}"
        if [[ "${_add_more,,}" != "y" ]]; then break; fi
        select_menu _env_names
        local _sel_env="${_env_names[$SELECTED_IDX]}"
        local _env_val
        _env_val=$(prompt_response "Value for $_sel_env")
        _overrides["$_sel_env"]="$_env_val"
    done

    if [ "${#_overrides[@]}" -eq 0 ]; then
        # shellcheck disable=SC2016
        _tvars_write --arg k "$_name" --arg v "$_star_val" '.template_vars[$k] = $v'
    else
        local _obj _ek
        # shellcheck disable=SC2016
        _obj=$(jq -n --arg star "$_star_val" '{"*": $star}')
        for _ek in "${!_overrides[@]}"; do
            # shellcheck disable=SC2016
            _obj=$(jq --arg k "$_ek" --arg v "${_overrides["$_ek"]}" '.[$k] = $v' <<< "$_obj")
        done
        # shellcheck disable=SC2016
        _tvars_write --arg k "$_name" --argjson v "$_obj" '.template_vars[$k] = $v'
    fi

    ok "Variable added: $_name"
    changed=true
}

# Edits an existing template variable (simple or scoped).
# Sets parent-scope `changed=true` on success.
_tvars_edit() {
    local -a _var_names
    mapfile -t _var_names < <(jq -r '.template_vars // {} | keys[]' "$CONFIG_FILE")
    select_menu _var_names
    local _name="${_var_names[$SELECTED_IDX]}"

    local _vtype
    _vtype=$(jq -r --arg k "$_name" '.template_vars[$k] | type' "$CONFIG_FILE")

    if [ "$_vtype" = "string" ]; then
        local _cur_val
        _cur_val=$(jq -r --arg k "$_name" '.template_vars[$k]' "$CONFIG_FILE")
        local _new_val
        _new_val=$(prompt_response "Nouvelle valeur pour $_name" "$_cur_val")

        printf "  Ajouter des overrides par env ? [y/N] "
        local _do_scope
        read -r _do_scope
        _do_scope="${_do_scope:-N}"

        if [[ "${_do_scope,,}" == "y" ]]; then
            local -a _env_names
            mapfile -t _env_names < <(jq -r '.servers | keys[]' "$CONFIG_FILE")
            local -A _overrides
            local _add_more
            while true; do
                printf "  Ajouter un override env ? [y/N] "
                read -r _add_more
                _add_more="${_add_more:-N}"
                if [[ "${_add_more,,}" != "y" ]]; then break; fi
                select_menu _env_names
                local _sel_env="${_env_names[$SELECTED_IDX]}"
                local _env_val
                _env_val=$(prompt_response "Valeur pour $_sel_env")
                _overrides["$_sel_env"]="$_env_val"
            done
            local _obj _ek
            # shellcheck disable=SC2016
            _obj=$(jq -n --arg star "$_new_val" '{"*": $star}')
            for _ek in "${!_overrides[@]}"; do
                # shellcheck disable=SC2016
                _obj=$(jq --arg k "$_ek" --arg v "${_overrides["$_ek"]}" '.[$k] = $v' <<< "$_obj")
            done
            # shellcheck disable=SC2016
            _tvars_write --arg k "$_name" --argjson v "$_obj" '.template_vars[$k] = $v'
        else
            # shellcheck disable=SC2016
            _tvars_write --arg k "$_name" --arg v "$_new_val" '.template_vars[$k] = $v'
        fi
        ok "$_name : \"$_cur_val\" → \"$_new_val\""
        changed=true

    else
        # Scoped: pick a key to edit, then offer adding a new override.
        local -a _keys
        mapfile -t _keys < <(jq -r --arg k "$_name" '.template_vars[$k] | keys[]' "$CONFIG_FILE")
        select_menu _keys
        local _key="${_keys[$SELECTED_IDX]}"

        local _cur_val
        _cur_val=$(jq -r --arg k "$_name" --arg ek "$_key" '.template_vars[$k][$ek]' "$CONFIG_FILE")
        local _new_val
        _new_val=$(prompt_response "Nouvelle valeur pour ${_name}[${_key}]" "$_cur_val")
        # shellcheck disable=SC2016
        _tvars_write --arg k "$_name" --arg ek "$_key" --arg v "$_new_val" \
            '.template_vars[$k][$ek] = $v'
        ok "${_name}[${_key}] : \"$_cur_val\" → \"$_new_val\""
        changed=true

        printf "  Ajouter un autre override env ? [y/N] "
        local _add_env
        read -r _add_env
        _add_env="${_add_env:-N}"
        if [[ "${_add_env,,}" == "y" ]]; then
            local -a _env_names
            mapfile -t _env_names < <(jq -r '.servers | keys[]' "$CONFIG_FILE")
            select_menu _env_names
            local _new_env="${_env_names[$SELECTED_IDX]}"
            local _new_env_val
            _new_env_val=$(prompt_response "Valeur pour $_new_env")
            # shellcheck disable=SC2016
            _tvars_write --arg k "$_name" --arg ek "$_new_env" --arg v "$_new_env_val" \
                '.template_vars[$k][$ek] = $v'
            ok "${_name}[${_new_env}] = \"$_new_env_val\""
        fi
    fi
}

# Deletes an entire template variable.
# Sets parent-scope `changed=true` on confirmed deletion.
_tvars_del_var() {
    local -a _var_names
    mapfile -t _var_names < <(jq -r '.template_vars // {} | keys[]' "$CONFIG_FILE")
    select_menu _var_names
    local _name="${_var_names[$SELECTED_IDX]}"

    printf "  Confirm removal of %s? [y/N] " "$_name"
    local _ans
    read -r _ans
    _ans="${_ans:-N}"
    if [[ "${_ans,,}" != "y" ]]; then
        ok "Cancelled"
        return 0
    fi

    # shellcheck disable=SC2016
    _tvars_write --arg k "$_name" 'del(.template_vars[$k])'
    ok "Variable removed: $_name"
    changed=true
}

# Deletes an env-specific override from a scoped template variable.
# If only "*" remains after deletion, converts to a simple string.
# Sets parent-scope `changed=true` on confirmed deletion.
_tvars_del_env() {
    local -a _scoped_names
    mapfile -t _scoped_names < <(jq -r \
        '.template_vars // {} | to_entries[] | select(.value | type == "object") | .key' \
        "$CONFIG_FILE")
    select_menu _scoped_names
    local _name="${_scoped_names[$SELECTED_IDX]}"

    local -a _env_keys
    mapfile -t _env_keys < <(jq -r --arg k "$_name" \
        '.template_vars[$k] | keys[] | select(. != "*")' "$CONFIG_FILE")
    select_menu _env_keys
    local _env="${_env_keys[$SELECTED_IDX]}"

    printf "  Confirm removal of %s[%s]? [y/N] " "$_name" "$_env"
    local _ans
    read -r _ans
    _ans="${_ans:-N}"
    if [[ "${_ans,,}" != "y" ]]; then
        ok "Cancelled"
        return 0
    fi

    local _remaining
    # shellcheck disable=SC2016
    _remaining=$(jq --arg k "$_name" --arg ek "$_env" \
        'del(.template_vars[$k][$ek]) | .template_vars[$k] | keys | length' "$CONFIG_FILE")

    if [ "$_remaining" -eq 1 ]; then
        # Only "*" remains — convert to simple string
        local _star_val
        _star_val=$(jq -r --arg k "$_name" '.template_vars[$k]["*"]' "$CONFIG_FILE")
        # shellcheck disable=SC2016
        _tvars_write --arg k "$_name" --arg v "$_star_val" \
            'del(.template_vars[$k]) | .template_vars[$k] = $v'
    else
        # shellcheck disable=SC2016
        _tvars_write --arg k "$_name" --arg ek "$_env" 'del(.template_vars[$k][$ek])'
    fi

    ok "Override removed: ${_name}[${_env}]"
    changed=true
}

cmd_config_templatevars() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — template vars"
    echo ""

    local changed=false

    # Phase 1: Display
    local -a _var_names
    mapfile -t _var_names < <(jq -r '.template_vars // {} | keys[]' "$CONFIG_FILE")

    if [ "${#_var_names[@]}" -eq 0 ]; then
        warn "No variable defined"
    else
        _tvars_display_all
    fi
    echo ""

    # Phase 2: Action menu
    local -a _actions=("Add variable")
    if [ "${#_var_names[@]}" -gt 0 ]; then
        _actions+=("Edit variable" "Delete variable")
        local _scoped_count
        _scoped_count=$(jq \
            '[.template_vars // {} | to_entries[] | select(.value | type == "object")] | length' \
            "$CONFIG_FILE")
        if [ "$_scoped_count" -gt 0 ]; then
            _actions+=("Delete env override")
        fi
    fi
    _actions+=("Quit")

    select_menu _actions
    local _action="${_actions[$SELECTED_IDX]}"

    case "$_action" in
        "Quit")                return 0 ;;
        "Add variable")        _tvars_add ;;
        "Edit variable")       _tvars_edit ;;
        "Delete variable")     _tvars_del_var ;;
        "Delete env override") _tvars_del_env ;;
    esac

    if [[ "$changed" == "true" ]]; then
        prompt_sync_confirm
    fi
}
