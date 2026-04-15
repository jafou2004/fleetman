#!/bin/bash

##
# Synchronizes configuration across the fleet.
#   Phase 1a:  generates ASCII art files
#   Phase 1b:  collects pod directories into pods.json
#   Phase 1c: (--full only) collects Docker services per pod into services.json
#   Phase 2:  replicates scripts/, ~/.bash_aliases, config.json, and .data/ to all servers
#
# Usage: fleetman sync [-q] [-f] [-h]
#
# Options:
#   -q, --quick  Skip Phase 1 — use after config-only changes
#   -f, --full   Also run Phase 1c: collect Docker services per pod into services.json
#   -h, --help   Show this help
#
# Examples:
#   fleetman sync
#   fleetman sync -q
#   fleetman sync -f
##

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
# shellcheck source=scripts/lib/bashrc.sh
source "$_LIB/bashrc.sh"

QUICK_MODE=false
FULL_MODE=false

parse_args() {
    local _filtered=()
    for _a in "$@"; do
        case "$_a" in
            --quick) QUICK_MODE=true ;;
            --full)  FULL_MODE=true ;;
            *) _filtered+=("$_a") ;;
        esac
    done
    set -- "${_filtered[@]}"

    while getopts ":qf" _opt "$@"; do
        case "$_opt" in
            q) QUICK_MODE=true ;;
            f) FULL_MODE=true ;;
            \?) err "Unknown option: -$OPTARG"; exit 1 ;;
        esac
    done

    if [ "$QUICK_MODE" = "true" ] && [ "$FULL_MODE" = "true" ]; then
        err "Options -q et -f sont incompatibles"; exit 1
    fi
}

ensure_user_aliases() {
    if [ ! -f "$USER_ALIASES_FILE" ]; then
        cat > "$USER_ALIASES_FILE" << 'EOF'
# Personal aliases — add your own below.
# Sourced after PATH setup: use standard alias format.
# alias myalias='command' # Description

# ### USER
EOF
        warn "Created empty $USER_ALIASES_FILE — add your personal aliases there"
    fi
}

# ── Phase 1a: braille ASCII art ────────────────────────────────────────────────

