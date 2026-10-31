#!/usr/bin/env bash
# Exact-stdout positive checks for all 20 patterns.
# This is a verification *gate*, never a self-attesting compiler receipt.
set -euo pipefail
if [[ "$#" -ne 1 || "$1" != "--execute" ]]; then
  echo "usage: $0 --execute" >&2
  exit 64
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
compiler="${ORESLANG_BIN:-}"
pin="${ORESLANG_COMPILER_SHA256:-}"
if [[ "$compiler" != /* || ! -f "$compiler" || ! -x "$compiler" ]]; then
  echo "native patterns blocked: trusted absolute compiler executable required" >&2
  exit 69
fi
if [[ ! "$pin" =~ ^[0-9a-f]{64}$ || "$pin" == "$(printf '0%.0s' {1..64})" ]]; then
  echo "native patterns blocked: independently established compiler SHA-256 required" >&2
  exit 69
fi
sha="$(sha256sum -- "$compiler")"
sha="${sha%% *}"
if [[ "$sha" != "$pin" ]]; then
  echo "native patterns blocked: compiler SHA-256 mismatch" >&2
  exit 69
fi
cd "$root"
shopt -s nullglob
sources=("$root"/patterns/*.ores)
oracles=("$root"/tests/native-pattern-oracles/*.stdout)
if [[ "${#sources[@]}" -ne 20 || "${#oracles[@]}" -ne 20 ]]; then
  echo "native patterns blocked: exactly 20 sources and 20 output oracles required" >&2
  exit 66
fi
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ores-native-patterns.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
umask 077
run_compiler() {
  timeout --signal=TERM --kill-after=2s 60s env -i \
    PATH=/usr/bin:/bin HOME=/nonexistent LANG=C LC_ALL=C \
    "$compiler" "$1" "$2"
}
for source in "${sources[@]}"; do
  if [[ ! -f "$source" || -L "$source" || "$(realpath -e -- "$source")" != "$root/patterns/"* ]]; then
    echo "native patterns blocked: source missing or escapes repository" >&2
    exit 70
  fi
  basename="${source##*/}"
  expected="$root/tests/native-pattern-oracles/${basename%.ores}.stdout"
  if [[ ! -f "$expected" || -L "$expected" || "$(realpath -e -- "$expected")" != "$root/tests/native-pattern-oracles/"* ]]; then
    echo "native patterns blocked: missing or escaping expected stdout for $basename" >&2
    exit 70
  fi
  printf '==> check %s\n' "$basename"
  run_compiler check "$source" > "$tmp/check.stdout" 2> "$tmp/check.stderr"
  sha="$(sha256sum -- "$compiler")"
  sha="${sha%% *}"
  if [[ "$sha" != "$pin" ]]; then
    echo "native patterns blocked: compiler changed between check and run" >&2
    exit 69
  fi
  printf '==> run %s\n' "$basename"
  run_compiler run "$source" > "$tmp/actual.stdout" 2> "$tmp/actual.stderr"
  if ! cmp -s -- "$expected" "$tmp/actual.stdout"; then
    echo "native patterns rejected: exact output mismatch in $basename" >&2
    exit 65
  fi
done
printf '%s\n' 'NATIVE_PATTERN_OUTPUT_ORACLES_MATCHED=20 (compiler provenance still requires independent verification)'
