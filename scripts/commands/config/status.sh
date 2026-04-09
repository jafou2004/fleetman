#!/bin/bash

##
# @menu Status checks
# @order 2
#
# Manages status-check containers and WUD port in config.json.
#
# Usage: fleetman config status
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

cmd_config_status() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — status checks"

    local changed=false

    # ── 1. Display current containers ─────────────────────────────────────────
    local -a containers
    mapfile -t containers < <(jq -r '.status_checks.containers // [] | .[]' "$CONFIG_FILE" 2>/dev/null)

    if [ "${#containers[@]}" -eq 0 ]; then
        warn "No container followed"
    else
        local c
        for c in "${containers[@]}"; do
            ok "$c"
        done
    fi

    # ── 2. Remove step (only if list is non-empty) ────────────────────────────
    if [ "${#containers[@]}" -gt 0 ]; then
        printf "Remove containers? [y/N] "
        local remove_ans
        read -r remove_ans
        if [[ "${remove_ans:-N}" =~ ^[Yy] ]]; then
            select_menu_multi containers
            if [ "${#SELECTED_INDICES[@]}" -gt 0 ]; then
                local -a kept=()
                local -a removed_names=()
                local i idx is_selected
                for i in "${!containers[@]}"; do
                    is_selected=false
                    for idx in "${SELECTED_INDICES[@]}"; do
                        if [ "$i" -eq "$idx" ]; then
                            is_selected=true
                            break
                        fi
                    done
                    if [[ "$is_selected" == "true" ]]; then
                        removed_names+=("${containers[$i]}")
                    else
                        kept+=("${containers[$i]}")
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
                if ! jq --argjson v "$kept_json" '.status_checks.containers = $v' "$CONFIG_FILE" > "$tmp" \
                    || ! mv "$tmp" "$CONFIG_FILE"; then
                    rm -f "$tmp"
                    err "Failed to write config"
                    exit 1
                fi

                # Safe: codebase does not use set -u; empty array expands to nothing
                containers=("${kept[@]}")
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

    # ── 3. Add step ───────────────────────────────────────────────────────────
    printf "Containers to add (space-separated, Enter to skip)? "
    local new_raw
    read -r new_raw
    if [[ -n "$new_raw" ]]; then
        local -a new_containers
        read -ra new_containers <<< "$new_raw"
        local -a to_add=()
        local nc existing already
        for nc in "${new_containers[@]}"; do
            already=false
            for existing in "${containers[@]}"; do
                if [[ "$nc" == "$existing" ]]; then
                    already=true
                    break
                fi
            done
            if [[ "$already" == "true" ]]; then
                warn "Already followed, ignored: $nc"
            else
                to_add+=("$nc")
            fi
        done
        if [ "${#to_add[@]}" -gt 0 ]; then
            local add_json
            add_json=$(printf '%s\n' "${to_add[@]}" | jq -R . | jq -s .)
            local tmp
            tmp=$(mktemp)
            if ! jq --argjson v "$add_json" '.status_checks.containers = (.status_checks.containers // []) + $v' "$CONFIG_FILE" > "$tmp" \
                || ! mv "$tmp" "$CONFIG_FILE"; then
                rm -f "$tmp"
                err "Failed to write config"
                exit 1
            fi
            for nc in "${to_add[@]}"; do
                containers+=("$nc")
            done
            local added_str="" _a
            for _a in "${to_add[@]}"; do
                if [[ -n "$added_str" ]]; then added_str+=", "; fi
                added_str+="$_a"
            done
            ok "Added: $added_str"
            changed=true
        fi
    fi

    # ── 4. WUD port ───────────────────────────────────────────────────────────
    local current_wud
    current_wud=$(jq 'if .status_checks.wud_port != null then .status_checks.wud_port else 0 end' "$CONFIG_FILE")
    local new_wud
    new_wud=$(prompt_response "WUD port (0 = disabled)" "$current_wud")
    if [[ ! "$new_wud" =~ ^[0-9]+$ ]]; then
        err "Invalid value: must be a non-negative integer"
        exit 1
    fi
    if [[ "$new_wud" == "$current_wud" ]]; then
        ok "Unchanged (wud_port = $current_wud)"
    else
        local tmp
        tmp=$(mktemp)
        if ! jq --argjson v "$new_wud" '.status_checks.wud_port = $v' "$CONFIG_FILE" > "$tmp" \
            || ! mv "$tmp" "$CONFIG_FILE"; then
            rm -f "$tmp"
            err "Failed to write config"
            exit 1
        fi
        ok "wud_port: $current_wud → $new_wud"
        changed=true
    fi

    # ── 5. Propose sync if changed ────────────────────────────────────────────
    if [[ "$changed" == "true" ]]; then
        prompt_sync_confirm
    fi
}
