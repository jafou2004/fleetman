#!/bin/bash

# Interactive UI helpers — prompts, menus, labels.
[[ -n "${_FLEETMAN_UI_LOADED:-}" ]] && return 0
_FLEETMAN_UI_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/vars.sh"
source "$(dirname "${BASH_SOURCE[0]}")/display.sh"

# Prompts the user for a value; loops until a non-empty input is given.
# Usage: var=$(prompt_response "Question" ["default"])
prompt_response() {
    local prompt="$1" default="$2" response=""
    while [[ -z "$response" ]]; do
        [[ -n "$default" ]] && printf "%s ? [%s] " "$prompt" "$default" >&2 \
                            || printf "%s ? " "$prompt" >&2
        read -r response
        [[ -z "$response" && -n "$default" ]] && response="$default"
    done
    printf "%s" "$response"
}

# Arrow-key selection menu. Sets global SELECTED_IDX.
# Usage: select_menu <array_name> [initial_idx]
SELECTED_IDX=0
SELECTED_INDICES=()

select_menu_multi() {
    local -n _smm_labels=$1
    local count=${#_smm_labels[@]}
    local cursor=0
    local -a checked=()
    local i
    for i in "${!_smm_labels[@]}"; do
        checked+=("false")
    done

    tput civis 2>/dev/null

    _smm_draw() {
        for i in "${!_smm_labels[@]}"; do
            local box="[ ]"
            [[ "${checked[$i]}" == "true" ]] && box="[x]"
            if [ "$i" -eq "$cursor" ]; then
                echo -e "  ${BLUE}▶ $box ${_smm_labels[$i]}${NC}"
            else
                echo "    $box ${_smm_labels[$i]}"
            fi
        done
    }

    _smm_draw

    while true; do
        local key
        IFS= read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
            case "$key" in
                '[A')
                    cursor=$(( cursor - 1 ))
                    if [ "$cursor" -lt 0 ]; then cursor=$(( count - 1 )); fi
                    ;;
                '[B')
                    cursor=$(( cursor + 1 ))
                    if [ "$cursor" -ge "$count" ]; then cursor=0; fi
                    ;;
            esac
        elif [[ "$key" == ' ' ]]; then
            if [[ "${checked[cursor]}" == "true" ]]; then
                checked[cursor]="false"
            else
                checked[cursor]="true"
            fi
        elif [[ "$key" == '' ]]; then
            break
        elif [[ "$key" == 'q' ]] || [[ "$key" == $'\x03' ]]; then
            tput cnorm 2>/dev/null
            echo ""
            exit 0
        fi
        tput cuu "$count" 2>/dev/null
        _smm_draw
    done

    tput cnorm 2>/dev/null

    SELECTED_INDICES=()
    for i in "${!checked[@]}"; do
        if [[ "${checked[$i]}" == "true" ]]; then
            SELECTED_INDICES+=("$i")
        fi
    done
}

select_menu() {
    local -n _sm_labels=$1
    local selected=${2:-0}
    local count=${#_sm_labels[@]}

    tput civis 2>/dev/null

    _sm_draw() {
        for i in "${!_sm_labels[@]}"; do
            if [ "$i" -eq "$selected" ]; then
                echo -e "  ${BLUE}▶ ${_sm_labels[$i]}${NC}"
            else
                echo "    ${_sm_labels[$i]}"
            fi
        done
    }

    _sm_draw

    while true; do
        local key
        IFS= read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
            case "$key" in
                '[A') (( selected-- )); [ "$selected" -lt 0 ] && selected=$(( count - 1 )) ;;
                '[B') (( selected++ )); [ "$selected" -ge "$count" ] && selected=0 ;;
            esac
        elif [[ "$key" == '' ]]; then   # Enter
            break
        elif [[ "$key" == 'q' ]] || [[ "$key" == $'\x03' ]]; then   # q or Ctrl+C
            tput cnorm 2>/dev/null
            echo ""
            exit 0
        fi
        tput cuu "$count" 2>/dev/null
        _sm_draw
    done

    tput cnorm 2>/dev/null
    SELECTED_IDX=$selected
}

# Prints a [Y/n] prompt and returns 0 if confirmed (Y/Enter), 1 if declined (n/N).
# Usage: prompt_confirm "Question text"
prompt_confirm() {
    local question="$1" answer
    printf "  %s [Y/n] " "$question"
    read -r answer
    answer="${answer:-Y}"
    [[ ! "$answer" =~ ^[nN] ]]
}

# Prompts the user to propagate changes via fleetman sync.
# Usage: prompt_sync_confirm [mode]
#   mode: "quick" (default) or "full"
prompt_sync_confirm() {
    local mode="${1:-quick}"
    printf "Propager via fleetman sync ? [Y/n] "
    local ans
    read -r ans
    ans="${ans:-Y}"
    if [[ ! "$ans" =~ ^[Nn] ]]; then
        if [[ "$mode" == "quick" ]]; then
            bash "$SCRIPTS_DIR/bin/fleetman" sync -q
        else
            bash "$SCRIPTS_DIR/bin/fleetman" sync
        fi
    fi
}

# Builds a display label array from server_list and server_envs globals.
# Format: "shortname [ENV]" with env portion colorized via env_color_ansi.
# Usage: build_server_list_labels <labels_array_name>
build_server_list_labels() {
    local -n _labels=$1
    local fqdn env color bg
    for fqdn in "${server_list[@]}"; do
        env="${server_envs[$fqdn]}"
        color=$(jq -r --arg e "$env" '.env_colors[$e] // "white"' "$CONFIG_FILE" 2>/dev/null)
        bg=$(env_color_ansi "$color" bg)
        _labels+=("$(printf "%s ${bg}[%s]${NC}" "$(short_name "$fqdn")" "${env^^}")")
    done
}

# Builds a display label array from the server_order and server_pods globals.
# Usage: build_server_labels <labels_array_name>
build_server_labels() {
    local -n _labels=$1
    local server pods_display
    for server in "${server_order[@]}"; do
        pods_display="${server_pods[$server]// /, }"
        _labels+=("$(short_name "$server")  ($pods_display)")
    done
}
