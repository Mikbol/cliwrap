# @match secretsmanager get-secret-value
# @mode  pre
# @desc  Auto-select AWS profile based on secret-id prefix (prod/* → prod-ro)

run() {
  # Skip if user explicitly set --profile
  local a
  for a in "$@"; do
    [[ "$a" == "--profile" || "$a" == --profile=* ]] && return 0
  done

  # Find --secret-id in args (handles both `--secret-id X` and `--secret-id=X`)
  local secret="" prev=""
  for a in "$@"; do
    if [[ "$prev" == "--secret-id" ]]; then
      secret="$a"; break
    elif [[ "$a" == --secret-id=* ]]; then
      secret="${a#--secret-id=}"; break
    fi
    prev="$a"
  done

  case "$secret" in
    prod/*) export AWS_PROFILE="prod-readonly" ;;
    dev/*)  export AWS_PROFILE="dev" ;;
    stg/*)  export AWS_PROFILE="staging" ;;
  esac

  [[ -n "${AWS_PROFILE:-}" ]] && echo "[cliwrap] AWS_PROFILE=$AWS_PROFILE (inferred from '$secret')" >&2
}
