#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ores-pattern-paths.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project with spaces"
mkdir -p "$project/scripts" "$project/patterns" "$tmp/bin"
cp "$root/scripts/check-all.sh" "$project/scripts/check-all.sh"
printf 'safe\n' > "$project/patterns/a safe.ores"
printf 'safe\n' > "$project/patterns/b;touch-injected.ores"
printf 'safe\n' > "$project/patterns/c"$'\n'"line.ores"
cat > "$tmp/bin/compiler" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 2 && "$1" == "check" ]] || exit 91
printf '%s\0' "$2" >> "$RUNNER_PATH_LOG"
MOCK
chmod +x "$tmp/bin/compiler"
export RUNNER_PATH_LOG="$tmp/paths.log"
ORESLANG_BIN="$tmp/bin/compiler" bash "$project/scripts/check-all.sh" > "$tmp/output"
mapfile -d '' -t actual < "$RUNNER_PATH_LOG"
expected=("$project"/patterns/*.ores)
[[ "${#actual[@]}" -eq "${#expected[@]}" ]]
for ((i=0; i<${#expected[@]}; i++)); do
  [[ "${actual[i]}" == "${expected[i]}" ]] || {
    echo "changed pattern pathname at index $i" >&2
    exit 1
  }
done
[[ ! -e "$project/touch-injected" ]]
echo "check-all pathname boundaries: PASS"
