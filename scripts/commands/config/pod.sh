#!/bin/bash

##
# @menu Pods
# @order 11
#
# Manages pods configuration in config.json.
#
# Usage: fleetman config pod
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
# Usage: _pod_write [jq-options...] <filter>
_pod_write() {
    local _tmp
    _tmp=$(mktemp)
    if ! jq "$@" "$CONFIG_FILE" > "$_tmp" || ! mv "$_tmp" "$CONFIG_FILE"; then
        rm -f "$_tmp"
        err "Failed to write config"
        exit 1
    fi
}

_pod_display_all() {
    local _pod _nv _nt
    while IFS= read -r _pod; do
        _nv=$(jq --arg p "$_pod" '.pods[$p].env_vars // [] | length' "$CONFIG_FILE")
        _nt=$(jq --arg p "$_pod" '.pods[$p].env_templates // {} | length' "$CONFIG_FILE")
        ok "$_pod  (${_nv} env_vars, ${_nt} env_templates)"
    done < <(jq -r '.pods // {} | keys[]' "$CONFIG_FILE")
}
_pod_add() {
    local _name
    local -a _available

    if [ -f "$PODS_FILE" ]; then
        local -a _all_pods
        mapfile -t _all_pods < <(jq -r '.[] | to_entries[] | .value[]' "$PODS_FILE" | sort -u)
        local _p _in_config
        for _p in "${_all_pods[@]}"; do
            _in_config=$(jq -r --arg p "$_p" '.pods // {} | has($p)' "$CONFIG_FILE")
            if [ "$_in_config" = "false" ]; then
                _available+=("$_p")
            fi
        done

        if [ "${#_available[@]}" -eq 0 ]; then
            warn "All pods already configured"
            return 0
        fi

        select_menu _available
        _name="${_available[$SELECTED_IDX]}"
    else
        _name=$(prompt_response "Pod name")
        if [ -z "$_name" ]; then
            warn "Empty name — cancelled"
            return 0
        fi
        local _exists
        _exists=$(jq -r --arg p "$_name" '.pods // {} | has($p)' "$CONFIG_FILE")
        if [ "$_exists" = "true" ]; then
            warn "Pod already configured: $_name"
            return 0
        fi
    fi

    # shellcheck disable=SC2016
    _pod_write --arg p "$_name" '.pods[$p] = {"env_vars": [], "env_templates": {}}'
    ok "Pod added: $_name"
    changed=true
}
_pod_remove() {
    local _pod="$1"

    printf "  Confirm removal of \"%s\" ? [y/N] " "$_pod"
    local _ans
    read -r _ans
    _ans="${_ans:-N}"

    if [[ "${_ans,,}" != "y" ]]; then
        ok "Cancelled"
        return 0
    fi

    # shellcheck disable=SC2016
    _pod_write --arg p "$_pod" 'del(.pods[$p])'
    ok "Pod removed: $_pod"
    changed=true
}
_pod_manage_envvars() {
    local _pod="$1"

    section "env_vars — $_pod"

    local -a _vars
    mapfile -t _vars < <(jq -r --arg p "$_pod" '.pods[$p].env_vars // [] | .[]' "$CONFIG_FILE")

    if [ "${#_vars[@]}" -eq 0 ]; then
        warn "No variable"
    else
        local _v
        for _v in "${_vars[@]}"; do
            ok "$_v"
        done
    fi

    if [ "${#_vars[@]}" -gt 0 ]; then
        printf "  Remove variables? [y/N] "
        local _remove_ans
        read -r _remove_ans
        if [[ "${_remove_ans:-N}" =~ ^[Yy] ]]; then
            select_menu_multi _vars
            if [ "${#SELECTED_INDICES[@]}" -gt 0 ]; then
                local -a _kept=()
                local _i _idx _is_sel
                for _i in "${!_vars[@]}"; do
                    _is_sel=false
                    for _idx in "${SELECTED_INDICES[@]}"; do
                        if [ "$_i" -eq "$_idx" ]; then _is_sel=true; break; fi
                    done
                    if [[ "$_is_sel" != "true" ]]; then
                        _kept+=("${_vars[$_i]}")
                    fi
                done
                local _kept_json
                if [ "${#_kept[@]}" -eq 0 ]; then
                    _kept_json='[]'
                else
                    _kept_json=$(printf '%s\n' "${_kept[@]}" | jq -R . | jq -s .)
                fi
                # shellcheck disable=SC2016
                _pod_write --arg p "$_pod" --argjson v "$_kept_json" '.pods[$p].env_vars = $v'
                _vars=("${_kept[@]}")
                changed=true
            fi
        fi
    fi

    while true; do
        local _new
        _new=$(prompt_response "Variable name (Enter to finish)" "")
        if [[ -z "$_new" ]]; then break; fi

        local _dup=false _v2
        for _v2 in "${_vars[@]}"; do
            if [[ "$_v2" == "$_new" ]]; then _dup=true; break; fi
        done
        if [[ "$_dup" == "true" ]]; then
            warn "Variable already present: $_new"
            continue
        fi

        local _in_tmpl
        _in_tmpl=$(jq -r --arg p "$_pod" --arg v "$_new" \
            '.pods[$p].env_templates // {} | has($v)' "$CONFIG_FILE")
        if [ "$_in_tmpl" = "true" ]; then
            err "Variable already in env_templates: $_new"
            exit 1
        fi

        # shellcheck disable=SC2016
        _pod_write --arg p "$_pod" --arg v "$_new" \
            '.pods[$p].env_vars = (.pods[$p].env_vars // []) + [$v]'
        _vars+=("$_new")
        ok "$_new"
        changed=true
    done
}
_pod_show_tokens() {
    printf "  Tokens built-in : {hostname} {short} {env} {pod} {name} {num} {suffix}\n"
    printf "    Case variants  : {FOO} = uppercase, {Foo} = title\n"
    local _tvars
    _tvars=$(jq -r '.template_vars // {} | keys[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ')
    if [ -n "$_tvars" ]; then
        printf "  Template vars   :"
        local _k
        # shellcheck disable=SC2086
        for _k in $_tvars; do
            printf " {%s}" "$_k"
        done
        printf "\n"
    fi
}

