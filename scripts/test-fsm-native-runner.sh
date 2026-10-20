#!/usr/bin/env bash
# Runner contract test double only; NOT real Oreslang compiler evidence.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/fsm-native-runner.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
testdir="$tmp/path with spaces"
mkdir -p "$testdir"
cat > "$testdir/fake-oreslang" <<'COMPILER'
#!/usr/bin/env bash
set -euo pipefail
test "$#" = 2
test "$2" = "$FSM_EXPECTED_FIXTURE"
case "$1" in
  check|run) ;;
  *) exit 91 ;;
esac
printf '%s\n' "$1" >> "$FSM_RUN_LOG"
if [[ "$1" == "check" ]]; then
  exit "${FSM_CHECK_STATUS:-0}"
fi
COMPILER
chmod +x "$testdir/fake-oreslang"
export FSM_EXPECTED_FIXTURE="$root/examples/fsm/01-symbol-reducer.ores"
export FSM_RUN_LOG="$tmp/invocations"
export ORESLANG_BIN="$testdir/fake-oreslang"

bash "$root/scripts/check-fsm-native.sh"
test "$(cat "$FSM_RUN_LOG")" = "check"
: > "$FSM_RUN_LOG"

bash "$root/scripts/check-fsm-native.sh" --execute
test "$(cat "$FSM_RUN_LOG")" = "$(printf 'check\nrun')"
: > "$FSM_RUN_LOG"

# Compiler syntax failure must prevent guest execution.
set +e
FSM_CHECK_STATUS=41 bash "$root/scripts/check-fsm-native.sh" --execute > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 41
test "$(cat "$FSM_RUN_LOG")" = "check"
: > "$FSM_RUN_LOG"

# Reject malformed runner invocations before compiler interaction.
set +e
bash "$root/scripts/check-fsm-native.sh" --not-a-mode > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 64
test ! -s "$FSM_RUN_LOG"
set +e
bash "$root/scripts/check-fsm-native.sh" --execute --execute > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 64
test ! -s "$FSM_RUN_LOG"

# Missing compiler must not become a green test.
set +e
ORESLANG_BIN="$tmp/no-such-compiler" bash "$root/scripts/check-fsm-native.sh" > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 69
grep -q 'compiler not found' "$tmp/out"
echo "native runner contracts: PASS (test-double only)"
