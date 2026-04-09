#!/bin/bash

##
# @menu Ignored Pods
# @order 3
#
# Manages pods_ignore PCRE patterns in config.json.
# Patterns are applied during fleetman sync to exclude matching pods from pods.json.
#
# Usage: fleetman config podsignore
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

cmd_config_podsignore() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — ignored pods"

    local changed=false

    # ── 1. Display current patterns ─────────────────────────────────────
    local -a patterns
    mapfile -t patterns < <(jq -r '.pods_ignore // [] | .[]' "$CONFIG_FILE" 2>/dev/null)

    if [ "${#patterns[@]}" -eq 0 ]; then
        warn "No pattern configured"
    else
        local p
        for p in "${patterns[@]}"; do
            ok "$p"
        done
    fi

    # ── 2. Removal (only if list non-empty) ──────────────────────────
    if [ "${#patterns[@]}" -gt 0 ]; then
        printf "Remove patterns? [y/N] "
        local remove_ans
        read -r remove_ans
        if [[ "${remove_ans:-N}" =~ ^[Yy] ]]; then
            select_menu_multi patterns
            if [ "${#SELECTED_INDICES[@]}" -gt 0 ]; then
                local -a kept=()
                local -a removed_names=()
                local i idx is_selected
                for i in "${!patterns[@]}"; do
                    is_selected=false
                    for idx in "${SELECTED_INDICES[@]}"; do
                        if [ "$i" -eq "$idx" ]; then
                            is_selected=true
                            break
                        fi
                    done
                    if [[ "$is_selected" == "true" ]]; then
                        removed_names+=("${patterns[$i]}")
                    else
                        kept+=("${patterns[$i]}")
                    fi
                done

                local kept_json
                if [ "${#kept[@]}" -eq 0 ]; then
                    kept_json='[]'
                else
                    kept_json=$(printf '%s\n' "${kept[@]}" | jq -R . | jq -s .)
                fi

                local tmp
                tmp=$(mktemp)
                if ! jq --argjson v "$kept_json" '.pods_ignore = $v' "$CONFIG_FILE" > "$tmp" \
                    || ! mv "$tmp" "$CONFIG_FILE"; then
                    rm -f "$tmp"
                    err "Failed to write config"
                    exit 1
                fi

                patterns=("${kept[@]}")
                local removed_str="" _n
                for _n in "${removed_names[@]}"; do
                    if [[ -n "$removed_str" ]]; then removed_str+=", "; fi
                    removed_str+="$_n"
                done
                ok "Removed: $removed_str"
                changed=true
            fi
        fi
    fi

    # ── 3. Add (loop until empty input) ─────────────────────────────────
    while true; do
        local new_pattern
        new_pattern=$(prompt_response "New PCRE pattern (Enter to finish)" "")
        if [[ -z "$new_pattern" ]]; then break; fi

        # Validation PCRE: exit code 2 = invalid regex
        printf '' | grep -P "$new_pattern" >/dev/null 2>&1
        local _rc=$?
        if [ "$_rc" -eq 2 ]; then
            err "Invalid PCRE pattern: $new_pattern"
            exit 1
        fi

        # Duplicate
        local already=false _p
        for _p in "${patterns[@]}"; do
            if [[ "$_p" == "$new_pattern" ]]; then
                already=true
                break
            fi
        done
        if [[ "$already" == "true" ]]; then
            warn "Pattern already present: $new_pattern"
            continue
        fi

        # Atomic add
        local tmp
        tmp=$(mktemp)
        if ! jq --arg v "$new_pattern" '.pods_ignore = (.pods_ignore // []) + [$v]' "$CONFIG_FILE" > "$tmp" \
            || ! mv "$tmp" "$CONFIG_FILE"; then
            rm -f "$tmp"
            err "Failed to write config"
            exit 1
        fi
        patterns+=("$new_pattern")
        ok "$new_pattern"
        changed=true

        # Preview: pods currently tracked that would match the pattern
        if [ -f "$PODS_FILE" ]; then
            local -a _preview
            mapfile -t _preview < <(jq -r --arg pat "$new_pattern" \
                '.[] | to_entries[] | .value[] | select(test($pat))' "$PODS_FILE" 2>/dev/null | sort -u)
            if [ "${#_preview[@]}" -gt 0 ]; then
                warn "Pods that would be ignored on next sync: $(IFS=', '; echo "${_preview[*]}")"
            else
                ok "No pod currently tracked matches this pattern"
            fi
        fi
    done

    # ── 4. Sync si changement ─────────────────────────────────────────────────
    if [[ "$changed" == "true" ]]; then
        prompt_sync_confirm
    fi
}
