# @match sync
# @mode  replace
# @desc  Fetch, rebase on origin/<default-branch>, push
# @arg   --dry-run   Show what would happen without doing it

run() {
  local branch default
  branch=$(command git branch --show-current)
  default=$(command git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
              | sed 's|refs/remotes/origin/||' || echo "main")

  local prefix=""
  [[ -n "${ARG_DRY_RUN:-}" ]] && prefix="echo [dry-run]"

  $prefix command git fetch origin
  $prefix command git rebase "origin/$default"
  $prefix command git push --force-with-lease origin "$branch"
}
