#!/usr/bin/env zsh
# Nexus CLI tab completion for zsh with fzf integration
# Dynamically parses nx script for commands and descriptions

# Parse nx script for completion annotations
_nx_parse_commands() {
    local nx_script
    local -a parsed_commands

    # Find nx script
    if [[ -f "${ROOT_DIR:-$PWD}/.bin/nx" ]]; then
        nx_script="${ROOT_DIR:-$PWD}/.bin/nx"
    elif command -v nx >/dev/null 2>&1; then
        nx_script="$(command -v nx)"
    else
        return 1
    fi

    # Parse @completion annotations from nx script
    while IFS= read -r line; do
        if [[ $line =~ '# @completion ([a-z-]+) (.+)$' ]]; then
            local cmd="${match[1]}"
            local desc="${match[2]}"
            parsed_commands+=("${cmd}:${desc}")
        fi
    done < "$nx_script"

    # Print each command on a new line
    printf '%s\n' "${parsed_commands[@]}"
}

# Parse stack arguments for a command
_nx_parse_stack_args() {
    local nx_script="$1"
    local command="$2"

    # Check if command accepts stack argument
    awk "/^        # @completion $command /,/;;/" "$nx_script" | \
        grep -q '# @arg \[stack\]' && return 0
    return 1
}

# Parse command options
_nx_parse_options() {
    local nx_script="$1"
    local command="$2"
    local -a options

    # Extract options between command annotation and ;;
    while IFS= read -r line; do
        if [[ $line =~ '# @arg (.+)$' ]]; then
            local arg_desc="${match[1]}"
            if [[ $arg_desc =~ '^(-[a-z-]+)(,--[a-z-]+)? (.+)$' ]]; then
                local short="${match[1]}"
                local long="${match[2]#,}"
                local desc="${match[3]}"
                [[ -n $short ]] && options+=("${short}[${desc}]")
                [[ -n $long ]] && options+=("${long}[${desc}]")
            elif [[ $arg_desc =~ '^--([a-z-]+) (.+)$' ]]; then
                options+=("--${match[1]}[${match[2]}]")
            fi
        fi
    done < <(awk "/^        # @completion $command /,/;;/" "$nx_script")

    echo "${options[@]}"
}

_nx_completion() {
    local -a commands stacks options
    local curcontext="$curcontext" state line
    typeset -A opt_args

    # Find nx script
    local nx_script
    if [[ -f "${ROOT_DIR:-$PWD}/.bin/nx" ]]; then
        nx_script="${ROOT_DIR:-$PWD}/.bin/nx"
    elif command -v nx >/dev/null 2>&1; then
        nx_script="$(command -v nx)"
    else
        return 1
    fi

    # Parse commands from nx script
    local -a raw_commands
    raw_commands=(${(f)"$(_nx_parse_commands)"})

    for cmd_entry in "${raw_commands[@]}"; do
        commands+=("$cmd_entry")
    done

    # Get available stacks from the stacks directory
    local root_dir="${ROOT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    if [[ -d "${root_dir}/stacks" ]]; then
        stacks=(${(f)"$(find "${root_dir}/stacks" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | sort)"})
    fi

    _arguments -C \
        '1: :->command' \
        '2: :->stack' \
        '*: :->args'

    case $state in
        command)
            _describe 'command' commands
            ;;
        stack)
            case $line[1] in
                start|stop|restart|logs)
                    # Check if this command accepts stack argument
                    if _nx_parse_stack_args "$nx_script" "$line[1]"; then
                        _describe 'stack' stacks
                    fi

                    # Parse and add options
                    local -a cmd_options
                    cmd_options=(${(f)"$(_nx_parse_options "$nx_script" "$line[1]")"})
                    if [[ ${#cmd_options[@]} -gt 0 ]]; then
                        _arguments "${cmd_options[@]}"
                    fi
                    ;;
                check)
                    _values 'option' '--install[Attempt to install missing prerequisites]'
                    ;;
            esac
            ;;
        args)
            case $line[1] in
                logs)
                    _values 'option' \
                        '-f[Follow log output]' \
                        '--follow[Follow log output]'
                    ;;
            esac
            ;;
    esac
}

# Enhanced completion with fzf for interactive selection
_nx_fzf_completion() {
    local token=${LBUFFER##* }
    local commands stacks

    # Find nx script
    local nx_script
    if [[ -f "${ROOT_DIR:-$PWD}/.bin/nx" ]]; then
        nx_script="${ROOT_DIR:-$PWD}/.bin/nx"
    elif command -v nx >/dev/null 2>&1; then
        nx_script="$(command -v nx)"
    else
        return 1
    fi

    # Get the root directory
    local root_dir="${ROOT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

    # If we're completing the first argument (command)
    if [[ $LBUFFER =~ '^nx [a-z-]*$' ]] || [[ $LBUFFER == "nx " ]]; then
        # Parse commands from nx script
        local -a fzf_commands
        while IFS= read -r line; do
            if [[ $line =~ '# @completion ([a-z-]+) (.+)$' ]]; then
                local cmd="${match[1]}"
                local desc="${match[2]}"
                fzf_commands+=("${cmd}^${desc}")
            fi
        done < "$nx_script"

        if command -v fzf >/dev/null 2>&1 && [[ ${#fzf_commands[@]} -gt 0 ]]; then
            local selected=$(printf "%s\n" "${fzf_commands[@]}" | \
                fzf --height=40% \
                    --reverse \
                    --prompt="nx> " \
                    --delimiter="^" \
                    --with-nth=1 \
                    --preview='echo {2}' \
                    --preview-window=down:1:wrap | \
                cut -d'^' -f1)

            if [[ -n $selected ]]; then
                LBUFFER="${LBUFFER%$token}$selected"
            fi
            zle reset-prompt
            return 0
        fi
    # If we're completing the second argument (stack name) for stack commands
    elif [[ $LBUFFER =~ 'nx (start|stop|restart|logs) [a-z-]*$' ]]; then
        if [[ -d "$root_dir/stacks" ]]; then
            stacks=($(find "$root_dir/stacks" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | sort))

            if command -v fzf >/dev/null 2>&1 && [[ ${#stacks[@]} -gt 0 ]]; then
                local selected=$(printf "%s\n" "${stacks[@]}" | \
                    fzf --height=40% \
                        --reverse \
                        --prompt="stack> " \
                        --preview="echo 'Stack: {}'" \
                        --preview-window=down:1:wrap)

                if [[ -n $selected ]]; then
                    LBUFFER="${LBUFFER%$token}$selected"
                fi
                zle reset-prompt
                return 0
            fi
        fi
    fi
}

# Set up the completion
compdef _nx_completion nx

# Register fzf widget if fzf is available
if command -v fzf >/dev/null 2>&1; then
    zle -N _nx_fzf_completion
    # Bind to Ctrl-Space for nx fzf completion
    bindkey -M viins '^ ' _nx_fzf_completion
    bindkey -M emacs '^ ' _nx_fzf_completion
fi
