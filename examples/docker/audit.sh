# @match *
# @mode  post
# @desc  Append every docker invocation to an audit log

run() {
    local log="${DOCKER_AUDIT_LOG:-$HOME/.docker-audit.log}"
    printf '%s  rc=%s  docker %s\n' \
        "$(date -Iseconds)" "${CLIWRAP_EXIT_CODE:-?}" "$*" >> "$log"
}
