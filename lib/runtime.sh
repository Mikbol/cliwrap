# cliwrap runtime — sourced into user's shell via `eval "$(cliwrap init)"`
# Provides: cliwrap_register, cliwrap_dispatch, _cliwrap_complete
#
# A cliwrap "extension" is a single .sh file with metadata in comments:
#   # @match <pattern>    which subcommand this applies to
#                         "*"           → all invocations (global)
#                         "whoami"      → `<cli> whoami ...`
#                         "s3 cp"       → `<cli> s3 cp ...`
#   # @mode  <mode>       pre | post | replace   (default: pre)
#   # @desc  <text>       one-line description (shown in --help)
#   # @arg   <flag> <desc> declared flag; extracted into ARG_<NAME>, stripped
#                          from passthrough. Use --foo=VALUE for value-taking.
#
# The file defines one function: run().
# It is called with the remaining positional arguments (declared flags removed).
# Declared args are available as ARG_<UPPER_SNAKE_CASE_NAME>.

CLIWRAP_HOME="${CLIWRAP_HOME:-$HOME/.cliwrap}"

# ──────────────────────────────────────────────────────────────────────────────
# Metadata parsing
# ──────────────────────────────────────────────────────────────────────────────

_cliwrap_meta() {
    # _cliwrap_meta <file> <key>  →  prints value of first `# @key value` line
    local file="$1" key="$2"
    grep -E "^#[[:space:]]*@${key}([[:space:]]|$)" "$file" 2>/dev/null \
        | head -1 \
        | sed -E "s/^#[[:space:]]*@${key}[[:space:]]*//"
}

_cliwrap_meta_all() {
    # Prints all occurrences (for @arg which can appear multiple times)
    local file="$1" key="$2"
    grep -E "^#[[:space:]]*@${key}([[:space:]]|$)" "$file" 2>/dev/null \
        | sed -E "s/^#[[:space:]]*@${key}[[:space:]]*//"
}

# ──────────────────────────────────────────────────────────────────────────────
# Pattern matching: does an @match pattern apply to these args?
# ──────────────────────────────────────────────────────────────────────────────

