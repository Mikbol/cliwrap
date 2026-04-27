# @match whoami
# @mode  replace
# @desc  Show who you are, what account, and which profile is active
# @arg   --json    Output as JSON instead of human format

run() {
  local ident
  ident=$(command aws sts get-caller-identity --output json 2>/dev/null) \
    || { echo "Not logged in (or aws not available)"; return 1; }

  if [[ -n "${ARG_JSON:-}" ]]; then
    echo "$ident"
    return
  fi

  local account arn user
  account=$(echo "$ident" | grep -oE '"Account": *"[^"]*"' | cut -d'"' -f4)
  arn=$(echo "$ident"     | grep -oE '"Arn": *"[^"]*"'     | cut -d'"' -f4)
  user=$(echo "$ident"    | grep -oE '"UserId": *"[^"]*"'  | cut -d'"' -f4)

  echo "Profile:  ${AWS_PROFILE:-default}"
  echo "Region:   ${AWS_REGION:-?}"
  echo "Account:  $account"
  echo "ARN:      $arn"
  echo "UserId:   $user"
}
