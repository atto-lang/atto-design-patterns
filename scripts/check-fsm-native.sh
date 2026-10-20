#!/usr/bin/env bash
# Explicit native guest-source gate. Do not silently downgrade to Python stubs.
set -euo pipefail
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
elif [[ "$#" -gt 0 ]]; then
  echo "usage: $0 [--execute]" >&2
  exit 64
fi
