#!/usr/bin/env bash
# Explicit native guest-source gate: fail closed for missing/untrusted compilers.
# This checks exact guest stdout only in --execute mode. It is not compiler provenance attestation.
set -euo pipefail
if [[ "$#" -gt 1 ]] || { [[ "$#" -eq 1 ]] && [[ "$1" != "--execute" ]]; }; then
  echo "usage: $0 [--execute]" >&2
  exit 64
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
compiler="${ORESLANG_BIN:-}"
fixture="$root/examples/fsm/01-symbol-reducer.ores"
if [[ "$compiler" != /* || ! -f "$compiler" || ! -x "$compiler" || -L "$compiler" ]]; then
  echo "FSM native gate blocked: compiler not found or not an absolute executable path" >&2
  exit 69
fi
# An explicit compiler path and a resolved, in-repository fixture are mandatory.
if [[ ! -f "$fixture" || -L "$fixture" || "$(realpath -e -- "$fixture")" != "$fixture" ]]; then
  echo "FSM native gate blocked: fixture missing or escapes repository root" >&2
  exit 70
fi
# Do not propagate BASH_ENV, ENV, LD_*, CLASSPATH, PYTHONPATH,
# JAVA_TOOL_OPTIONS, GIT_CONFIG_* or other startup/config injection knobs.
# A compiler that requires extra ambient config must use a separately audited gate.
run_compiler() {
  timeout --signal=TERM --kill-after=2s 60s env -i \
    PATH=/usr/bin:/bin HOME=/nonexistent LANG=C LC_ALL=C \
    "$compiler" "$1" "$fixture"
}
# The binary digest is an independently supplied pin, not a Git commit SHA or
# proof of where the binary came from. Require it before executing guest code.
if [[ "${1:-}" == "--execute" ]]; then
  expected_head="${ORESLANG_EXPECTED_HEAD:-}"
  if [[ ! "$expected_head" =~ ^[0-9a-f]{40}$ || "$expected_head" =~ ^0{40}$ ]]; then
    echo "FSM native execution blocked: independently pinned exact Git HEAD required" >&2
    exit 69
  fi
  if [[ "$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)" != "$root" ||
        "$(git -C "$root" rev-parse --verify HEAD 2>/dev/null || true)" != "$expected_head" ||
        -n "$(git -C "$root" status --porcelain --untracked-files=normal 2>/dev/null || printf error)" ]]; then
    echo "FSM native execution blocked: wrong Git HEAD or dirty checkout" >&2
    exit 69
  fi
  fixture_sha256="$(sha256sum -- "$fixture")"
  fixture_sha256="${fixture_sha256%% *}"
  expected_sha256="${ORESLANG_COMPILER_SHA256:-}"
  if [[ ! "$expected_sha256" =~ ^[0-9a-f]{64}$ || "$expected_sha256" == "$(printf '0%.0s' {1..64})" ]]; then
    echo "FSM native execution blocked: missing or invalid compiler SHA-256 pin" >&2
    exit 69
  fi
  actual_sha256="$(sha256sum -- "$compiler")"
  actual_sha256="${actual_sha256%% *}"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "FSM native execution blocked: compiler SHA-256 mismatch" >&2
    exit 69
  fi
fi

run_compiler check
if [[ "${1:-}" == "--execute" ]]; then
  now="$(sha256sum -- "$fixture")"
  now="${now%% *}"
  if [[ "$now" != "$fixture_sha256" ]]; then
    echo "FSM native execution blocked: fixture changed during check" >&2
    exit 70
  fi
  # Recheck after compile; both steps still require a trusted, non-writable
  # compiler path to exclude concurrent replacement between hash and exec.
  actual_sha256="$(sha256sum -- "$compiler")"
  actual_sha256="${actual_sha256%% *}"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "FSM native execution blocked: compiler changed after check" >&2
    exit 69
  fi
  umask 077
  output="$(mktemp "${TMPDIR:-/tmp}/ores-fsm-stdout.XXXXXX")"
  trap 'rm -f -- "$output"' EXIT
  run_compiler run > "$output"
  actual_sha256="$(sha256sum -- "$compiler")"
  actual_sha256="${actual_sha256%% *}"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "FSM native execution blocked: compiler changed during guest execution" >&2
    exit 69
  fi
  now="$(sha256sum -- "$fixture")"
  now="${now%% *}"
  if [[ "$now" != "$fixture_sha256" ||
        "$(git -C "$root" rev-parse --verify HEAD)" != "$expected_head" ||
        -n "$(git -C "$root" status --porcelain --untracked-files=normal)" ]]; then
    echo "FSM native execution blocked: guest source or checkout changed during execution" >&2
    exit 70
  fi
  if ! cmp -s -- "$output" <(printf '%s\n' '#running' '#paused' '#running' '#done' '#idle' '#rejected'); then
    echo "FSM native execution rejected: guest stdout differs from exact six-line oracle" >&2
    exit 65
  fi
  cat -- "$output"
fi
