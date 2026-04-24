#!/bin/bash

# Uninstall helpers — remove fleet tooling from local and remote servers.
[[ -n "${_FLEETMAN_UNINSTALL_LOADED:-}" ]] && return 0
_FLEETMAN_UNINSTALL_LOADED=1

# shellcheck source=scripts/lib/display.sh
source "$(dirname "${BASH_SOURCE[0]}")/display.sh"

uninstall_remote() {
    local server="$1"
    local result _ssh_rc
    result=$(ssh_cmd "$server" bash -s << 'ENDSSH' 2>/dev/null
sed -i '/# BEGIN FLEETMAN/,/# END FLEETMAN/d' ~/.bashrc 2>/dev/null || true
echo "BASHRC_DONE"
crontab -l 2>/dev/null | grep -vF "bin/fleetman" | crontab - 2>/dev/null
echo "CRON_DONE"
rm -f ~/.fleet_pass.enc ~/.ssh/fleet_key ~/.ssh/fleet_key.pub ~/config.json ~/.bash_aliases
echo "FILES_DONE"
rm -rf ~/.data
echo "DATA_DONE"
rm -rf ~/scripts
echo "SCRIPTS_DONE"
ENDSSH
    )
    _ssh_rc=$?
    if [[ "$_ssh_rc" -ne 0 ]] || ! echo "$result" | grep -q "^SCRIPTS_DONE$"; then
        err "Uninstall failed on $server"
        return 1
    fi
    ok "Fleetman uninstalled from $server"
}

uninstall_local() {
    sed -i '/# BEGIN FLEETMAN/,/# END FLEETMAN/d' "$HOME/.bashrc" 2>/dev/null || true
    ok ".bashrc blocks removed"
    if crontab -l 2>/dev/null | grep -qF "bin/fleetman"; then
        crontab -l 2>/dev/null | grep -vF "bin/fleetman" | crontab - 2>/dev/null || true
        ok "fleetman cron entries removed"
    fi
    rm -f ~/.fleet_pass.enc ~/.ssh/fleet_key ~/.ssh/fleet_key.pub ~/config.json ~/.bash_aliases
    rm -rf ~/.data
    if [ -L ~/scripts ]; then
        rm ~/scripts
    elif [ -d ~/scripts ]; then
        rm -rf ~/scripts
    fi
    ok "Fleetman uninstalled from local server"
}
