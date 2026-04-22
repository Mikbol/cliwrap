# @match clean
# @mode  replace
# @desc  Remove stopped containers, dangling images, and unused volumes
# @arg   --all      Also remove unused images (not just dangling)
# @arg   --dry-run  Show what would be removed

run() {
    local flags=""
    [[ -n "${ARG_ALL:-}" ]] && flags="--all"

    if [[ -n "${ARG_DRY_RUN:-}" ]]; then
        echo "Would run: docker system prune $flags --volumes"
        command docker system df
        return
    fi

    command docker system prune $flags --volumes -f
}
