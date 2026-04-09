#!/bin/bash

##
# @menu Diff .env vs .env-dist
# @order 2
#
# Compares .env-dist and .env for a pod, reports missing/extra variables, and offers to sync them.
# Template-managed variables (env_templates in config.json) are added with their computed value.
#
# Usage: fleetman pod env diff [-p <pod-search>] [-e <env>]
#
# Options:
#   -p <pod>       Pod search term — required unless run from a pod directory
#   -e <env>       Environment: dev, test, or prod (default: all)
#   -h, --help     Show this help
#
# Examples:
#   fleetman pod env diff -p my-service
#   fleetman pod env diff -p my-service -e prod
#   cd /opt/pod/my-service && fleetman pod env diff
##

_LIB="$(dirname "${BASH_SOURCE[0]}")/../../../lib"
source "$_LIB/vars.sh"
source "$_LIB/display.sh"
source "$_LIB/auth.sh"
source "$_LIB/config.sh"
source "$_LIB/ui.sh"
source "$_LIB/templates.sh"

# Script-level globals
TEMPLATES_JSON=""      # .pods[$pod].env_templates from config.json
TEMPLATE_VARS_JSON=""  # .template_vars from config.json
POD_DIR=""
POD_ENV_DIST=""
POD_ENV=""
SERVER=""              # FQDN of the server being diffed (set before calling run_diff)
_DIFF_WRITTEN=0        # set to 1 by run_diff when it actually writes to $env_file

# ── Private helpers ────────────────────────────────────────────────────────────

# Extracts variable names from an env file (skips comments and blank lines).
_diff_get_vars() {
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$1" | cut -d= -f1
}

