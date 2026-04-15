#!/bin/bash
# Removes the fleet management tooling from all servers in the fleet.
# Usage: bash ~/scripts/internal/uninstall.sh [-h]
#        bash ~/scripts/internal/uninstall.sh
#
# Options:
#   -h   Show this help

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"
# shellcheck source=scripts/lib/auth.sh
source "$_LIB/auth.sh"
# shellcheck source=scripts/lib/config.sh
source "$_LIB/config.sh"
# shellcheck source=scripts/lib/iterate.sh
source "$_LIB/iterate.sh"

help() {
    echo "Removes the fleet management tooling from all servers in the fleet."
    echo ""
    echo "Usage: bash ~/scripts/internal/uninstall.sh [-h]"
    echo ""
    echo "Options:"
    echo "  -h   Show this help"
    echo ""
    echo "What is removed from each server:"
    echo "  ~/scripts/              scripts directory (symlink on master, dir on remotes)"
    echo "  ~/.bash_aliases         user aliases file"
    echo "  ~/config.json           fleet configuration"
    echo "  ~/.data/                generated data (pods.json, ASCII art, logs)"
    echo "  ~/.ssh/fleet_key        fleet private RSA key"
    echo "  ~/.ssh/fleet_key.pub    fleet public RSA key"
    echo "  ~/.fleet_pass.enc       encrypted fleet password"
    echo "  .bashrc modifications   BEGIN/END FLEETMAN block + ~/.data/fleetman.sh"
    echo "  fleetman cron entries"
    echo ""
    echo "After confirming, you will be asked separately whether to remove"
    echo "the git clone directory (~/fleetman/ or \$FLEETMAN_DIR) — locally or on fleet servers."
}

# ---------------------------------------------------------------------------
# Triple confirmation
# ---------------------------------------------------------------------------

_confirm_uninstall() {
    local short_master answer

    section "UNINSTALL — Fleet management removal"
    echo ""
    echo -e "${RED}WARNING: This will permanently delete the fleet management tooling${NC}"
    echo -e "${RED}from ALL servers listed in config.json.${NC}"
    echo ""
    echo "The following will be removed from every server:"
    echo "  • ~/scripts/            (scripts directory or symlink)"
    echo "  • ~/.bash_aliases       (user aliases file)"
    echo "  • ~/config.json         (fleet configuration)"
    echo "  • ~/.data/              (generated data)"
    echo "  • ~/.ssh/fleet_key      (fleet private key)"
    echo "  • ~/.ssh/fleet_key.pub  (fleet public key)"
    echo "  • ~/.fleet_pass.enc     (encrypted password)"
    echo "  • .bashrc blocks        (BEGIN/END FLEETMAN block)"
    echo "  • selfupdate cron entry"
    echo ""

    short_master=$(short_name "$MASTER_HOST")
    printf "  Type the short hostname of this server (%s) to confirm: " "$short_master"
    read -r answer
    if [[ "$answer" != "$short_master" ]]; then
        err "Confirmation failed — aborting"
        exit 1
    fi

    printf "  Are you absolutely sure? This cannot be undone. [yes/NO] "
    read -r answer
    if [[ "${answer,,}" != "yes" ]]; then
        err "Confirmation failed — aborting"
        exit 1
    fi

    printf "  Type 'UNINSTALL' in uppercase to proceed: "
    read -r answer
    if [[ "$answer" != "UNINSTALL" ]]; then
        err "Confirmation failed — aborting"
        exit 1
    fi

    echo ""
    warn "Proceeding with uninstall..."
    echo ""
}

# ---------------------------------------------------------------------------
# Local uninstall (master)
# ---------------------------------------------------------------------------

