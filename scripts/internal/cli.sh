#!/bin/bash

# CLI dispatcher — auto-discovers commands by convention.
# Commands expose functions named cmd_<verb> (or cmd_<verb>_<sub> for sub-commands).
# Sourced by scripts/bin/fleetman; call cli_dispatch "$ROOT/commands" "$@".
#
# Help system: each command file defines a docblock delimited by '##' lines.
# Anything outside the ## markers is regular comment — not shown in help.
# The dispatcher intercepts -h/--help before calling any command function.

_CLI_LOADED_FILE=""

# Extracts the first non-blank content line from a command file's ## docblock.
# Used to build the one-liner shown in fleetman -h and subcommand listings.
# Usage: _cli_extract_desc <filepath>
_cli_extract_desc() {
    local file="$1"
    local line in_block=0
    while IFS= read -r line; do
        if [[ "$line" == '##' ]]; then
            if [[ "$in_block" -eq 0 ]]; then in_block=1; continue
            else break; fi
        fi
        [[ "$in_block" -eq 0 ]] && continue
        [[ "$line" == '# @'* ]] && continue
        if [[ "$line" == '# '* ]]; then
            echo "${line:2}"
            return
        fi
    done < "$file"
}

# Extracts the value of a @tag metadata line from a command file's ## docblock.
# Returns exit 1 (empty output) if the tag is not found.
# Usage: _cli_extract_tag <filepath> <tag>
_cli_extract_tag() {
    local file="$1" tag="$2"
    local line in_block=0
    while IFS= read -r line; do
        if [[ "$line" == '##' ]]; then
            if [[ "$in_block" -eq 0 ]]; then in_block=1; continue
            else break; fi
        fi
        [[ "$in_block" -eq 0 ]] && continue
        if [[ "$line" == "# @${tag} "* ]]; then
            echo "${line#"# @${tag} "}"
            return 0
        fi
    done < "$file"
    return 1
}

# Scans all *.sh in <dir> for @menu/@order metadata; outputs sorted "order|label|filepath" lines.
# Exits 1 with an error message if any file is missing @menu or @order.
# Usage: _cli_scan_menu_dir <dir>
_cli_scan_menu_dir() {
    local dir="$1"
    local file label order
    local -a raw=()
    for file in "$dir"/*.sh; do
        [[ -f "$file" ]] || continue
        if ! label="$(_cli_extract_tag "$file" "menu")"; then
            echo -e "\033[1;31m  ✗ Missing @menu in ${file##*/}\033[0m" >&2
            exit 1
        fi
        if ! order="$(_cli_extract_tag "$file" "order")"; then
            echo -e "\033[1;31m  ✗ Missing @order in ${file##*/}\033[0m" >&2
            exit 1
        fi
        raw+=("${order}|${label}|${file}")
    done
    if [ "${#raw[@]}" -gt 0 ]; then
        printf '%s\n' "${raw[@]}" | sort -t'|' -k1 -n
    fi
}

# Scans cmd_dir for @menu/@order sub-commands, shows a select_menu,
# lazily sources the selected file, and calls the corresponding function.
# Usage: _cli_dispatch_submenu <cmd_dir> <commands_dir>
_cli_dispatch_submenu() {
    local cmd_dir="$1"
    local commands_dir="$2"

    local scan_out
    if ! scan_out="$(_cli_scan_menu_dir "$cmd_dir")"; then
        exit 1
    fi

    local -a entries labels files
    mapfile -t entries <<< "$scan_out"

    local entry label file
    for entry in "${entries[@]}"; do
        label="${entry#*|}"; label="${label%|*}"
        file="${entry##*|}"
        labels+=("$label")
        files+=("$file")
    done

    select_menu labels

    local rel fn
    rel="${files[$SELECTED_IDX]#"${commands_dir}/"}"
    rel="${rel%.sh}"
    fn="cmd_${rel//\//_}"
    # Source lazily: skip if function is already defined (allows mocking in tests).
    if ! declare -f "$fn" > /dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${files[$SELECTED_IDX]}"
    fi
    "$fn"
}

# Prints the ## docblock of a command file as help text.
# Strips '# ' prefix from content lines; lone '#' becomes a blank line.
# Usage: _cli_cmd_help <filepath>
_cli_cmd_help() {
    local file="$1"
    local line in_block=0
    while IFS= read -r line; do
        if [[ "$line" == '##' ]]; then
            if [[ "$in_block" -eq 0 ]]; then
                in_block=1
            else
                break
            fi
            continue
        fi
        [[ "$in_block" -eq 0 ]] && continue
        [[ "$line" == '# @'* ]] && continue
        if [[ "$line" == '# '* ]]; then
            echo "${line:2}"
        elif [[ "$line" == '#' ]]; then
            echo ""
        fi
    done < "$file"
    local subdir="${file%.sh}"
    if [[ -d "$subdir" ]]; then
        echo ""
        echo "Available subcommands:"
        local subfile short desc
        for subfile in "$subdir"/*.sh; do
            [[ -f "$subfile" ]] || continue
            short="${subfile##*/}"
            short="${short%.sh}"
            desc="$(_cli_extract_desc "$subfile")"
            printf '  %-16s %s\n' "$short" "$desc"
        done
        local subsubdir subverb
        for subsubdir in "$subdir"/*/; do
            [[ -d "$subsubdir" ]] || continue
            subverb="${subsubdir%/}"
            subverb="${subverb##*/}"
            # Skip: the .sh with the same name was already listed above
            [[ -f "$subdir/$subverb.sh" ]] && continue
            printf '  %-16s %s\n' "$subverb" "(subcommands)"
        done
    fi
}

