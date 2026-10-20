#!/usr/bin/env bash
# Explicit native guest-source gate: fail closed for missing/untrusted compilers.
# This checks only invocation success, NOT guest semantic correctness.
set -euo pipefail
if [[ "$#" -gt 1 ]] || { [[ "$#" -eq 1 ]] && [[ "$1" != "--execute" ]]; }; then
  echo "usage: $0 [--execute]" >&2
  exit 64
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
compiler="${ORESLANG_BIN:-}"
fixture="$root/examples/fsm/01-symbol-reducer.ores"
if [[ "$compiler" != /* || ! -f "$compiler" || ! -x "$compiler" ]]; then
  echo "FSM native gate blocked: compiler not found or not an absolute executable path" >&2
  exit 69
fi
# An explicit compiler path and a resolved, in-repository fixture are mandatory.
if [[ ! -f "$fixture" || "$(realpath -e -- "$fixture")" != "$root/"* ]]; then
  echo "FSM native gate blocked: fixture missing or escapes repository root" >&2
  exit 70
fi
# Do not propagate BASH_ENV, ENV, LD_*, CLASSPATH, PYTHONPATH,
# JAVA_TOOL_OPTIONS, GIT_CONFIG_* or other startup/config injection knobs.
# A compiler that requires extra ambient config must use a separately audited gate.
run_compiler() {
  env -i PATH=/usr/bin:/bin HOME=/nonexistent LANG=C LC_ALL=C \
    "$compiler" "$1" "$fixture"
}
run_compiler check
if [[ "${1:-}" == "--execute" ]]; then
  run_compiler run
fi