_pod_manage_templates() {
    local _pod="$1"

    section "env_templates — $_pod"

    local -a _keys
    mapfile -t _keys < <(jq -r --arg p "$_pod" \
        '.pods[$p].env_templates // {} | keys[]' "$CONFIG_FILE")

    if [ "${#_keys[@]}" -eq 0 ]; then
        warn "No template"
    else
        local _k _v
        for _k in "${_keys[@]}"; do
            _v=$(jq -r --arg p "$_pod" --arg k "$_k" \
                '.pods[$p].env_templates[$k]' "$CONFIG_FILE")
            ok "$_k = \"$_v\""
        done
    fi
    echo ""

    local -a _actions=("Add")
    if [ "${#_keys[@]}" -gt 0 ]; then
        _actions+=("Edit" "Remove")
    fi
    _actions+=("Back")

    select_menu _actions
    local _action="${_actions[$SELECTED_IDX]}"

    case "$_action" in
        "Back") return 0 ;;

        "Add")
            local _name
            _name=$(prompt_response "Variable name")
            if [ -z "$_name" ]; then return 0; fi

            local _in_vars
            _in_vars=$(jq -r --arg p "$_pod" --arg v "$_name" \
                '.pods[$p].env_vars // [] | contains([$v])' "$CONFIG_FILE")
            if [ "$_in_vars" = "true" ]; then
                err "Variable already in env_vars: $_name"
                exit 1
            fi

            local _in_tmpl
            _in_tmpl=$(jq -r --arg p "$_pod" --arg v "$_name" \
                '.pods[$p].env_templates // {} | has($v)' "$CONFIG_FILE")
            if [ "$_in_tmpl" = "true" ]; then
                warn "Template already present: $_name"
                return 0
            fi

            _pod_show_tokens
            local _tmpl
            _tmpl=$(prompt_response "Template")
            # shellcheck disable=SC2016
            _pod_write --arg p "$_pod" --arg k "$_name" --arg v "$_tmpl" \
                '.pods[$p].env_templates[$k] = $v'
            ok "$_name = \"$_tmpl\""
            changed=true
            ;;

        "Edit")
            select_menu _keys
            local _key="${_keys[$SELECTED_IDX]}"
            local _cur
            _cur=$(jq -r --arg p "$_pod" --arg k "$_key" \
                '.pods[$p].env_templates[$k]' "$CONFIG_FILE")
            _pod_show_tokens
            local _new_tmpl
            _new_tmpl=$(prompt_response "New template for $_key" "$_cur")
            # shellcheck disable=SC2016
            _pod_write --arg p "$_pod" --arg k "$_key" --arg v "$_new_tmpl" \
                '.pods[$p].env_templates[$k] = $v'
            ok "$_key : \"$_cur\" → \"$_new_tmpl\""
            changed=true
            ;;

        "Remove")
            select_menu_multi _keys
            if [ "${#SELECTED_INDICES[@]}" -gt 0 ]; then
                printf "  Confirm removal? [y/N] "
                local _ans
                read -r _ans
                _ans="${_ans:-N}"
                if [[ "${_ans,,}" == "y" ]]; then
                    local _idx _key_to_del
                    for _idx in "${SELECTED_INDICES[@]}"; do
                        _key_to_del="${_keys[$_idx]}"
                        # shellcheck disable=SC2016
                        _pod_write --arg p "$_pod" --arg k "$_key_to_del" \
                            'del(.pods[$p].env_templates[$k])'
                    done
                    ok "Template(s) removed"
                    changed=true
                fi
            fi
            ;;
    esac
}

cmd_config_pod() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — pods"

    local changed=false

    while true; do
        echo ""
        local -a _pod_names
        mapfile -t _pod_names < <(jq -r '.pods // {} | keys[]' "$CONFIG_FILE")

        if [ "${#_pod_names[@]}" -eq 0 ]; then
            warn "No pod configured"
        else
            _pod_display_all
        fi
        echo ""

        local -a _menu=("${_pod_names[@]}" "── Add a new pod ──" "Quit")
        select_menu _menu
        local _choice="${_menu[$SELECTED_IDX]}"

        case "$_choice" in
            "Quit") break ;;
            "── Add a new pod ──") _pod_add ;;
            *)
                local -a _sub=("Manage env_vars" "Manage env_templates" "Remove this pod" "Back")
                select_menu _sub
                local _sub_choice="${_sub[$SELECTED_IDX]}"
                case "$_sub_choice" in
                    "Manage env_vars")       _pod_manage_envvars "$_choice" ;;
                    "Manage env_templates")  _pod_manage_templates "$_choice" ;;
                    "Remove this pod")       _pod_remove "$_choice" ;;
                    "Back") : ;;
                esac
                ;;
        esac
    done

    if [[ "$changed" == "true" ]]; then
        prompt_sync_confirm
    fi
}
