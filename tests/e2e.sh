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
echo "────────────────────────"
echo "passed: $pass   failed: $fail"
[[ $fail -eq 0 ]]
