#!/usr/bin/env bash
# Tests shell admission/oracle wiring with a fake CLI. NOT native Oreslang evidence.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ores-pattern-oracle-runner.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
project="$tmp/project with spaces"
mkdir -p "$project"/{scripts,patterns,tests/native-pattern-oracles} "$tmp/bin with spaces"
cp "$root/scripts/check-native-patterns.sh" "$project/scripts/"
cp "$root"/patterns/*.ores "$project/patterns/"
cp "$root"/tests/native-pattern-oracles/*.stdout "$project/tests/native-pattern-oracles/"
cat > "$tmp/bin with spaces/fake-compiler" <<'COMPILER'
#!/usr/bin/env bash
set -euo pipefail
test "$#" -eq 2
test "$1" = check -o "$1" = run
test -z "${JAVA_TOOL_OPTIONS:-}${PYTHONPATH:-}${BASH_ENV:-}${LD_PRELOAD:-}${GIT_CONFIG_COUNT:-}"
source="$2"
root="${source%/patterns/*}"
name="${source##*/}"
printf '%s\t%s\n' "$1" "$name" >> "$root/invocations"
if [[ "$1" == check ]]; then
  if [[ -f "$root/force-check-fail" ]]; then exit 41; fi
else
  if [[ -f "$root/force-run-fail" ]]; then exit 42; fi
  if [[ -f "$root/wrong-output" ]]; then
    printf '%s\n' wrong
  else
    cat -- "$root/tests/native-pattern-oracles/${name%.ores}.stdout"
  fi
fi
COMPILER
chmod +x "$tmp/bin with spaces/fake-compiler"
export ORESLANG_BIN="$tmp/bin with spaces/fake-compiler"
export ORESLANG_COMPILER_SHA256="$(sha256sum -- "$ORESLANG_BIN" | cut -d' ' -f1)"
log="$project/invocations"
JAVA_TOOL_OPTIONS=poison PYTHONPATH=poison BASH_ENV= \
  bash "$project/scripts/check-native-patterns.sh" --execute > "$tmp/out" 2>&1
grep -q 'NATIVE_PATTERN_OUTPUT_ORACLES_MATCHED=20' "$tmp/out"
test "$(wc -l < "$log")" -eq 40
: > "$log"

for bad_pin in "" "not-hex" "$(printf '0%.0s' {1..64})" "$(printf '1%.0s' {1..64})"; do
  set +e
  ORESLANG_COMPILER_SHA256="$bad_pin" bash "$project/scripts/check-native-patterns.sh" --execute > "$tmp/out" 2>&1
  status=$?
  set -e
  test "$status" -eq 69
  test ! -s "$log"
done

touch "$project/wrong-output"
set +e
bash "$project/scripts/check-native-patterns.sh" --execute > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 65
grep -q 'exact output mismatch' "$tmp/out"
test "$(wc -l < "$log")" -eq 2
rm "$project/wrong-output"
: > "$log"

touch "$project/force-check-fail"
set +e
bash "$project/scripts/check-native-patterns.sh" --execute > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 41
test "$(wc -l < "$log")" -eq 1
rm "$project/force-check-fail"
: > "$log"

touch "$project/force-run-fail"
set +e
bash "$project/scripts/check-native-patterns.sh" --execute > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 42
test "$(wc -l < "$log")" -eq 2
rm "$project/force-run-fail"
: > "$log"

mv "$project/patterns/01-strategy.ores" "$tmp/hidden"
set +e
bash "$project/scripts/check-native-patterns.sh" --execute > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 66
test ! -s "$log"
mv "$tmp/hidden" "$project/patterns/01-strategy.ores"

set +e
bash "$project/scripts/check-native-patterns.sh" > "$tmp/out" 2>&1
status=$?
set -e
test "$status" -eq 64
test ! -s "$log"
echo "native pattern runner contracts: PASS (test double only)"