# Extracts a variable's block from env_dist: blank/comment lines immediately
# above the variable line, plus the variable line itself.
_diff_get_block() {
    local varname="$1" env_dist="$2"
    local var_line block_start prev prev_line
    var_line=$(grep -n "^${varname}=" "$env_dist" | head -1 | cut -d: -f1)
    block_start=$var_line
    while [ "$block_start" -gt 1 ]; do
        prev=$(( block_start - 1 ))
        prev_line=$(sed -n "${prev}p" "$env_dist")
        if [[ "$prev_line" =~ ^# ]] || [[ -z "$prev_line" ]]; then
            block_start=$prev
        else
            break
        fi
    done
    sed -n "${block_start},${var_line}p" "$env_dist"
}

# Finds the nearest preceding variable in env_dist that already exists in env_file.
# Used as insertion anchor. Outputs the variable name, or nothing if not found.
_diff_find_anchor() {
    local varname="$1" env_dist="$2" env_file="$3"
    local var_line i line candidate
    var_line=$(grep -n "^${varname}=" "$env_dist" | head -1 | cut -d: -f1)
    for (( i = var_line - 1; i >= 1; i-- )); do
        line=$(sed -n "${i}p" "$env_dist")
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            candidate="${BASH_REMATCH[1]}"
            grep -qE "^${candidate}=" "$env_file" && echo "$candidate" && return
        fi
    done
}

# Inserts a block into env_file after the anchor variable line.
# If no anchor, prepends at the top.
_diff_insert_block() {
    local anchor="$1" block="$2" env_file="$3"
    local tmp inserted
    tmp=$(mktemp)
    if [ -z "$anchor" ]; then
        { printf '%s\n' "$block"; cat "$env_file"; } > "$tmp"
    else
        inserted=false
        while IFS= read -r line; do
            printf '%s\n' "$line" >> "$tmp"
            if ! $inserted && [[ "$line" =~ ^"${anchor}"= ]]; then
                printf '%s\n' "$block" >> "$tmp"
                inserted=true
            fi
        done < "$env_file"
    fi
    mv "$tmp" "$env_file"
}

# ── Core diff logic ────────────────────────────────────────────────────────────

# Compares env_dist against env_file, reports diffs, offers to sync.
# Template-aware: missing vars in TEMPLATES_JSON are added with their
# computed per-server value (requires SERVER global to be set).
# Sets _DIFF_WRITTEN=1 whenever it writes to env_file.
# Returns 0 if in sync, 1 if diffs were found (or .env was absent/created).
run_diff() {
    local env_dist="$1" env_file="$2"

    if [ ! -f "$env_dist" ]; then
        err "No .env-dist found — cannot compare"
        return 1
    fi

    # No .env: offer to create from .env-dist
    if [ ! -f "$env_file" ]; then
        warn "No .env found"
        if prompt_confirm "Create .env from .env-dist?"; then
            cp "$env_dist" "$env_file"
            _DIFF_WRITTEN=1
            ok ".env created from .env-dist"
        else
            echo "  Skipped"
        fi
        return 1
    fi

    # Extract variable names from both files
    local -a dist_vars env_vars
    mapfile -t dist_vars < <(_diff_get_vars "$env_dist")
    mapfile -t env_vars  < <(_diff_get_vars "$env_file")

    # Compute missing (in dist, not in env) and extra (in env, not in dist)
    local -a missing=() extra=()
    local v
    for v in "${dist_vars[@]}"; do
        grep -qE "^${v}=" "$env_file" || missing+=("$v")
    done
    for v in "${env_vars[@]}"; do
        grep -qE "^${v}=" "$env_dist" || extra+=("$v")
    done

    if [ "${#extra[@]}" -eq 0 ] && [ "${#missing[@]}" -eq 0 ]; then
        ok ".env is in sync with .env-dist"
        return 0
    fi

    # Report extra variables (red)
    if [ "${#extra[@]}" -gt 0 ]; then
        echo -e "${RED}  Extra in .env (not in .env-dist):${NC}"
        for v in "${extra[@]}"; do echo "    + $v"; done
        echo ""
    fi

    # Report missing variables (yellow), annotating template-managed ones
    if [ "${#missing[@]}" -gt 0 ]; then
        echo -e "${YELLOW}  Missing in .env (present in .env-dist):${NC}"
        local _annotation=""
        for v in "${missing[@]}"; do
            _annotation=""
            if [ -n "$TEMPLATES_JSON" ] && \
               jq -e --arg v "$v" 'has($v)' <<< "$TEMPLATES_JSON" > /dev/null 2>&1; then
                _annotation=" [template]"
            fi
            echo "    - ${v}${_annotation}"
        done
        echo ""
    fi

    # Offer to remove extra variables
    if [ "${#extra[@]}" -gt 0 ]; then
        if prompt_confirm "Remove ${#extra[@]} extra variable(s) from .env?"; then
            for v in "${extra[@]}"; do
                sed -i "/^${v}=/d" "$env_file"
                ok "Removed: $v"
            done
            _DIFF_WRITTEN=1
            echo ""
        fi
    fi

    # Offer to add missing variables
    if [ "${#missing[@]}" -gt 0 ]; then
        if prompt_confirm "Add ${#missing[@]} missing variable(s) to .env?"; then
            local block anchor _tmpl _short _env _val _esc
            # Process missing vars in .env-dist order so newly inserted variables
            # can serve as anchors for subsequent ones.
            for v in "${missing[@]}"; do
                # Template-aware: compute per-server value if available
                if [ -n "$TEMPLATES_JSON" ] && [ -n "$SERVER" ] && \
                   jq -e --arg v "$v" 'has($v)' <<< "$TEMPLATES_JSON" > /dev/null 2>&1; then
                    _tmpl=$(jq -r --arg v "$v" '.[$v]' <<< "$TEMPLATES_JSON")
                    _parse_server_parts "$SERVER"
                    _short=$(short_name "$SERVER")
                    _env=$(_get_env_for_server "$SERVER")
                    _val=$(_substitute "$_tmpl" "$SERVER" "$_short" "$_env" "$SELECTED_POD")
                    _esc=$(_escape_for_sed "$_val")
                    block=$(_diff_get_block "$v" "$env_dist" | sed "s|^${v}=.*|${v}=${_esc}|")
                else
                    block=$(_diff_get_block "$v" "$env_dist")
                fi
                anchor=$(_diff_find_anchor "$v" "$env_dist" "$env_file")
                _diff_insert_block "$anchor" "$block" "$env_file"
                ok "Added: $v"
            done
            _DIFF_WRITTEN=1
            echo ""
        fi
    fi

    return 1
}

# ── Mode A helpers ─────────────────────────────────────────────────────────────

# Runs diff locally in $POD_DIR.
# Returns run_diff's exit code (0 = in sync, 1 = diffs or missing dir).
diff_local() {
    if [ ! -d "$POD_DIR" ]; then
        err "Pod directory not found: $POD_DIR"
        return 1
    fi
    # shellcheck disable=SC2164
    pushd "$POD_DIR" > /dev/null 2>&1
    run_diff "$POD_ENV_DIST" "$POD_ENV"
    local rc=$?
    # shellcheck disable=SC2164
    popd > /dev/null 2>&1
    return $rc
}

# Runs diff remotely: fetches .env-dist and .env via SCP, diffs locally,
# pushes back .env if _DIFF_WRITTEN=1.
# Returns 0 if in sync, 1 if diffs found or fetch failed.
diff_remote() {
    local tmp_dist tmp_env
    tmp_dist=$(mktemp)
    tmp_env=$(mktemp)
    # rm -f intentional: we need a non-existing path so that scp failure
    # (absent remote .env) leaves tmp_env absent, while run_diff step 2
    # (create from .env-dist) correctly creates the file at that path.
    rm -f "$tmp_env"

    if ! scp_cmd "$SERVER:$POD_ENV_DIST" "$tmp_dist" > /dev/null 2>&1; then
        err "Cannot fetch .env-dist from $(short_name "$SERVER"):$POD_ENV_DIST"
        rm -f "$tmp_dist"
        return 1
    fi

    scp_cmd "$SERVER:$POD_ENV" "$tmp_env" > /dev/null 2>&1 || true

    _DIFF_WRITTEN=0
    run_diff "$tmp_dist" "$tmp_env"
    local rc=$?

    # Only push back if run_diff actually wrote to tmp_env
    if [ "$_DIFF_WRITTEN" -eq 1 ] && [ -f "$tmp_env" ]; then
        if scp_cmd "$tmp_env" "$SERVER:$POD_ENV" > /dev/null 2>&1; then
            ok ".env pushed back to $(short_name "$SERVER")"
        else
            err "Failed to push .env back to $(short_name "$SERVER")"
        fi
    fi

    rm -f "$tmp_dist" "$tmp_env"
    return $rc
}

# ── Main ───────────────────────────────────────────────────────────────────────

cmd_pod_env_diff() {
    parse_search_env_opts "$@" || true
    shift $((OPTIND - 1))

    # ── Mode A: -p given → diff on a server hosting the pod ──────────────────

    if [ -n "$SEARCH" ]; then
        check_sshpass
        check_config_file
        find_and_select_pod "$SEARCH" "$ENV_FILTER" "pod env diff: \"$SEARCH\""
        parse_env "$ENV_FILTER"
        collect_pod_servers

        load_pod_templates "$SELECTED_POD"

        ask_password

        # Server selection — show menu if multiple servers hosting the pod
        local -a srv_labels=()
        local s
        if [ "${#pod_servers[@]}" -gt 1 ]; then
            for s in "${pod_servers[@]}"; do srv_labels+=("$(short_name "$s")"); done
            section "pod env diff: \"$SEARCH\" [$label]"
            echo ""
            select_menu srv_labels
            echo ""
            SERVER="${pod_servers[$SELECTED_IDX]}"
        else
            SERVER="${pod_servers[0]}"
        fi

        POD_DIR="$PODS_DIR/$SELECTED_POD"
        POD_ENV_DIST="$POD_DIR/.env-dist"
        POD_ENV="$POD_DIR/.env"

        section "pod env diff: $(short_name "$SERVER") → $SELECTED_POD"
        echo ""

        _DIFF_WRITTEN=0
        if is_local_server "$SERVER"; then
            diff_local
        else
            diff_remote
        fi
        local diff_rc=$?

        if [ "$diff_rc" -ne 0 ]; then
            echo ""
            if is_local_server "$SERVER"; then
                if prompt_confirm "Go to $POD_DIR?"; then
                    cd "$POD_DIR" && SHLVL=2 exec bash
                fi
            else
                if prompt_confirm "SSH to $(short_name "$SERVER")?"; then
                    ssh_cmd -t "$SERVER" "cd $POD_DIR && SHLVL=2 exec bash"
                fi
            fi
        fi

    # ── Mode B: no -p, current dir is a pod directory ────────────────────────

    elif [ -f ".env-dist" ] || [ -f ".env" ]; then
        section "pod env diff: $(basename "$(pwd)")"
        echo ""
        run_diff ".env-dist" ".env"

    # ── Mode C: neither ───────────────────────────────────────────────────────

    else
        err "No pod specified (-p) and current directory is not a pod directory."
        echo "  Run from a pod directory, or use -p <pod-search>."
        echo "  Use -h for help."
        exit 1
    fi
    unset PASSWORD
}
