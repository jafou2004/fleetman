#!/bin/bash

# Bash completion for the fleetman CLI.
# Auto-discovers commands from scripts/commands/ at completion time — zero
# maintenance when adding new commands or subcommands.
# Sourced from ~/.bashrc by fleetman sync (idempotent block).

# Extracts option flags from a command file's ## docblock (Options: section).
# Scans for lines matching '#   -' (3 spaces + dash) inside the ## block.
# Outputs flags space-separated (e.g. "-h --help -e -p").
# Usage: _fleetman_opts_from_file <filepath>
_fleetman_opts_from_file() {
    local file="$1"
    local line in_block=0
    while IFS= read -r line; do
        if [[ "$line" == '##' ]]; then
            if [[ "$in_block" -eq 0 ]]; then in_block=1; continue; else break; fi
        fi
        [[ "$in_block" -eq 0 ]] && continue
        if [[ "$line" == '#   -'* ]]; then
            local rest word
            rest="${line#'#   '}"
            for word in $rest; do
                [[ "$word" == -* ]] && printf '%s ' "${word%%,*}"
            done
        fi
    done < "$file"
}

# Main completion function registered with 'complete'.
# Completion priority:
#   1. Flag value completion (-e → env names, -p → pod names)
#   2. Option completion  (cur starts with -)
#   3. Subcommand completion (verb group with commands/<verb>/ directory)
#   4. Top-level command completion
_fleetman_completions() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Resolve commands directory from the fleetman binary location.
    local fleetman_bin cmd_dir
    fleetman_bin="$(command -v fleetman 2>/dev/null)" || return
    cmd_dir="$(cd "$(dirname "$(readlink -f "$fleetman_bin")")/.." && pwd)/commands"
    [[ -d "$cmd_dir" ]] || return

    # Collect verb, subverb, subsubverb — stop at first flag, mirroring the dispatcher.
    local verb="" subverb="" subsubverb="" i pos_count=0
    for (( i=1; i<COMP_CWORD; i++ )); do
        local w="${COMP_WORDS[i]}"
        [[ "$w" == -* ]] && break
        (( pos_count++ )) || true
        [[ "$pos_count" -eq 1 ]] && verb="$w"
        [[ "$pos_count" -eq 2 ]] && subverb="$w"
        [[ "$pos_count" -eq 3 ]] && subsubverb="$w"
    done

    # Value completion for flags that take an argument.
    case "$prev" in
        -e)
            if command -v jq &>/dev/null && [[ -f "$HOME/config.json" ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=( $(compgen -W "$(jq -r '.servers | keys[]' "$HOME/config.json" 2>/dev/null)" -- "$cur") )
            fi
            return ;;
        -p)
            local pods_file="$HOME/.data/pods.json"
            if command -v jq &>/dev/null && [[ -f "$pods_file" ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=( $(compgen -W "$(jq -r '.[][][]' "$pods_file" 2>/dev/null | sort -u)" -- "$cur") )
            fi
            return ;;
    esac

    # Option completion (current word starts with -).
    if [[ "$cur" == -* ]]; then
        local cmd_file=""
        if [[ -n "$subsubverb" && -f "$cmd_dir/$verb/$subverb/$subsubverb.sh" ]]; then
            cmd_file="$cmd_dir/$verb/$subverb/$subsubverb.sh"
        elif [[ -n "$subverb" && -f "$cmd_dir/$verb/$subverb.sh" ]]; then
            cmd_file="$cmd_dir/$verb/$subverb.sh"
        elif [[ -n "$verb" && -f "$cmd_dir/$verb.sh" ]]; then
            cmd_file="$cmd_dir/$verb.sh"
        fi
        if [[ -n "$cmd_file" ]]; then
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "$(_fleetman_opts_from_file "$cmd_file")" -- "$cur") )
        fi
        return
    fi

    # Sub-subcommand completion (depth 3: commands/<verb>/<subverb>/ directory).
    if [[ -n "$verb" && -n "$subverb" && -z "$subsubverb" && -d "$cmd_dir/$verb/$subverb" ]]; then
        local subs="" f
        for f in "$cmd_dir/$verb/$subverb"/*.sh; do
            [[ -f "$f" ]] || continue
            local s="${f##*/}"; s="${s%.sh}"
            subs+=" $s"
        done
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$subs" -- "$cur") )
        return
    fi

    # Subcommand completion (verb group with a commands/<verb>/ directory).
    if [[ -n "$verb" && -z "$subverb" && -d "$cmd_dir/$verb" ]]; then
        local subs="" f
        for f in "$cmd_dir/$verb"/*.sh; do
            [[ -f "$f" ]] || continue
            local s="${f##*/}"; s="${s%.sh}"
            subs+=" $s"
        done
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$subs" -- "$cur") )
        return
    fi

    # Top-level command completion.
    if [[ -z "$verb" ]]; then
        local cmds="" f
        for f in "$cmd_dir"/*.sh; do
            [[ -f "$f" ]] || continue
            local s="${f##*/}"; s="${s%.sh}"
            cmds+=" $s"
        done
        for f in "$cmd_dir"/*/; do
            [[ -d "$f" ]] || continue
            local s="${f%/}"; s="${s##*/}"
            cmds+=" $s"
        done
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
    fi
}

complete -F _fleetman_completions fleetman