_init_braille_font() {
    # ── Braille font (smbraille / TOIlet) — 2 lines per character ─────────────
    declare -gA F1 F2

    # Uppercase A–Z
    F1[A]='⣎⣱'; F2[A]='⠇⠸'
    F1[B]='⣏⡱'; F2[B]='⠧⠜'
    F1[C]='⡎⠑'; F2[C]='⠣⠔'
    F1[D]='⡏⢱'; F2[D]='⠧⠜'
    F1[E]='⣏⡉'; F2[E]='⠧⠤'
    F1[F]='⣏⡉'; F2[F]='⠇ '
    F1[G]='⡎⠑ '; F2[G]='⠣⠝'
    F1[H]='⣇⣸'; F2[H]='⠇⠸'
    F1[I]='⡇';   F2[I]='⠇'
    F1[J]='⠈⢹'; F2[J]='⠣⠜'
    F1[K]='⣇⠜'; F2[K]='⠇⠱'
    F1[L]='⡇ ';  F2[L]='⠧⠤'
    F1[M]='⡷⢾'; F2[M]='⠇⠸'
    F1[N]='⡷⣸'; F2[N]='⠇⠹'
    F1[O]='⡎⢱'; F2[O]='⠣⠜'
    F1[P]='⣏⡱'; F2[P]='⠇ '
    F1[Q]='⡎⢱'; F2[Q]='⠣⠪'
    F1[R]='⣏⡱'; F2[R]='⠇⠱'
    F1[S]='⢎⡑'; F2[S]='⠢⠜'
    F1[T]='⢹⠁'; F2[T]='⠸ '
    F1[U]='⡇⢸'; F2[U]='⠣⠜'
    F1[V]='⡇⢸'; F2[V]='⠡⠌'
    F1[W]='⡇⢸'; F2[W]='⠟⠻'
    F1[X]='⢇⡸'; F2[X]='⠇⠸'
    F1[Y]='⢇⡸'; F2[Y]=' ⠇'
    F1[Z]='⢉⠝'; F2[Z]='⠮⠤'

    # Lowercase a–z
    F1[a]='⢀⣀'; F2[a]='⠣⠼'
    F1[b]='⣇⡀'; F2[b]='⠧⠜'
    F1[c]='⢀⣀'; F2[c]='⠣⠤'
    F1[d]='⢀⣸'; F2[d]='⠣⠼'
    F1[e]='⢀⡀'; F2[e]='⠣⠭'
    F1[f]='⣰⡁'; F2[f]='⢸ '
    F1[g]='⢀⡀'; F2[g]='⣑⡺'
    F1[h]='⣇⡀'; F2[h]='⠇⠸'
    F1[i]='⠄';   F2[i]='⠇'
    F1[j]='⠠';   F2[j]='⡸'
    F1[k]='⡇⡠'; F2[k]='⠏⠢'
    F1[l]='⡇';   F2[l]='⠣'
    F1[m]='⣀⣀ '; F2[m]='⠇⠇⠇'
    F1[n]='⣀⡀'; F2[n]='⠇⠸'
    F1[o]='⢀⡀'; F2[o]='⠣⠜'
    F1[p]='⣀⡀'; F2[p]='⡧⠜'
    F1[q]='⢀⣀'; F2[q]='⠣⢼'
    F1[r]='⡀⣀'; F2[r]='⠏ '
    F1[s]='⢀⣀'; F2[s]='⠭⠕'
    F1[t]='⣰⡀'; F2[t]='⠘⠤'
    F1[u]='⡀⢀'; F2[u]='⠣⠼'
    F1[v]='⡀⢀'; F2[v]='⠑⠊'
    F1[w]='⡀⢀'; F2[w]='⠟⠻'
    F1[x]='⡀⢀'; F2[x]='⠜⠣'
    F1[y]='⡀⢀'; F2[y]='⣑⡺'
    F1[z]='⣀⣀'; F2[z]='⠴⠥'

    # Digits 0–9
    F1[0]='⣎⣵'; F2[0]='⠫⠜'
    F1[1]='⢺ ';  F2[1]='⠼⠄'
    F1[2]='⠊⡱'; F2[2]='⠮⠤'
    F1[3]='⢉⡹'; F2[3]='⠤⠜'
    F1[4]='⣇⣸'; F2[4]=' ⠸'
    F1[5]='⣏⡉'; F2[5]='⠤⠜'
    F1[6]='⣎⡁'; F2[6]='⠣⠜'
    F1[7]='⠉⡹'; F2[7]='⠸ '
    F1[8]='⢎⡱'; F2[8]='⠣⠜'
    F1[9]='⢎⣱'; F2[9]='⠠⠜'
}

