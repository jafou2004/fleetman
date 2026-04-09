#!/bin/bash

# Template substitution engine for per-server .env variable rendering.
# Shared by pod/env/cp.sh and pod/update.sh.
[[ -n "${_FLEETMAN_TEMPLATES_LOADED:-}" ]] && return 0
_FLEETMAN_TEMPLATES_LOADED=1
#
# Callers must set TEMPLATES_JSON (env_templates object) and TEMPLATE_VARS_JSON
# (template_vars object) before calling _build_sed_cmds or _apply_templates.
# SELECTED_POD must also be set.

_LIB="$(dirname "${BASH_SOURCE[0]}")"
source "$_LIB/display.sh"

# Script-level globals for template engine (uppercase, shared between functions)
_TP_NAME=""
_TP_NUM=""
_TP_SUFFIX=""
_RESULT=""
SED_CMDS=""

# Parses FQDN into base name, numeric part, and env suffix.
# Algorithm mirrors compute_title() in lib/display.sh.
# Sets script-level globals _TP_NAME, _TP_NUM, _TP_SUFFIX (no local).
_parse_server_parts() {
    local fqdn="$1"
    local short env_part name_num
    short="${fqdn%%.*}"
    env_part="${short##*-}"
    name_num="${short%-*}"
    _TP_NUM=$(echo "$name_num" | sed 's/[^0-9]//g')
    _TP_NAME=$(echo "$name_num" | sed 's/[0-9]*$//')
    _TP_SUFFIX="$env_part"
}

# Applies one variable (3 case forms) to the global $_RESULT.
# Usage: _apply_var <key> <value>
_apply_var() {
    local _k="$1" _v="$2" _tmp
    _RESULT="${_RESULT//\{$_k\}/${_v,,}}"
    _RESULT="${_RESULT//\{${_k^^}\}/${_v^^}}"
    _tmp="${_v,,}"
    _RESULT="${_RESULT//\{${_k^}\}/${_tmp^}}"
}

# Substitutes all template variables in a template string. Outputs result to stdout.
# Requires _TP_NAME/_TP_NUM/_TP_SUFFIX to be set via _parse_server_parts beforehand.
# Reads TEMPLATE_VARS_JSON for custom variables.
_substitute() {
    local tmpl="$1" hostname="$2" short="$3" env="$4" pod="$5"
    local key val
    _RESULT="$tmpl"
    _apply_var "hostname" "$hostname"
    _apply_var "short"    "$short"
    _apply_var "env"      "$env"
    _apply_var "pod"      "$pod"
    _apply_var "name"     "$_TP_NAME"
    _apply_var "num"      "$_TP_NUM"
    _apply_var "suffix"   "$_TP_SUFFIX"
    if [ -n "$TEMPLATE_VARS_JSON" ]; then
        while IFS=$'\t' read -r key val; do
            _apply_var "$key" "$val"
        done < <(jq -r --arg env "$env" '
            to_entries[] |
            .key as $k |
            (.value | if type == "object"
                then (if has($env) then .[$env] else (.["*"] // empty) end)
                else .
            end) |
            "\($k)\t\(.)"
        ' <<< "$TEMPLATE_VARS_JSON")
    fi
    echo "$_RESULT"
}

# Escapes a value for use as a sed replacement string (| delimiter).
# Handles: backslash → \\, pipe → \|, ampersand → \&
_escape_for_sed() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/|/\\|/g; s/&/\\&/g'
}

# Returns the environment name for a given server FQDN by looking it up in pods.json.
_get_env_for_server() {
    local server="$1"
    jq -r --arg s "$server" \
        'to_entries[] | select(.value | has($s)) | .key' \
        "$PODS_FILE" | head -1
}

# Builds SED_CMDS (script-level global) for the given server.
# Uses | as sed delimiter. Values are escaped for |, \, &.
# Note: no quotes around values in replacement — valid Docker .env format.
# Only call when TEMPLATES_JSON is non-empty.
_build_sed_cmds() {
    local server="$1"
    local _short _env _pod _var _tmpl _val _esc
    SED_CMDS=""
    _parse_server_parts "$server"
    _short=$(short_name "$server")
    _pod="$SELECTED_POD"
    _env=$(_get_env_for_server "$server")
    while IFS=$'\t' read -r _var _tmpl; do
        _val=$(_substitute "$_tmpl" "$server" "$_short" "$_env" "$_pod")
        _esc=$(_escape_for_sed "$_val")
        SED_CMDS="${SED_CMDS:+$SED_CMDS;}s|^${_var}=.*|${_var}=${_esc}|"
    done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$TEMPLATES_JSON")
}

# Loads TEMPLATES_JSON and TEMPLATE_VARS_JSON from config.json for the given pod.
# Sets them to empty string if absent from config.
# Usage: load_pod_templates <pod>
load_pod_templates() {
    local pod="$1"
    TEMPLATES_JSON=$(jq -r --arg pod "$pod" \
        '.pods[$pod].env_templates // empty' "$CONFIG_FILE")
    TEMPLATE_VARS_JSON=$(jq -r '.template_vars // empty' "$CONFIG_FILE")
}

# Convenience wrapper: builds sed commands and applies them in-place to env_file.
# Only call when TEMPLATES_JSON is non-empty.
_apply_templates() {
    local server="$1" env_file="$2"
    _build_sed_cmds "$server"
    sed -i "$SED_CMDS" "$env_file"
}
