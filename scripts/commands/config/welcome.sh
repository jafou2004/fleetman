#!/bin/bash

##
# @menu Welcome screen
# @order 8
#
# Configures the welcome screen display interactively with a live preview.
#
# Usage: fleetman config welcome
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
# shellcheck source=scripts/internal/welcome.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../internal/welcome.sh"

_wc_cleanup() {
    tput cnorm 2>/dev/null
}

_wc_do_save() {
    local tmp
    tmp=$(mktemp)
    if ! jq --arg e "$_show_welcome" --arg p "$_show_pods" \
            --arg o "$_show_os"      --arg d "$_show_docker" \
            '.welcome = {enabled:($e=="true"), show_pods:($p=="true"),
                         show_os:($o=="true"), show_docker:($d=="true")}' \
            "$CONFIG_FILE" > "$tmp" || ! mv "$tmp" "$CONFIG_FILE"; then
        rm -f "$tmp"
        err "Failed to write config"
        return 1
    fi
    prompt_sync_confirm
}

# shellcheck disable=SC2015
_wc_handle_key() {
    local _key="$1"
    case "$_key" in
        a) [ "$_show_welcome" = "true" ] && _show_welcome="false" || _show_welcome="true" ;;
        p) [ "$_show_pods"    = "true" ] && _show_pods="false"    || _show_pods="true" ;;
        o) [ "$_show_os"      = "true" ] && _show_os="false"      || _show_os="true" ;;
        d) [ "$_show_docker"  = "true" ] && _show_docker="false"  || _show_docker="true" ;;
        RIGHT) _env_idx=$(( (_env_idx + 1) % ${#_envs[@]} )) ;;
        LEFT)  _env_idx=$(( (_env_idx - 1 + ${#_envs[@]}) % ${#_envs[@]} )) ;;
        x) _wc_do_save; return 2 ;;
        q) return 3 ;;
    esac
    return 0
}

_wc_render_preview() {
    local _fqdn="$1"
    local _host="${_fqdn%%.*}"
    ENV_NAME="${_envs[$_env_idx]}"
    ENV_COLOR_NAME=$(jq -r --arg e "$ENV_NAME" '.env_colors[$e] // "white"' "$CONFIG_FILE" 2>/dev/null)
    ENV_FG=$(env_color_ansi "$ENV_COLOR_NAME" fg)
    ENV_BG=$(env_color_ansi "$ENV_COLOR_NAME" bg)
    FQDN="$_fqdn"
    HOST="$_host"
    ASCII_LINES=()
    local _ascii_file="$DATA_DIR/welcome_${_host}.ascii"
    if [ -f "$_ascii_file" ]; then
        mapfile -t ASCII_LINES < "$_ascii_file"
    fi
    PODS=()
    if [ -f "$PODS_FILE" ]; then
        mapfile -t PODS < <(jq -r --arg e "$ENV_NAME" --arg h "$_fqdn" \
            '.[$e][$h][]? // empty' "$PODS_FILE" 2>/dev/null)
    fi
    container_rows=("$(printf "%b" "${BLUE}Docker${NC}  (preview mode)")")
    _SHOW_WELCOME="$_show_welcome"
    _SHOW_PODS="$_show_pods"
    _SHOW_OS="$_show_os"
    _SHOW_DOCKER="$_show_docker"
    collect_system_info
    tput clear 2>/dev/null
    if [ "$_show_welcome" = "true" ]; then
        render
    else
        printf "┌%s┐\n" "$(hline "$BOX_W")"
        box_full "$(printf "%b[ Welcome screen DISABLED ]%b" "$YELLOW" "$NC")"
        printf "└%s┘\n" "$(hline "$BOX_W")"
    fi
    printf "\n  ←/→ env   a enabled   p pods   o os   d docker   x save+quit   q quit\n"
}

cmd_config_welcome() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    # Load envs (alphabetical order)
    local -a _envs
    mapfile -t _envs < <(jq -r '.servers | keys[]' "$CONFIG_FILE")

    # Current state from config.json
    local _show_welcome _show_pods _show_os _show_docker _cfg
    _cfg=$(jq -r '[
        (if .welcome.enabled    == false then "false" else "true" end),
        (if .welcome.show_pods  == false then "false" else "true" end),
        (if .welcome.show_os    == false then "false" else "true" end),
        (if .welcome.show_docker == false then "false" else "true" end)
    ] | join(" ")' "$CONFIG_FILE" 2>/dev/null) || true
    read -r _show_welcome _show_pods _show_os _show_docker <<< "${_cfg:-true true true true}"

    local _env_idx=0
    local _rc=0
    tput civis 2>/dev/null
    # shellcheck disable=SC2064
    trap '_wc_cleanup; exit 0' INT TERM

    while true; do
        local _fqdn
        _fqdn=$(jq -r --arg e "${_envs[$_env_idx]}" '.servers[$e][0] // empty' "$CONFIG_FILE")
        _wc_render_preview "$_fqdn"

        local _key _seq
        IFS= read -rsn1 _key
        if [[ "$_key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 _seq
            case "$_seq" in
                '[C') _key="RIGHT" ;;
                '[D') _key="LEFT" ;;
                *)     _key="" ;;
            esac
        fi

        _wc_handle_key "$_key"
        _rc=$?
        if [ "$_rc" -eq 2 ] || [ "$_rc" -eq 3 ]; then break; fi
    done

    _wc_cleanup
    if [ "$_rc" -eq 2 ]; then ok "Welcome config saved"; fi
    exit 0
}