_render_braille() {
    local text="$1" line1="" line2="" i ch
    for (( i=0; i<${#text}; i++ )); do
        ch="${text:$i:1}"
        [[ $i -gt 0 ]] && { line1+=' '; line2+=' '; }
        if [[ -n "${F1[$ch]+x}" ]]; then
            line1+="${F1[$ch]}"
            line2+="${F2[$ch]}"
        else
            line1+='⣀'
            line2+='⠿'
        fi
    done
    printf '%s\n%s\n' "$line1" "$line2"
}

generate_ascii_files() {
    _init_braille_font

    local count=0
    while IFS= read -r server; do
        local short base num name_l1 name_l2 num_l1 num_l2

        short=$(short_name "$server")
        base=$(echo "$short" | sed 's/[0-9].*//' | tr '[:lower:]' '[:upper:]')
        num=$(echo "$short" | grep -o '[0-9]\+' | head -1)

        { read -r name_l1; read -r name_l2; } < <(_render_braille "$base")

        if [[ -n "$num" ]]; then
            { read -r num_l1; read -r num_l2; } < <(_render_braille "$num")
            printf '%s  %s\n%s  %s\n' "$name_l1" "$num_l1" "$name_l2" "$num_l2"
        else
            printf '%s\n%s\n' "$name_l1" "$name_l2"
        fi > "$DATA_DIR/welcome_${short}.ascii"

        (( count++ ))
    done < <(jq -r '.servers[] | .[]' "$CONFIG_FILE")

    ok "Braille ASCII art generated for $count server(s) → $DATA_DIR/welcome_*.ascii"
}

# ── Shared: iterate over environments ─────────────────────────────────────────

# Calls $1 "$env" for each environment: only $ENV if set, all envs from config otherwise.
# Prints a colored section header and a blank line between envs when iterating all.
for_each_env() {
    local fn=$1
    if [ -n "$ENV" ]; then
        $fn "$ENV"
    else
        while IFS= read -r env <&4; do
            echo -e "${BLUE}── ${env^^} ──────────────────────────────────────────────────${NC}"
            $fn "$env"
            echo ""
        done 4< <(jq -r '.servers | keys[]' "$CONFIG_FILE")
    fi
}

# ── Phase 1b: pod collection ───────────────────────────────────────────────────

_PODS_TMP=""

_collect_pods_server() {
    local server=$1
    local pods_raw pods count ignore_patterns

    if [ "$server" = "$MASTER_HOST" ]; then
        pods_raw=$(find "$PODS_DIR" -maxdepth 1 -mindepth 1 -type d \
            -exec basename {} \; 2>/dev/null)
    else
        if ! pods_raw=$(ssh_cmd "$server" \
            "find \"$PODS_DIR\" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null"); then
            err "SSH connection failed"
            return 1
        fi
    fi

    ignore_patterns=$(jq -c '.pods_ignore // []' "$CONFIG_FILE")
    if [ -z "$pods_raw" ]; then
        pods="[]"
    else
        pods=$(echo "$pods_raw" | jq -R . | jq -s --argjson ignore "$ignore_patterns" \
            '[.[] | select(. as $p | $ignore | map(. as $re | $p | test($re)) | any | not)]')
    fi
    count=$(echo "$pods" | jq 'length')

    echo "$pods" > "$_PODS_TMP/${server}.json"

    if [ "$count" -eq 0 ]; then
        warn "no pods in $PODS_DIR"
    else
        ok "$count pod(s) — $(echo "$pods" | jq -r 'join(", ")')"
    fi
}

collect_pods_local()  { _collect_pods_server "$MASTER_HOST"; }
collect_pods_remote() { _collect_pods_server "$1"; }

collect_env() {
    local env=$1
    local -a env_servers
    mapfile -t env_servers < <(jq -r --arg e "$env" '.servers[$e] | .[]' "$CONFIG_FILE")

    _PODS_TMP=$(mktemp -d)
    iterate_servers collect_pods_local collect_pods_remote env_servers
    print_summary

    # Merge — starts from existing data, only overwrites servers that succeeded
    local env_data
    env_data=$(echo "$PODS_DATA" | jq -c --arg e "$env" '.[$e] // {}')
    local server pods
    for server in "${env_servers[@]}"; do
        if [ -f "$_PODS_TMP/${server}.json" ]; then
            pods=$(cat "$_PODS_TMP/${server}.json")
            env_data=$(echo "$env_data" | jq --arg s "$server" \
                --argjson p "$pods" '. + {($s): $p}')
        fi
    done

    rm -rf "$_PODS_TMP"
    PODS_DATA=$(echo "$PODS_DATA" | jq --arg e "$env" \
        --argjson d "$env_data" '. + {($e): $d}')
}

check_all_servers_flag() {
    local updates=()
    declare -A _updates_seen

    local envs_to_check=()
    if [ -n "$ENV" ]; then
        envs_to_check=("$ENV")
    else
        mapfile -t envs_to_check < <(jq -r '.servers | keys[]' "$CONFIG_FILE")
    fi

    for env in "${envs_to_check[@]}"; do
        local server_count
        server_count=$(jq -r --arg e "$env" '.servers[$e] | length' "$CONFIG_FILE")
        [ "$server_count" -eq 0 ] && continue

        local pods_in_env=()
        mapfile -t pods_in_env < <(echo "$PODS_DATA" | jq -r --arg e "$env" \
            '.[$e] // {} | to_entries[] | .value[]' | sort -u)

        for pod in "${pods_in_env[@]}"; do
            local pod_count
            pod_count=$(echo "$PODS_DATA" | jq -r --arg e "$env" --arg p "$pod" \
                '.[$e] // {} | to_entries[] | select(.value[] == $p) | .key' | wc -l)

            if [ "$pod_count" -eq "$server_count" ]; then
                local current_flag
                current_flag=$(jq -r --arg p "$pod" '.pods[$p].all_servers // false' "$CONFIG_FILE")
                if [ "$current_flag" != "true" ] && [[ ! -v _updates_seen[$pod] ]]; then
                    _updates_seen[$pod]=1
                    updates+=("$pod")
                fi
            fi
        done
    done

    [ ${#updates[@]} -eq 0 ] && return

    echo ""
    warn "Pod(s) deployed on all servers in at least one environment but not flagged in config.json:"
    for pod in "${updates[@]}"; do
        echo "    • $pod"
    done
    local answer
    read -rp "  Set \"all_servers\": true for these pods in config.json? [Y/n] " answer
    answer="${answer:-Y}"
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        for pod in "${updates[@]}"; do
            local updated
            updated=$(jq --arg p "$pod" '
                if .pods[$p] then .pods[$p].all_servers = true
                else .pods[$p] = {"all_servers": true}
                end
            ' "$CONFIG_FILE")
            echo "$updated" > "$CONFIG_FILE"
            ok "config.json: $pod → \"all_servers\": true"
        done
    else
        ok "config.json left unchanged"
    fi
}

load_pods_data() {
    mkdir -p "$DATA_DIR"
    if [ -f "$PODS_FILE" ]; then
        PODS_DATA=$(cat "$PODS_FILE")
    else
        PODS_DATA="{}"
    fi
}

# shellcheck disable=SC2034  # ENV used by collect_env
collect_all_pods() {
    for_each_env collect_env
    echo "$PODS_DATA" | jq '.' > "$PODS_FILE"
    ok "Collection complete → $PODS_FILE"

    if [[ -t 0 ]]; then
        check_all_servers_flag
    fi

    date '+%Y-%m-%d %H:%M' > "$DATA_DIR/last_sync.txt"
}

# ── Phase 1c: Docker services collection ──────────────────────────────────────

collect_services_local() {
    local pods_json=$1
    local result="{}"
    local pod pod_dir raw services

    while IFS= read -r pod; do
        pod_dir="$PODS_DIR/$pod"
        if [ ! -d "$pod_dir" ]; then continue; fi
        if [ ! -f "$pod_dir/docker-compose.yml" ] && [ ! -f "$pod_dir/compose.yml" ]; then continue; fi
        raw=$(cd "$pod_dir" && sudo_run docker compose ps --format json 2>/dev/null || echo "")
        services=$(printf '%s\n' "$raw" | jq -sc \
            'if length == 1 and (.[0] | type == "array") then .[0] else . end' \
            2>/dev/null || echo "[]")
        result=$(printf '%s' "$result" | jq --arg p "$pod" --argjson s "$services" '. + {($p): $s}')
    done < <(printf '%s' "$pods_json" | jq -r '.[]')

    printf '%s' "$result"
}

collect_services_remote() {
    local server=$1 pods_json=$2
    local pods_b64
    pods_b64=$(printf '%s' "$pods_json" | base64 | tr -d '\n')

    ssh_cmd "$server" bash << ENDSSH
pods_json=\$(printf '%s' '${pods_b64}' | base64 -d)
pods_dir='${PODS_DIR}'
result="{}"
while IFS= read -r pod; do
    pod_dir="\$pods_dir/\$pod"
    if [ ! -d "\$pod_dir" ]; then continue; fi
    if [ ! -f "\$pod_dir/docker-compose.yml" ] && [ ! -f "\$pod_dir/compose.yml" ]; then continue; fi
    raw=\$(cd "\$pod_dir" && echo "$B64_PASS" | base64 -d | sudo -S docker compose ps --format json 2>/dev/null || echo "")
    services=\$(printf '%s\n' "\$raw" | jq -sc \
        'if length == 1 and (.[0] | type == "array") then .[0] else . end' 2>/dev/null || echo "[]")
    result=\$(printf '%s' "\$result" | jq --arg p "\$pod" --argjson s "\$services" '. + {(\$p): \$s}')
done < <(printf '%s' "\$pods_json" | jq -r '.[]')
printf '%s' "\$result"
ENDSSH
}

_SERVICES_TMP=""
_COLLECT_ENV=""

_services_collect_job() {
    local server=$1
    local pods_json server_services count

    pods_json=$(printf '%s' "$PODS_DATA" | jq -c \
        --arg e "$_COLLECT_ENV" --arg s "$server" '.[$e][$s] // []')

    if [ "$server" = "$MASTER_HOST" ]; then
        server_services=$(collect_services_local "$pods_json")
    else
        if ! server_services=$(collect_services_remote "$server" "$pods_json"); then
            err "SSH connection failed"
            return 1
        fi
    fi

    count=$(printf '%s' "$server_services" | \
        jq '[to_entries[].value | length] | add // 0' 2>/dev/null || echo "0")

    echo "$server_services" > "$_SERVICES_TMP/${server}.json"
    ok "$count service(s)"
}

_services_local_job()  { _services_collect_job "$MASTER_HOST"; }
_services_remote_job() { _services_collect_job "$1"; }

collect_services_env() {
    local env=$1
    local -a env_servers
    mapfile -t env_servers < <(jq -r --arg e "$env" '.servers[$e] | .[]' "$CONFIG_FILE")

    _COLLECT_ENV="$env"
    _SERVICES_TMP=$(mktemp -d)
    iterate_servers _services_local_job _services_remote_job env_servers
    print_summary

    local env_sdata
    env_sdata=$(printf '%s' "$SERVICES_DATA" | jq -c --arg e "$env" '.[$e] // {}')
    local server server_services
    for server in "${env_servers[@]}"; do
        if [ -f "$_SERVICES_TMP/${server}.json" ]; then
            server_services=$(cat "$_SERVICES_TMP/${server}.json")
            env_sdata=$(printf '%s\n%s' "$env_sdata" "$server_services" | \
                jq -sc --arg s "$server" '.[0] + {($s): .[1]}')
        fi
    done

    rm -rf "$_SERVICES_TMP"
    SERVICES_DATA=$(printf '%s\n%s' "$SERVICES_DATA" "$env_sdata" | \
        jq -sc --arg e "$env" '.[0] + {($e): .[1]}')
}

collect_all_services() {
    SERVICES_DATA="{}"
    for_each_env collect_services_env
    printf '%s' "$SERVICES_DATA" | jq '.' > "$SERVICES_FILE"
    ok "Collection complete → $SERVICES_FILE"
}

# ── Phase 2: file synchronisation ─────────────────────────────────────────────

sync_local() {
    # If subfolder install, verify/recreate the symlink ~/scripts
    local _pdir="${FLEETMAN_DIR:-$HOME/fleetman}"
    if [[ -d "$_pdir/.git" && ! -L "$HOME/scripts" && ! -d "$HOME/scripts" ]]; then
        ln -s "$_pdir/scripts" "$HOME/scripts"
        ok "symlink ~/scripts recreated → $_pdir/scripts"
    fi

    hostname -f > "$FQDN_FILE"
    ok "FQDN cached → $FQDN_FILE"

    if [[ -d "$_pdir/.git" ]]; then
        hostname -f > "$GIT_SERVER_FILE"
        ok "Git clone server cached → $GIT_SERVER_FILE"
    fi

    if write_fleetman_bashrc_block; then
        ok ".bashrc Fleetman block added"
    fi
    generate_fleetman_sh
    ok "fleetman.sh generated in ~/.data"
    ok "Synchronised"
    echo ""
}

sync_remote() {
    local server=$1

    local _rsync_err
    if ! _rsync_err=$(rsync_cmd -a --delete "$SCRIPTS_DIR/" "$server:~/scripts/" 2>&1); then
        err "Failed to sync scripts/${_rsync_err:+ — $_rsync_err}"; echo ""; return 1
    fi
    ok "scripts/ synced"

    if ! _rsync_err=$(rsync_cmd -a "$USER_ALIASES_FILE" "$CONFIG_FILE" "$server:~/" 2>&1); then
        err "Failed to sync config files${_rsync_err:+ — $_rsync_err}"; echo ""; return 1
    fi
    ok "config files synced"

    if ! _rsync_err=$(rsync_cmd -a --exclude=fqdn "$DATA_DIR/" "$server:~/.data/" 2>&1); then
        err "Failed to sync .data/${_rsync_err:+ — $_rsync_err}"; echo ""; return 1
    fi
    ok ".data/ synced"

    ssh_cmd "$server" "hostname -f > ~/.data/fqdn" > /dev/null 2>&1
    ok "FQDN cached"

    if [ -f "$FLEET_KEY" ] && [ -f "$FLEET_PASS_FILE" ]; then
        ssh_cmd "$server" "mkdir -p ~/.ssh && chmod 700 ~/.ssh" > /dev/null 2>&1
        scp_cmd "$FLEET_KEY" "$server:~/.ssh/fleet_key" > /dev/null 2>&1 \
            && ssh_cmd "$server" "chmod 600 ~/.ssh/fleet_key" > /dev/null 2>&1
        if [ -f "${FLEET_KEY}.pub" ]; then
            scp_cmd "${FLEET_KEY}.pub" "$server:~/.ssh/fleet_key.pub" > /dev/null 2>&1
        fi
        scp_cmd "$FLEET_PASS_FILE" "$server:~/.fleet_pass.enc" > /dev/null 2>&1
        ok "fleet key + encrypted password deployed"
    fi

    local result
    result=$(ssh_cmd "$server" 'bash -s' << 'ENDSSH'
if ! grep -qF '# BEGIN FLEETMAN' ~/.bashrc 2>/dev/null; then
    {
        echo ""
        echo "# BEGIN FLEETMAN"
        echo '[[ -f ~/.data/fleetman.sh ]] && . ~/.data/fleetman.sh'
        echo "# END FLEETMAN"
    } >> ~/.bashrc
    echo "F_ADDED"
fi
ENDSSH
)
    if echo "$result" | grep -q "^F_ADDED$"; then
        ok ".bashrc Fleetman block added"
    fi
    ok "Synchronised"
    echo ""
}

# ── Entry point ────────────────────────────────────────────────────────────────

cmd_sync() {
    parse_args "$@"

    check_sshpass
    require_cmd rsync
    check_config_file
    ask_password

    ensure_user_aliases
    load_pods_data

    if [ "$QUICK_MODE" != "true" ]; then
        section "Phase 1a: welcome ASCII generation"
        echo ""
        generate_ascii_files
        echo ""

        section "Phase 1b: pod collection [$(env_label)]"
        echo ""
        collect_all_pods
        echo ""

        if [ "$FULL_MODE" = "true" ]; then
            section "Phase 1c: Docker services collection [$(env_label)]"
            echo ""
            collect_all_services
            echo ""
        fi
    fi

    section "Phase 2: synchronisation [$(env_label)]"
    echo ""
    iterate_servers sync_local sync_remote
    print_summary

    echo ""
    echo "To apply the changes, run 'source ~/.bashrc' on each server"

    unset PASSWORD
}
