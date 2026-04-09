#!/bin/bash

##
# @menu Autosync (sync cron)
# @order 4
#
# Manage the daily autosync cron job (fleetman sync) on the git clone server.
#
# Usage: fleetman config autosync
#
# Options:
#   -h, --help   Show this help
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/ui.sh
source "$_LIB/ui.sh"

cmd_config_autosync() {
    local OPTIND=1
    while getopts ":" _opt "$@"; do
        case "$_opt" in
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_config_file

    section "Configuration — autosync"
    echo ""

    # ── Git clone detection ────────────────────────────────────────────────
    local _pdir="${FLEETMAN_DIR:-$HOME/fleetman}"
    local _git_server="" _is_local=0

    if [[ -d "$_pdir/.git" ]]; then
        _is_local=1
        _git_server="$MASTER_HOST"
    else
        if [[ ! -s "$GIT_SERVER_FILE" ]]; then
            err "Git clone server not cached — run 'fleetman sync' first from the server holding the git clone"
            exit 1   # PASSWORD not yet set — ask_password runs after this guard
        fi
        check_sshpass
        ask_password
        _git_server=$(< "$GIT_SERVER_FILE")
        # shellcheck disable=SC2016
        if ! ssh_cmd "$_git_server" '[[ -d "${FLEETMAN_DIR:-$HOME/fleetman}/.git" ]]' 2>/dev/null; then
            err "Cached server $(short_name "$_git_server") unreachable or git clone missing"
            echo "  Re-run 'fleetman sync' from the server holding the git clone"
            unset PASSWORD
            exit 1
        fi
    fi

    if [[ -z "$_git_server" ]]; then
        err "No git clone found in the fleet"
        if [[ "$_is_local" -eq 0 ]]; then unset PASSWORD; fi
        exit 1
    fi

    # ── Read cron state ─────────────────────────────────────────────────────
    local _is_active=0 _current_time=""

    if [[ "$_is_local" -eq 1 ]]; then
        local _cron_output _cron_line
        _cron_output=$(crontab -l 2>/dev/null || true)
        _cron_line=$(echo "$_cron_output" | grep "bin/fleetman sync" || true)
        if [[ -n "$_cron_line" ]]; then
            _is_active=1
            # printf "%02d:%02d" zero-pads single-digit hours/minutes (e.g. "0 1" → "01:00", "30 8" → "08:30")
            _current_time=$(echo "$_cron_line" | awk '{printf "%02d:%02d\n", $2, $1}')
            if ! [[ "$_current_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                _current_time="01:00"
            fi
        fi
    else
        local _phase_a_out
        _phase_a_out=$(ssh_cmd "$_git_server" bash -s << ENDSSH
_cron_output=\$(crontab -l 2>/dev/null || true)
_cron_line=\$(echo "\$_cron_output" | grep "bin/fleetman sync" || true)
if [[ -n "\$_cron_line" ]]; then
    _hhmm=\$(echo "\$_cron_line" | awk '{printf "%02d:%02d\n", \$2, \$1}')
    echo "CRON_ACTIVE:\$_hhmm"
else
    echo "CRON_INACTIVE"
fi
ENDSSH
)
        if [[ "$_phase_a_out" == CRON_ACTIVE:* ]]; then
            _is_active=1
            _current_time="${_phase_a_out#CRON_ACTIVE:}"
            if ! [[ "$_current_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                _current_time="01:00"
            fi
        fi
    fi

    # ── Display state ────────────────────────────────────────────────────────
    local _server_label
    _server_label=$(short_name "$_git_server")
    if [[ "$_is_active" -eq 1 ]]; then
        ok "Autosync active — every day at ${_current_time} on ${_server_label}"
    else
        warn "Autosync inactive"
    fi
    echo ""

    # ── Prompt activation / deactivation ────────────────────────────────────
    local _answer
    if [[ "$_is_active" -eq 0 ]]; then
        printf "  Enable? [Y/n] "
        read -r _answer
        _answer="${_answer:-Y}"
        if [[ "${_answer,,}" == "n" ]]; then
            ok "Unchanged"
            return 0
        fi
    else
        printf "  Disable? [N/y] "
        read -r _answer
        _answer="${_answer:-N}"
        if [[ "${_answer,,}" == "y" ]]; then
            if [[ "$_is_local" -eq 1 ]]; then
                (crontab -l 2>/dev/null || true) | grep -v "bin/fleetman sync" | crontab -
            else
                local _phase_b_out
                _phase_b_out=$(ssh_cmd "$_git_server" bash -s << ENDSSH
(crontab -l 2>/dev/null || true) | grep -v "bin/fleetman sync" | crontab -
echo "CRON_REMOVED"
ENDSSH
)
                [[ "$_phase_b_out" != *CRON_REMOVED* ]] && warn "Unexpected response from server"
            fi
            ok "Autosync disabled"
            if [[ "$_is_local" -eq 0 ]]; then unset PASSWORD; fi
            return 0
        fi
        # N → proceed to time input
    fi

    # ── Input time HH:MM ────────────────────────────────────────────────────
    local _default_time="${_current_time:-01:00}"
    local _new_time
    _new_time=$(prompt_response "Time (HH:MM)" "$_default_time")
    while ! [[ "$_new_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; do
        warn "Invalid format — expected HH:MM (e.g. 01:00, 23:30)"
        _new_time=$(prompt_response "Time (HH:MM)" "$_default_time")
    done

    if [[ "$_is_active" -eq 1 && "$_new_time" == "$_current_time" ]]; then
        ok "Unchanged"
        if [[ "$_is_local" -eq 0 ]]; then unset PASSWORD; fi
        return 0
    fi

    # ── Build and write cron ─────────────────────────────────────
    local _hh _mm
    _hh="${_new_time%%:*}"
    _mm="${_new_time##*:}"
    local _new_cron_line="${_mm} ${_hh} * * * mv ~/.data/autosync.log ~/.data/autosync.log.1 2>/dev/null; bash ~/scripts/bin/fleetman sync > ~/.data/autosync.log 2>&1"

    if [[ "$_is_local" -eq 1 ]]; then
        { (crontab -l 2>/dev/null || true) | grep -v "bin/fleetman sync"; echo "$_new_cron_line"; } | crontab -
    else
        local _phase_b_out
        _phase_b_out=$(ssh_cmd "$_git_server" bash -s << ENDSSH
_new_cron_line="$_new_cron_line"
{ (crontab -l 2>/dev/null || true) | grep -v "bin/fleetman sync"; echo "\$_new_cron_line"; } | crontab -
echo "CRON_UPDATED"
ENDSSH
)
        [[ "$_phase_b_out" != *CRON_UPDATED* ]] && warn "Unexpected response from server"
    fi

    ok "Autosync scheduled at $_new_time"
    if [[ "$_is_local" -eq 0 ]]; then unset PASSWORD; fi
}