uninstall_local() {
    # Clean .bashrc: remove BEGIN/END FLEETMAN block
    sed -i '/# BEGIN FLEETMAN/,/# END FLEETMAN/d' "$HOME/.bashrc" 2>/dev/null || true
    ok ".bashrc blocks removed"

    # Remove fleetman cron entries
    if crontab -l 2>/dev/null | grep -qF "bin/fleetman"; then
        crontab -l 2>/dev/null | grep -vF "bin/fleetman" | crontab -
        ok "fleetman cron entries removed"
    else
        ok "No fleetman cron entries found"
    fi

    # Remove fleet files
    rm -f ~/.fleet_pass.enc
    ok "$HOME/.fleet_pass.enc removed"
    rm -f ~/.ssh/fleet_key ~/.ssh/fleet_key.pub
    ok "$HOME/.ssh/fleet_key removed"
    rm -f ~/config.json
    ok "$HOME/config.json removed"
    rm -f ~/.bash_aliases
    ok "$HOME/.bash_aliases removed"
    rm -rf ~/.data
    ok "$HOME/.data/ removed"

    # ~/scripts — symlink on master, real dir on remotes
    if [ -L ~/scripts ]; then
        rm ~/scripts
        ok "$HOME/scripts symlink removed"
    elif [ -d ~/scripts ]; then
        rm -rf ~/scripts
        ok "$HOME/scripts/ removed"
    else
        ok "$HOME/scripts not found"
    fi

    ok "Uninstalled"
    echo ""
}

# ---------------------------------------------------------------------------
# Remote uninstall (fleet servers)
# ---------------------------------------------------------------------------

uninstall_remote() {
    local server=$1
    local result _ssh_rc

    result=$(ssh_cmd "$server" bash -s << ENDSSH 2>/dev/null
# Clean .bashrc: remove BEGIN/END FLEETMAN block
sed -i '/# BEGIN FLEETMAN/,/# END FLEETMAN/d' ~/.bashrc 2>/dev/null || true
echo "BASHRC_DONE"

# Remove fleetman cron entries
crontab -l 2>/dev/null | grep -vF "bin/fleetman" | crontab - 2>/dev/null
echo "CRON_DONE"

# Remove fleet files
rm -f ~/.fleet_pass.enc ~/.ssh/fleet_key ~/.ssh/fleet_key.pub \
      ~/config.json ~/.bash_aliases
echo "FILES_DONE"

rm -rf ~/.data
echo "DATA_DONE"

# ~/scripts is a real directory on remotes (sync copies it)
rm -rf ~/scripts
echo "SCRIPTS_DONE"
ENDSSH
    )
    _ssh_rc=$?

    if [[ "$_ssh_rc" -ne 0 ]] || ! echo "$result" | grep -q "^SCRIPTS_DONE$"; then
        err "Uninstall failed or incomplete"
        echo ""
        return 1
    fi

    ok "Uninstalled"
    echo ""
}

# ---------------------------------------------------------------------------
# Offer to remove git clone on master
# ---------------------------------------------------------------------------

_ask_remove_clone() {
    local pdir="${FLEETMAN_DIR:-$HOME/fleetman}"
    local clone_server=""   # vide = local, non-vide = FQDN distant

    echo ""

    if [ ! -d "$pdir/.git" ]; then
        local _server
        while IFS= read -r _server; do
            # if form required — bare [ ] && continue returns exit 1 under set -e
            if [ "$_server" = "$MASTER_HOST" ]; then continue; fi
            # $pdir intentionally expands locally: fleet convention is same path on all servers
            if ssh_cmd "$_server" "[ -d \"$pdir/.git\" ]" 2>/dev/null; then
                clone_server="$_server"
                break
            fi
        done < <(jq -r '.servers[] | .[]' "$CONFIG_FILE" 2>/dev/null)
    fi

    if [ -z "$clone_server" ] && [ ! -d "$pdir/.git" ]; then
        ok "Git clone not found locally or on fleet — skipping"
        return
    fi

    if [ -n "$clone_server" ]; then
        warn "Git clone found at: $clone_server:$pdir"
    else
        warn "Git clone found at: $pdir"
    fi
    printf "  Remove it? [y/N] "
    local answer
    read -r answer

    if [[ "${answer,,}" == "y" ]]; then
        if [ -n "$clone_server" ]; then
            ssh_cmd "$clone_server" "rm -rf \"$pdir\""
            ok "Removed $clone_server:$pdir"
        else
            rm -rf "$pdir"
            ok "Removed $pdir"
        fi
    else
        if [ -n "$clone_server" ]; then
            ok "Git clone kept at $clone_server:$pdir"
        else
            ok "Git clone kept at $pdir"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local _opt
    local OPTIND=1
    while getopts ":h" _opt "$@"; do
        case "$_opt" in
            h) help; exit 0 ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    check_sshpass
    check_config_file
    ask_password

    _confirm_uninstall
    _ask_remove_clone

    section "Uninstalling fleet management [ALL]"
    echo ""
    iterate_servers uninstall_local uninstall_remote
    print_summary

    unset PASSWORD
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
