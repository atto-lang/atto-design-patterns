#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ores-pattern-runner.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"
project="$tmp/project with spaces"
mkdir -p "$project/scripts" "$project/patterns" "$tmp/bin"
cp "$root/scripts/check-all.sh" "$project/scripts/check-all.sh"
printf 'first fixture\n' > "$project/patterns/01-first.ores"
printf 'second fixture\n' > "$project/patterns/02-second.ores"
cat > "$tmp/bin/compiler" <<'COMPILER'
#!/usr/bin/env bash
set -euo pipefail
test "$PWD" = "$RUNNER_PROJECT"
test "$#" = 2
test "$1" = check
case "$2" in
  "$RUNNER_PROJECT/patterns/01-first.ores"|"$RUNNER_PROJECT/patterns/02-second.ores") ;;
  *) exit 91 ;;
esac
printf '%s\n' "$2" >> "$RUNNER_LOG"
exit "${RUNNER_STATUS:-0}"
COMPILER
chmod +x "$tmp/bin/compiler"
export RUNNER_PROJECT="$project" RUNNER_LOG="$tmp/invocations"
export ORESLANG_BIN="$tmp/bin/compiler"
cd "$tmp"
bash "$project/scripts/check-all.sh"
test "$(wc -l < "$RUNNER_LOG")" -eq 2
test "$(head -1 "$RUNNER_LOG")" = "$project/patterns/01-first.ores"
test "$(tail -1 "$RUNNER_LOG")" = "$project/patterns/02-second.ores"
: > "$RUNNER_LOG"
set +e
RUNNER_STATUS=44 bash "$project/scripts/check-all.sh" > "$tmp/output" 2>&1
status=$?
set -e
test "$status" = 44
test "$(wc -l < "$RUNNER_LOG")" -eq 1
if ORESLANG_BIN="$tmp/missing" bash "$project/scripts/check-all.sh" > "$tmp/output" 2>&1; then
  echo "missing compiler accepted" >&2
  exit 1
fi
mkdir "$tmp/saved-patterns"
mv "$project/patterns/"*.ores "$tmp/saved-patterns/"
: > "$RUNNER_LOG"
set +e
bash "$project/scripts/check-all.sh" > "$tmp/output" 2>&1
status=$?
set -e
test "$status" = 66
test ! -s "$RUNNER_LOG"
grep -q 'no Oreslang patterns found' "$tmp/output"
echo "runner contracts: PASS"
