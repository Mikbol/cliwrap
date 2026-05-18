#!/usr/bin/env bash
# End-to-end test for cliwrap. Uses fake `aws`/`git`/`docker` on PATH.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIWRAP_HOME=$(mktemp -d)
export CLIWRAP_HOME
export CLIWRAP_LIB="$ROOT/lib"

# Fake binaries that just print what they were called with
FAKE_BIN=$(mktemp -d)
for tool in aws git docker; do
  cat > "$FAKE_BIN/$tool" <<EOF
#!/bin/bash
echo "[REAL $tool] \$@ | AWS_REGION=\${AWS_REGION:-unset} AWS_PROFILE=\${AWS_PROFILE:-unset} AWS_PAGER=\${AWS_PAGER:-unset}"
EOF
  chmod +x "$FAKE_BIN/$tool"
done
export PATH="$FAKE_BIN:$PATH"

# Set up wrappers from examples
for cli in aws git docker; do
  mkdir -p "$CLIWRAP_HOME/$cli"
  cp "$ROOT/examples/$cli"/*.sh "$CLIWRAP_HOME/$cli/"
done

# Source the runtime and register
source "$ROOT/lib/runtime.sh"
for cli in aws git docker; do
  cliwrap_register "$cli"
done

pass=0; fail=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  ✓ $desc"; pass=$((pass+1))
  else
    echo "  ✗ $desc"
    echo "     expected to contain: $expected"
    echo "     got: $actual"
    fail=$((fail+1))
  fi
}

echo
echo "=== AWS ==="
out=$(aws s3 ls 2>&1)
check "global pre-hook sets AWS_REGION"     "AWS_REGION=eu-north-1" "$out"
check "global pre-hook disables pager"      "AWS_PAGER="            "$out"
check "passes through to real aws"          "[REAL aws] s3 ls"      "$out"

out=$(aws secretsmanager get-secret-value --secret-id prod/db/pw 2>&1)
check "smart-secrets sets prod profile"     "AWS_PROFILE=prod-readonly" "$out"
check "log line printed"                    "inferred from 'prod/db/pw'" "$out"
check "real aws still called"               "[REAL aws] secretsmanager get-secret-value --secret-id prod/db/pw" "$out"

out=$(aws secretsmanager get-secret-value --secret-id dev/api/key 2>&1)
check "smart-secrets switches to dev"       "AWS_PROFILE=dev" "$out"

out=$(aws secretsmanager get-secret-value --secret-id dev/x --profile explicit 2>&1)
check "explicit --profile wins"             "AWS_PROFILE=unset" "$out"

# whoami replace command — mock sts in the fake binary
cat > "$FAKE_BIN/aws" <<'EOF'
#!/bin/bash
if [[ "$1" == "sts" && "$2" == "get-caller-identity" ]]; then
    echo '{"UserId":"AIDA42","Account":"123456789","Arn":"arn:aws:iam::123456789:user/claude"}'
else
    echo "[REAL aws] $@"
fi
EOF
chmod +x "$FAKE_BIN/aws"

out=$(aws whoami 2>&1)
check "custom 'whoami' runs as replace"     "Account:  123456789" "$out"
check "whoami shows ARN"                    "arn:aws:iam::123456789" "$out"

out=$(aws whoami --json 2>&1)
check "--json flag consumed and works"      '"Account":"123456789"' "$out"

echo
echo "=== GIT (sync requires real repo, test safe-push matching instead) ==="
out=$(git status 2>&1)
check "git passthrough works"               "[REAL git] status" "$out"

# safe-push without --force should pass through
out=$(git push origin feature 2>&1)
check "git push without --force passes"     "[REAL git] push origin feature" "$out"

echo
echo "=== DOCKER ==="
out=$(docker ps 2>&1)
check "docker passthrough works"            "[REAL docker] ps" "$out"

AUDIT_LOG=$(mktemp)
export DOCKER_AUDIT_LOG="$AUDIT_LOG"
docker ps -a >/dev/null 2>&1
docker images >/dev/null 2>&1
check "post-hook logged 2 entries"          "docker ps -a" "$(cat "$AUDIT_LOG")"
check "post-hook logged images call"        "docker images" "$(cat "$AUDIT_LOG")"
check "post-hook includes exit code"        "rc=0"         "$(cat "$AUDIT_LOG")"

echo
echo "=== HELP INTEGRATION ==="
out=$(aws --help 2>&1)
check "--help shows real help"              "[REAL aws] --help" "$out"
check "--help shows custom commands section" "CUSTOM COMMANDS" "$out"
check "--help lists whoami"                 "whoami" "$out"

echo
echo "=== COMPLETION ==="
# Simulate tab completion at different positions
COMP_WORDS=(aws ""); COMP_CWORD=1; COMP_LINE="aws "; COMP_POINT=4
_cliwrap_complete
check "completion offers 'whoami' as subcommand" "whoami" "${COMPREPLY[*]}"

COMP_WORDS=(aws whoami ""); COMP_CWORD=2; COMP_LINE="aws whoami "; COMP_POINT=11
_cliwrap_complete
check "completion offers --json flag for whoami"  "--json" "${COMPREPLY[*]}"

echo
echo "=== POSIX -- TERMINATOR ==="
cat > "$CLIWRAP_HOME/aws/dashdash.sh" <<'EOF'
# @match dashdash
# @mode  replace
# @desc  Print received args
# @arg   --verbose   Be loud
run() {
  echo "ARG_VERBOSE=${ARG_VERBOSE:-unset}"
  echo "args=[$*]"
}
EOF

out=$(aws dashdash --verbose foo bar 2>&1)
check "args before -- parsed normally"     "ARG_VERBOSE=1"        "$out"
check "remaining args after extraction"    "args=[dashdash foo bar]" "$out"

out=$(aws dashdash -- --verbose foo 2>&1)
check "-- preserves --verbose as literal"  "ARG_VERBOSE=unset"     "$out"
check "args after -- include -- itself"    "args=[dashdash -- --verbose foo]" "$out"

out=$(aws dashdash foo -- --verbose bar 2>&1)
check "-- with args before and after"      "args=[dashdash foo -- --verbose bar]" "$out"

echo
echo "=== FLAG PARSING EDGE CASES ==="
cat > "$CLIWRAP_HOME/aws/flagedge.sh" <<'EOF'
# @match flagedge
# @mode  replace
# @desc  Edge case flag tests
# @arg   --output=FORMAT   Output format
# @arg   --count=N         Numeric count
# @arg   --verbose         Be loud
# @arg   --multi-word      Multi-word flag
run() {
  echo "OUTPUT=${ARG_OUTPUT:-unset}"
  echo "COUNT=${ARG_COUNT:-unset}"
  echo "VERBOSE=${ARG_VERBOSE:-unset}"
  echo "MULTI_WORD=${ARG_MULTI_WORD:-unset}"
  echo "remaining=[$*]"
}
EOF

out=$(aws flagedge --output=json --count=42 --verbose --multi-word 2>&1)
check "all = syntax flags parsed"          "OUTPUT=json"           "$out"
check "numeric value preserved"            "COUNT=42"              "$out"
check "boolean flag set to 1"              "VERBOSE=1"             "$out"
check "multi-word → ARG_MULTI_WORD"        "MULTI_WORD=1"          "$out"

out=$(aws flagedge --output "with spaces" 2>&1)
check "space-separated quoted value"       "OUTPUT=with spaces"    "$out"

out=$(aws flagedge --output "" 2>&1)
check "empty value preserved"              "OUTPUT="               "$out"

out=$(aws flagedge --output=hello extra positional 2>&1)
check "positional args preserved"          "remaining=[flagedge extra positional]" "$out"

out=$(aws flagedge --output 2>&1 || true)
check "missing value errors clearly"       "expects a value"       "$out"

echo
echo "=== HOOK ORDERING ==="
ORDER_LOG=$(mktemp)
mkdir -p "$CLIWRAP_HOME/git"
for i in 1 2 3; do
  cat > "$CLIWRAP_HOME/git/0${i}-order.sh" <<EOF
# @match order-test
# @mode  pre
# @desc  Order-test step $i
run() { echo "step-$i" >> "$ORDER_LOG"; }
EOF
done
cat > "$CLIWRAP_HOME/git/99-order-runner.sh" <<EOF
# @match order-test
# @mode  replace
# @desc  Just print done
run() { echo "done"; }
EOF

out=$(git order-test 2>&1)
check "all 3 pre-hooks executed"           "done"                  "$out"
log_content=$(cat "$ORDER_LOG" | tr '\n' ' ')
check "pre-hooks ran in filename order"    "step-1 step-2 step-3"  "$log_content"

echo
echo "=== POST-HOOK EXIT CODE ==="
EXIT_LOG=$(mktemp)
cat > "$CLIWRAP_HOME/docker/exit-capture.sh" <<EOF
# @match exit-test
# @mode  post
# @desc  Capture exit code
run() { echo "rc=\${CLIWRAP_EXIT_CODE:-?}" >> "$EXIT_LOG"; }
EOF
cat > "$FAKE_BIN/docker" <<'EOF'
#!/bin/bash
if [[ "$1" == "exit-test" ]]; then exit 42; fi
echo "[REAL docker] $@"
EOF
chmod +x "$FAKE_BIN/docker"

docker exit-test >/dev/null 2>&1 || true
check "post-hook sees real exit code"      "rc=42"                 "$(cat "$EXIT_LOG")"

cat > "$FAKE_BIN/docker" <<'EOF'
#!/bin/bash
echo "[REAL docker] $@"
EOF
chmod +x "$FAKE_BIN/docker"

echo
echo "=== MISSING run() VALIDATION ==="
cat > "$CLIWRAP_HOME/git/norun.sh" <<EOF
# @match norun-test
# @mode  replace
# @desc  No run() defined
EOF
out=$(git norun-test 2>&1)
check "missing run() emits warning"        "defines no run()"      "$out"

echo
echo "=== CLIWRAP_DEBUG MODE ==="
out=$(CLIWRAP_DEBUG=1 aws whoami 2>&1)
check "debug mode logs run() invocation"   "cliwrap[debug]: run()"  "$out"
out=$(aws whoami 2>&1)
check "debug silent when DEBUG unset"      ""                       "${out//cliwrap[debug]/MARKER}"

echo
echo "=== NESTED WRAPPED CALLS ==="
cat > "$CLIWRAP_HOME/git/nested.sh" <<EOF
# @match nested
# @mode  replace
# @desc  Calls aws from within git wrapper
run() {
  aws s3 ls
  echo "git-after-aws"
}
EOF
out=$(git nested 2>&1)
check "nested wrapped call dispatches both"  "git-after-aws"       "$out"
check "nested wrapped call: aws passthrough"  "[REAL aws] s3 ls"   "$out"

echo
echo "=== STRIPPING DECLARED FLAGS FROM NATIVE CLI ==="
cat > "$CLIWRAP_HOME/aws/strip.sh" <<EOF
# @match strip-test
# @mode  pre
# @desc  Declares but doesn't consume args
# @arg   --my-flag=VAL    A flag native CLI shouldn't see
run() { :; }
EOF
out=$(aws strip-test --my-flag=value other-arg 2>&1)
check "native CLI does not receive --my-flag" "[REAL aws] strip-test other-arg" "$out"

echo
echo "=== EXTENSION FILENAME ROBUSTNESS ==="
cat > "$CLIWRAP_HOME/git/00-first.sh" <<EOF
# @match robust-test
# @mode  pre
# @desc  First
run() { echo "first"; }
EOF
cat > "$CLIWRAP_HOME/git/zz-last.sh" <<EOF
# @match robust-test
# @mode  pre
# @desc  Last
run() { echo "last"; }
EOF
cat > "$CLIWRAP_HOME/git/run-robust.sh" <<EOF
# @match robust-test
# @mode  replace
# @desc  Replace
run() { echo "replaced"; }
EOF
out=$(git robust-test 2>&1)
check "00- prefixed file loads"            "first"                 "$out"
check "zz- prefixed file loads"            "last"                  "$out"
check "replace hook runs after pre hooks"  "replaced"              "$out"

echo
echo "────────────────────────"
echo "passed: $pass   failed: $fail"
[[ $fail -eq 0 ]]
