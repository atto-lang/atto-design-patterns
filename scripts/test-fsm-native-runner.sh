#!/usr/bin/env bash
# Runner contract test double only; NOT real Oreslang compiler evidence.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/fsm-native-runner.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
testdir="$tmp/path with spaces"
mkdir -p "$testdir"
cat > "$testdir/fake-oreslang" <<'COMPILER'
#!/usr/bin/env bash
set -euo pipefail
test "$#" = 2
case "$2" in
  */examples/fsm/01-symbol-reducer.ores) ;;
  *) exit 92 ;;
esac
case "$1" in
  check|run) ;;
  *) exit 91 ;;
esac
# Deliberately poison the caller environment to verify no compiler inheritance.
test -z "${JAVA_TOOL_OPTIONS:-}${GIT_CONFIG_COUNT:-}${PYTHONPATH:-}${BASH_ENV:-}${LD_PRELOAD:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
printf '%s\n' "$1" >> "$script_dir/invocations"
if [[ "$1" == "check" && -e "$script_dir/force-check-fail" ]]; then
  exit 41
fi
COMPILER
chmod +x "$testdir/fake-oreslang"
export ORESLANG_BIN="$testdir/fake-oreslang"
log="$tmp/invocations"

JAVA_TOOL_OPTIONS=poison GIT_CONFIG_COUNT=1 PYTHONPATH=/bad \
  bash "$root/scripts/check-fsm-native.sh"
test "$(cat "$log")" = "check"
: > "$log"

bash "$root/scripts/check-fsm-native.sh" --execute
test "$(cat "$log")" = "$(printf 'check\nrun')"
: > "$log"

# Check failure must prevent executing guest code.
touch "$tmp/force-check-fail"
set +e
bash "$root/scripts/check-fsm-native.sh" --execute > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 41
test "$(cat "$log")" = "check"
rm "$tmp/force-check-fail"
: > "$log"

# Reject malformed modes before even invoking the compiler.
for bad in "--not-a-mode" "--execute --execute"; do
  set +e
  # Explicitly expand the one supported two-argument rejection.
  if [[ "$bad" == "--execute --execute" ]]; then
    bash "$root/scripts/check-fsm-native.sh" --execute --execute > "$tmp/out" 2>&1
  else
    bash "$root/scripts/check-fsm-native.sh" "$bad" > "$tmp/out" 2>&1
  fi
  status=$?
  set -e
  test "$status" -eq 64
  test ! -s "$log"
done

# A relative/PATH-resolved compiler, missing compiler and non-executable file
# must all fail closed rather than producing a false green native receipt.
: > "$tmp/not-executable"
for invalid in "oreslang" "$tmp/no-such-compiler" "$tmp/not-executable"; do
  set +e
  ORESLANG_BIN="$invalid" bash "$root/scripts/check-fsm-native.sh" > "$tmp/out" 2>&1
  status=$?
  set -e
  test "$status" -eq 69
  grep -q 'compiler not found' "$tmp/out"
  test ! -s "$log"
done
echo "native runner contracts: PASS (test-double only)"
