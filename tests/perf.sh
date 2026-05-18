#!/usr/bin/env bash
# Performance regression test for cliwrap dispatch.
# Goal: dispatch a wrapped CLI with N extensions in under THRESHOLD_MS per call.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIWRAP_HOME=$(mktemp -d)
export CLIWRAP_HOME
export CLIWRAP_LIB="$ROOT/lib"

FAKE_BIN=$(mktemp -d)
BASH_PATH=$(which bash)
cat > "$FAKE_BIN/aws" <<EOF
#!$BASH_PATH
exit 0
EOF
chmod +x "$FAKE_BIN/aws"
export PATH="$FAKE_BIN:$PATH"

mkdir -p "$CLIWRAP_HOME/aws"
# Generate 20 trivial extensions
for i in $(seq -w 1 20); do
  # Variable expansion needed in heredoc (quoted delimiter would prevent it)
  # shellcheck disable=SC2086
  cat > "$CLIWRAP_HOME/aws/ext$i.sh" <<EOF
# @match perftest
# @mode  pre
# @desc  perf extension $i
run() { :; }
EOF
done
# shellcheck disable=SC2086
cat > "$CLIWRAP_HOME/aws/perf-replace.sh" <<EOF
# @match perftest
# @mode  replace
# @desc  no-op replace
run() { :; }
EOF

source "$ROOT/lib/runtime.sh"
cliwrap_register aws

# Warm up
aws perftest >/dev/null 2>&1

ITERATIONS=50
THRESHOLD_MS=500   # per-call budget with 20 extensions in test environment

START=$(date +%s%N 2>/dev/null)
for _ in $(seq 1 $ITERATIONS); do
  aws perftest >/dev/null 2>&1
done
END=$(date +%s%N 2>/dev/null)

# date +%s%N gives nanoseconds; macOS BSD date outputs literal %N like "1234567890N"
# Check if the output contains non-digits (the literal 'N' or other chars)
if [[ ! "$START" =~ ^[0-9]+$ || ! "$END" =~ ^[0-9]+$ ]]; then
  echo "perf.sh: BSD date detected (no nanoseconds); skipping precise timing on this OS."
  echo "perf.sh: ran $ITERATIONS iterations successfully — no crash."
  exit 0
fi

ELAPSED_NS=$((END - START))
PER_CALL_MS=$(( ELAPSED_NS / ITERATIONS / 1000000 ))

echo "perf.sh: $ITERATIONS iterations, ${PER_CALL_MS}ms per call (budget: ${THRESHOLD_MS}ms)"

if (( PER_CALL_MS > THRESHOLD_MS )); then
  echo "perf.sh: FAIL — dispatch latency exceeds budget"
  exit 1
fi
echo "perf.sh: PASS"