# Lists subcommands from commands/<verb>/ when no parent file exists.
# Reads the first ## docblock line of each *.sh for its description.
# Usage: _cli_help_subcommands <commands_dir> <verb>
_cli_help_subcommands() {
    local dir="$1" verb="$2"
    local file short desc
    echo "$APP_NAME ${_CLI_VERSION:+ v$_CLI_VERSION}"
    echo "---------------------"
    echo "Usage: fleetman $verb <subcommand> [options]"
    echo ""
    echo "Available subcommands:"
    for file in "$dir/$verb"/*.sh; do
        [[ -f "$file" ]] || continue
        short="${file##*/}"
        short="${short%.sh}"
        desc="$(_cli_extract_desc "$file")"
        printf '  %-16s %s\n' "$short" "$desc"
    done
    echo ""
    echo "  Use 'fleetman $verb <subcommand> -h' for subcommand-specific help."
}

# Prints global usage with auto-discovered command list.
# Reads the first ## docblock line of each commands/*.sh as its description.
# Usage: _cli_help [commands_dir]
_cli_help() {
    local commands_dir="${1:-}"
    local file short desc subdir subverb
    echo "$APP_DESCRIPTION"
    echo ""
    echo "Usage: fleetman <command> [options]"
    echo ""
    echo "Global options:"
    echo "  -v, --version    Show version"
    echo "  -h, --help       Show this help"
    echo ""
    echo "Available commands:"
    if [[ -n "$commands_dir" ]]; then
        for file in "$commands_dir"/*.sh; do
            [[ -f "$file" ]] || continue
            short="${file##*/}"
            short="${short%.sh}"
            desc="$(_cli_extract_desc "$file")"
            printf '  %-16s %s\n' "$short" "$desc"
        done
        for subdir in "$commands_dir"/*/; do
            [[ -d "$subdir" ]] || continue
            subverb="${subdir%/}"
            subverb="${subverb##*/}"
            # Skip: the .sh with the same name was already listed above
            [[ -f "$commands_dir/$subverb.sh" ]] && continue
            printf '  %-16s %s\n' "$subverb" "(subcommands — fleetman $subverb -h)"
        done
    fi
    echo ""
    echo "  Use 'fleetman <command> -h' for command-specific help."
}

# Tries to load a command file for the given function name.
# Converts cmd_pod_pull → tries commands/pod/pull.sh then commands/pod.sh.
# Sets _CLI_LOADED_FILE on success.
# Usage: _cli_try_load <commands_dir> <fn_name>
_cli_try_load() {
    local dir="$1" fn="$2"
    local path="${fn#cmd_}"                  # e.g. pod_pull
    local file_deep file_top
    file_deep="$dir/${path//_//}.sh"         # commands/pod/pull.sh
    file_top="$dir/${path%%_*}.sh"           # commands/pod.sh

    if [[ -f "$file_deep" ]]; then
        # shellcheck source=/dev/null
        source "$file_deep"
        _CLI_LOADED_FILE="$file_deep"
        return 0
    elif [[ -f "$file_top" && "$file_top" != "$file_deep" ]]; then
        # shellcheck source=/dev/null
        source "$file_top"
        _CLI_LOADED_FILE="$file_top"
        return 0
    fi
    return 1
}

# Routes "$@" to the matching cmd_* function.
# First positional arguments build the function name; flags stop the scan.
# Intercepts -h/--help before calling any command function.
# Usage: cli_dispatch <commands_dir> [args...]
cli_dispatch() {
    local commands_dir="$1"; shift
    _CLI_LOADED_FILE=""

    # Global help / no args
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]]; then
        echo "$APP_NAME ${_CLI_VERSION:+ v$_CLI_VERSION}"
        echo "---------------------"
        _cli_help "$commands_dir"
        exit 0
    fi

    local fn="cmd"
    local arg_count=0

    for arg in "$@"; do
        [[ "$arg" == -* ]] && break          # stop scanning at first flag
        fn="${fn}_${arg}"
        arg_count=$(( arg_count + 1 ))
        _cli_try_load "$commands_dir" "$fn"  # load candidate file (ignore errors)
    done

    # Intercept -h / --help anywhere in the remaining args
    local help_requested=0 rarg
    for rarg in "${@:$((arg_count + 1))}"; do
        if [[ "$rarg" == "-h" || "$rarg" == "--help" ]]; then
            help_requested=1
            break
        fi
    done

    if [[ "$help_requested" -eq 1 ]]; then
        echo "$APP_NAME ${_CLI_VERSION:+ v$_CLI_VERSION}"
        echo "---------------------"
        if [[ -n "$_CLI_LOADED_FILE" ]]; then
            _cli_cmd_help "$_CLI_LOADED_FILE"
        else
            local verb="${fn#cmd_}"
            if [[ -n "$verb" && -d "$commands_dir/$verb" ]]; then
                _cli_help_subcommands "$commands_dir" "$verb"
            else
                echo -e "\033[1;31m  ✗ Unknown command: $verb\033[0m"
                echo ""
                _cli_help "$commands_dir"
                exit 1
            fi
        fi
        exit 0
    fi

    if declare -f "$fn" > /dev/null 2>&1; then
        shift "$arg_count"
        "$fn" "$@"
        return
    fi

    echo -e "\033[1;31m  ✗ Unknown command: ${fn#cmd_}\033[0m"
    echo ""
    _cli_help "$commands_dir"
    exit 1
}
