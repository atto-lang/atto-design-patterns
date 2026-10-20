#!/usr/bin/env bash
# Explicit native guest-source gate: missing compiler and unsupported syntax fail.
set -euo pipefail
if [[ "$#" -gt 1 ]] || { [[ "$#" -eq 1 ]] && [[ "$1" != "--execute" ]]; }; then
  echo "usage: $0 [--execute]" >&2
  exit 64
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${ORESLANG_BIN:-oreslang}"
fixture="$root/examples/fsm/01-symbol-reducer.ores"
if ! command -v "$compiler" >/dev/null 2>&1 && [[ ! -x "$compiler" ]]; then
  echo "FSM native gate blocked: Oreslang compiler not found: $compiler" >&2
  exit 69
fi
"$compiler" check "$fixture"
if [[ "${1:-}" == "--execute" ]]; then
  "$compiler" run "$fixture"
fi
