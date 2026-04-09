#!/bin/bash

# Migration runner for fleetman upgrades.
# Finds and executes migration scripts in internal/migrations/ for versions
# strictly between old_ver (exclusive) and new_ver (inclusive).
# Each migration file is named vX.Y.Z.sh and run in ascending version order.
# Migration scripts may be interactive; they always run with a TTY when called
# from fleetman selfupdate (locally or via ssh -t for remote clones).
#
# Usage: bash run_migrations.sh <old_version> <new_version>
#   old_version  Version before the update  (e.g. "1.0.0" or "v1.0.0")
#   new_version  Version after the update   (e.g. "1.1.0" or "v1.1.0")

_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib"
# shellcheck source=scripts/lib/vars.sh
source "$_LIB/vars.sh"
# shellcheck source=scripts/lib/display.sh
source "$_LIB/display.sh"

_MIGRATIONS_DIR="$(dirname "${BASH_SOURCE[0]}")/migrations"

# Strict semver less-than: returns 0 if $1 < $2, 1 otherwise.
# Accepts versions with or without a leading 'v'.
# Usage: _ver_lt "1.0.0" "1.1.0"
_ver_lt() {
    local a="${1#v}" b="${2#v}"
    [ "$(printf '%s\n' "$a" "$b" | sort -V | head -1)" = "$a" ] && [ "$a" != "$b" ]
}

# Finds and runs migration scripts in the window ]old_ver, new_ver].
# Usage: run_migrations <old_ver> <new_ver>
main() {
    local old_ver="$1" new_ver="$2"
    local old="${old_ver#v}" new="${new_ver#v}"

    local -a pending=()
    local script name ver_clean
    while IFS= read -r script; do
        name="$(basename "$script")"
        ver_clean="${name%.sh}"    # "v1.1.0.sh" → "v1.1.0"
        ver_clean="${ver_clean#v}" # "v1.1.0"    → "1.1.0"
        if _ver_lt "$old" "$ver_clean" && ! _ver_lt "$new" "$ver_clean"; then
            pending+=("$script")
        fi
    done < <(find "$_MIGRATIONS_DIR" -name 'v[0-9]*.sh' 2>/dev/null | sort -V)

    section "Migrations ($old_ver → $new_ver)"
    echo ""

    if [[ "${#pending[@]}" -eq 0 ]]; then
        ok "No migration to apply"
        echo ""
        return 0
    fi

    ok "Actual version $old_ver"
    echo ""
    for script in "${pending[@]}"; do
        name="$(basename "$script")"
        local ver="${name%.sh}"
        echo -e "${CYAN}-- Migration to $ver --${NC}"
        echo ""
        bash "$script"
        echo ""
    done
    ok "All migrations done"
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: run_migrations.sh <old_version> <new_version>" >&2
        exit 1
    fi
    main "$1" "$2"
fi
