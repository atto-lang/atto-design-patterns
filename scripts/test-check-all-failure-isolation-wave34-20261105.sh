#!/usr/bin/env bash
# Disposable host-only policy test; no compiled AttoLang guest.
set -euo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ores-pattern-fail-isolation.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
project="$tmp/project with spaces"
mkdir -p "$project/scripts" "$project/patterns" "$tmp/bin"
cp "$source_root/scripts/check-all.sh" "$project/scripts/check-all.sh"
printf 'fixture\n' > "$project/patterns/01-safe.ores"
printf 'fixture\n' > "$project/patterns/02 stop.ores"
printf 'fixture\n' > "$project/patterns/03;bad.ores"
cat > "$tmp/bin/mock-compiler" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 2 && "$1" == check ]] || exit 91
printf '%s\0' "$2" >> "$INVOKED_LOG"
if [[ -n "${DENY_SUFFIX:-}" && "$2" == *"$DENY_SUFFIX" ]]; then exit 37; fi
MOCK
chmod +x "$tmp/bin/mock-compiler"
export INVOKED_LOG="$tmp/invoked"
: > "$INVOKED_LOG"
ORESLANG_BIN="$tmp/bin/mock-compiler" bash "$project/scripts/check-all.sh" >/dev/null
mapfile -d '' -t paths < "$INVOKED_LOG"
[[ "${#paths[@]}" -eq 3 ]]
[[ "${paths[0]}" == "$project/patterns/01-safe.ores" ]]
[[ "${paths[1]}" == "$project/patterns/02 stop.ores" ]]
[[ "${paths[2]}" == "$project/patterns/03;bad.ores" ]]
: > "$INVOKED_LOG"
set +e
DENY_SUFFIX='02 stop.ores' ORESLANG_BIN="$tmp/bin/mock-compiler" bash "$project/scripts/check-all.sh" >"$tmp/rejected" 2>&1
status=$?
set -e
[[ "$status" -eq 37 ]] || { echo "compiler failure was not propagated: $status" >&2; exit 1; }
mapfile -d '' -t paths < "$INVOKED_LOG"
[[ "${#paths[@]}" -eq 2 ]] || { echo 'compiler failure continued scanning' >&2; exit 1; }
[[ "${paths[1]}" == "$project/patterns/02 stop.ores" ]]
: > "$INVOKED_LOG"
set +e
ORESLANG_BIN="$tmp/nonexistent" bash "$project/scripts/check-all.sh" >"$tmp/missing" 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]]
[[ ! -s "$INVOKED_LOG" ]]
rm -- "$project/patterns/"*.ores
set +e
ORESLANG_BIN="$tmp/bin/mock-compiler" bash "$project/scripts/check-all.sh" >"$tmp/empty" 2>&1
status=$?
set -e
[[ "$status" -eq 66 ]]
grep -F 'no Oreslang patterns found' "$tmp/empty" >/dev/null
[[ ! -s "$INVOKED_LOG" ]]
printf 'PATTERN_FAILURE_ISOLATION_HOST_PASS GUEST_NOT_EXECUTED\n'
