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
if [[ "$compiler" != /* || ! -f "$compiler" || ! -x "$compiler" || -L "$compiler" ]]; then
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
expected_head="${ORESLANG_EXPECTED_HEAD:-}"
if [[ ! "$expected_head" =~ ^[0-9a-f]{40}$ || "$expected_head" =~ ^0{40}$ ]]; then
  echo "native patterns blocked: independently pinned exact Git HEAD required" >&2
  exit 69
fi
if [[ "$(git rev-parse --show-toplevel 2>/dev/null || true)" != "$root" ||
      "$(git rev-parse --verify HEAD 2>/dev/null || true)" != "$expected_head" ||
      -n "$(git status --porcelain --untracked-files=normal 2>/dev/null || printf error)" ]]; then
  echo "native patterns blocked: Git HEAD mismatch or dirty/untrusted checkout" >&2
  exit 69
fi
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
  fixture_sha="$(sha256sum -- "$source")"
  fixture_sha="${fixture_sha%% *}"
  oracle_sha="$(sha256sum -- "$expected")"
  oracle_sha="${oracle_sha%% *}"
  printf '==> check %s\n' "$basename"
  run_compiler check "$source" > "$tmp/check.stdout" 2> "$tmp/check.stderr"
  now="$(sha256sum -- "$source")"
  now="${now%% *}"
  if [[ "$now" != "$fixture_sha" ]]; then
    echo "native patterns blocked: source changed between check and run in $basename" >&2
    exit 70
  fi
  sha="$(sha256sum -- "$compiler")"
  sha="${sha%% *}"
  if [[ "$sha" != "$pin" ]]; then
    echo "native patterns blocked: compiler changed between check and run" >&2
    exit 69
  fi
  printf '==> run %s\n' "$basename"
  run_compiler run "$source" > "$tmp/actual.stdout" 2> "$tmp/actual.stderr"
  now="$(sha256sum -- "$source")"
  now="${now%% *}"
  if [[ "$now" != "$fixture_sha" ]]; then
    echo "native patterns blocked: source changed during execution in $basename" >&2
    exit 70
  fi
  now="$(sha256sum -- "$expected")"
  now="${now%% *}"
  if [[ "$now" != "$oracle_sha" ]]; then
    echo "native patterns blocked: output oracle changed during execution in $basename" >&2
    exit 70
  fi
  if ! cmp -s -- "$expected" "$tmp/actual.stdout"; then
    echo "native patterns rejected: exact output mismatch in $basename" >&2
    exit 65
  fi
done
if [[ "$(git rev-parse --verify HEAD)" != "$expected_head" ||
      -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "native patterns blocked: repository changed during verification" >&2
  exit 70
fi
printf '%s\n' 'NATIVE_PATTERN_OUTPUT_ORACLES_MATCHED=20 (compiler provenance still requires independent verification)'
