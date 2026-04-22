# @match push
# @mode  pre
# @desc  Block destructive force-push to protected branches

run() {
    local has_force=0
    for a in "$@"; do
        [[ "$a" == "--force" || "$a" == "-f" ]] && has_force=1
    done
    [[ "$has_force" == "0" ]] && return 0

    local branch
    branch=$(command git branch --show-current 2>/dev/null || echo "")

    case "$branch" in
        main|master|production|release/*)
            echo "⚠  You are about to FORCE PUSH to '$branch'." >&2
            read -rp "Type the branch name to confirm: " confirm
            [[ "$confirm" == "$branch" ]] || { echo "Aborted."; return 1; }
            ;;
    esac
}