_cliwrap_match() {
    # _cliwrap_match "<pattern>" <args...>
    local pattern="$1"; shift
    [[ "$pattern" == "*" ]] && return 0
    [[ -z "$pattern" ]] && return 1

    local -a pat_words args
    read -ra pat_words <<< "$pattern"
    args=("$@")

    [[ ${#args[@]} -lt ${#pat_words[@]} ]] && return 1

    local i
    for i in "${!pat_words[@]}"; do
        [[ "${args[$i]}" == "${pat_words[$i]}" ]] || return 1
    done
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# Argument extraction: pulls declared flags out of argv, exposes as ARG_*
# ──────────────────────────────────────────────────────────────────────────────

_cliwrap_extract_args() {
    # _cliwrap_extract_args <file> <args...>
    # Sets global CLIWRAP_REMAINING=() with non-consumed args
    # Exports ARG_<NAME> for each declared arg
    local file="$1"; shift

    # Parse declared args: lines look like "--flag  description"
    # or "--flag=VALUE  description"
    local -A takes_value=()
    local -A flag_name=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local flag="${line%%[[:space:]]*}"
        local base="${flag%%=*}"              # --foo or --foo=VALUE → --foo
        local name="${base#--}"; name="${name#-}"
        name="${name//-/_}"
        name="$(echo "$name" | tr '[:lower:]' '[:upper:]')"
        flag_name["$base"]="$name"
        if [[ "$flag" == *"="* ]]; then
            takes_value["$base"]=1
        fi
    done < <(_cliwrap_meta_all "$file" arg)

    CLIWRAP_REMAINING=()
    while [[ $# -gt 0 ]]; do
        local arg="$1"
        local base="${arg%%=*}"
        if [[ -n "${flag_name[$base]:-}" ]]; then
            local name="${flag_name[$base]}"
            if [[ "${takes_value[$base]:-}" == "1" ]]; then
                if [[ "$arg" == *"="* ]]; then
                    export "ARG_$name"="${arg#*=}"
                    shift
                else
                    export "ARG_$name"="$2"
                    shift 2
                fi
            else
                export "ARG_$name"=1
                shift
            fi
        else
            CLIWRAP_REMAINING+=("$arg")
            shift
        fi
    done
}

_cliwrap_clear_args() {
    local file="$1"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local flag="${line%%[[:space:]]*}"
        local base="${flag%%=*}"
        local name="${base#--}"; name="${name#-}"
        name="${name//-/_}"
        name="$(echo "$name" | tr '[:lower:]' '[:upper:]')"
        unset "ARG_$name"
    done < <(_cliwrap_meta_all "$file" arg)
}

# ──────────────────────────────────────────────────────────────────────────────
# Hook execution: source file, call run(), unset
# ──────────────────────────────────────────────────────────────────────────────

_cliwrap_run_hook() {
    local file="$1"; shift
    _cliwrap_extract_args "$file" "$@"
    local args=("${CLIWRAP_REMAINING[@]}")
    # shellcheck disable=SC1090
    source "$file"
    local rc=0
    if declare -F run >/dev/null 2>&1; then
        run "${args[@]}"
        rc=$?
        unset -f run
    fi
    _cliwrap_clear_args "$file"
    return $rc
}

# Variant that only strips declared args and returns the residual
_cliwrap_strip_declared_args() {
    # Echoes the args with all declared flags (across ALL matching extensions) removed
    local cli="$1"; shift
    local ext_dir="$CLIWRAP_HOME/$cli"
    [[ -d "$ext_dir" ]] || { printf '%q ' "$@"; return; }

    # Collect all flags declared by matching extensions
    local -A takes_value=()
    local -A known=()
    local f
    for f in "$ext_dir"/*.sh; do
        [[ -f "$f" ]] || continue
        local match
        match=$(_cliwrap_meta "$f" match)
        _cliwrap_match "$match" "$@" || continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local flag="${line%%[[:space:]]*}"
            local base="${flag%%=*}"
            known["$base"]=1
            [[ "$flag" == *"="* ]] && takes_value["$base"]=1
        done < <(_cliwrap_meta_all "$f" arg)
    done

    local out=()
    while [[ $# -gt 0 ]]; do
        local arg="$1" base="${1%%=*}"
        if [[ -n "${known[$base]:-}" ]]; then
            if [[ "${takes_value[$base]:-}" == "1" && "$arg" != *"="* ]]; then
                shift 2
            else
                shift
            fi
        else
            out+=("$1")
            shift
        fi
    done
    printf '%q ' "${out[@]}"
}

# ──────────────────────────────────────────────────────────────────────────────
# The dispatcher — this is what the wrapper function calls
# ──────────────────────────────────────────────────────────────────────────────

cliwrap_dispatch() {
    local cli="$1"; shift
    local ext_dir="$CLIWRAP_HOME/$cli"

    # No extensions → transparent passthrough
    if [[ ! -d "$ext_dir" ]] || ! compgen -G "$ext_dir/*.sh" >/dev/null; then
        command "$cli" "$@"; return
    fi

    # Intercept --help at top level
    if [[ "$1" == "--help" || "$1" == "-h" || $# -eq 0 ]]; then
        command "$cli" "$@"
        local rc=$?
        _cliwrap_help_section "$cli"
        return $rc
    fi

    # Classify matching extensions by mode
    local -a pre_hooks=() post_hooks=()
    local replace_hook=""
    local f
    for f in "$ext_dir"/*.sh; do
        [[ -f "$f" ]] || continue
        local match mode
        match=$(_cliwrap_meta "$f" match)
        mode=$(_cliwrap_meta "$f" mode); mode="${mode:-pre}"

        _cliwrap_match "$match" "$@" || continue

        case "$mode" in
            pre)     pre_hooks+=("$f") ;;
            post)    post_hooks+=("$f") ;;
            replace) replace_hook="$f" ;;
            *)       echo "cliwrap: unknown @mode '$mode' in $f" >&2 ;;
        esac
    done

    # Lifecycle: pre → (replace | native) → post
    for f in "${pre_hooks[@]}"; do
        _cliwrap_run_hook "$f" "$@" || return $?
    done

    local exit_code=0
    if [[ -n "$replace_hook" ]]; then
        _cliwrap_run_hook "$replace_hook" "$@"
        exit_code=$?
    else
        # Strip flags that our extensions declared (so native CLI doesn't see them)
        local stripped
        stripped=$(_cliwrap_strip_declared_args "$cli" "$@")
        eval "command $cli $stripped"
        exit_code=$?
    fi

    local post_f
    for post_f in "${post_hooks[@]}"; do
        CLIWRAP_EXIT_CODE=$exit_code _cliwrap_run_hook "$post_f" "$@" || true
    done

    return $exit_code
}

# ──────────────────────────────────────────────────────────────────────────────
# Help section generation
# ──────────────────────────────────────────────────────────────────────────────

_cliwrap_help_section() {
    local cli="$1"
    local ext_dir="$CLIWRAP_HOME/$cli"
    [[ -d "$ext_dir" ]] || return

    local -a custom=() hooks=()
    local f
    for f in "$ext_dir"/*.sh; do
        [[ -f "$f" ]] || continue
        local match mode desc
        match=$(_cliwrap_meta "$f" match)
        mode=$(_cliwrap_meta "$f" mode); mode="${mode:-pre}"
        desc=$(_cliwrap_meta "$f" desc)
        if [[ "$mode" == "replace" ]]; then
            custom+=("$(printf '  %-30s %s' "$match" "$desc")")
        else
            hooks+=("$(printf '  %-30s [%s] %s' "$match" "$mode" "$desc")")
        fi
    done

    echo ""
    echo "CUSTOM COMMANDS (via cliwrap):"
    if [[ ${#custom[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        printf '%s\n' "${custom[@]}"
    fi
    if [[ ${#hooks[@]} -gt 0 ]]; then
        echo ""
        echo "ACTIVE HOOKS:"
        printf '%s\n' "${hooks[@]}"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Registration: create wrapper function + hook up completion
# ──────────────────────────────────────────────────────────────────────────────

cliwrap_register() {
    local cli="$1"

    # Capture native completion spec BEFORE we overwrite it.
    # native_spec is consumed by the `eval` below via ${native_spec@Q}.
    local native_spec
    # shellcheck disable=SC2034
    native_spec=$(complete -p "$cli" 2>/dev/null || true)
    eval "_CLIWRAP_NATIVE_$(echo "$cli" | tr -c 'A-Za-z0-9' '_')=\${native_spec@Q}"

    # Define the wrapper function. Using eval so we can template the name.
    eval "
    ${cli}() {
        cliwrap_dispatch ${cli} \"\$@\"
    }
    "

    # Register our completion function
    complete -F _cliwrap_complete "$cli"
}

# ──────────────────────────────────────────────────────────────────────────────
# Completion
# ──────────────────────────────────────────────────────────────────────────────

_cliwrap_complete() {
    local cli="${COMP_WORDS[0]}"
    local ext_dir="$CLIWRAP_HOME/$cli"
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local -a candidates=()

    if [[ -d "$ext_dir" ]]; then
        local f
        for f in "$ext_dir"/*.sh; do
            [[ -f "$f" ]] || continue
            local match mode
            match=$(_cliwrap_meta "$f" match)
            mode=$(_cliwrap_meta "$f" mode); mode="${mode:-pre}"

            if [[ $COMP_CWORD -eq 1 && "$mode" == "replace" && "$match" != "*" ]]; then
                # New top-level subcommand
                candidates+=("${match%% *}")
            fi

            # Flags from matching extensions
            local -a subargs=("${COMP_WORDS[@]:1:COMP_CWORD-1}")
            if _cliwrap_match "$match" "${subargs[@]}"; then
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    local flag="${line%%[[:space:]]*}"
                    candidates+=("${flag%%=*}")
                done < <(_cliwrap_meta_all "$f" arg)
            fi
        done
    fi

    # Get native completion candidates
    local -a native_candidates=()
    local var_name
    var_name="_CLIWRAP_NATIVE_$(echo "$cli" | tr -c 'A-Za-z0-9' '_')"
    local spec="${!var_name:-}"

    if [[ "$spec" == *" -F "* ]]; then
        local func
        func=$(echo "$spec" | sed -E 's/.* -F ([^ ]+).*/\1/')
        if declare -F "$func" >/dev/null 2>&1; then
            local saved_reply=("${COMPREPLY[@]}")
            COMPREPLY=()
            "$func" "$cli" "$cur" "${COMP_WORDS[COMP_CWORD-1]:-}" 2>/dev/null || true
            native_candidates=("${COMPREPLY[@]}")
            COMPREPLY=("${saved_reply[@]}")
        fi
    elif [[ "$spec" == *" -C "* ]]; then
        local prog
        prog=$(echo "$spec" | sed -E "s/.* -C '?([^' ]+).*/\1/")
        if command -v "$prog" >/dev/null 2>&1; then
            while IFS= read -r l; do
                [[ -n "$l" ]] && native_candidates+=("$l")
            done < <(COMP_LINE="$COMP_LINE" COMP_POINT="$COMP_POINT" "$prog" 2>/dev/null)
        fi
    fi

    local all="${candidates[*]} ${native_candidates[*]}"
    # shellcheck disable=SC2207  # compgen output is safe to word-split here
    COMPREPLY=($(compgen -W "$all" -- "$cur"))
}
