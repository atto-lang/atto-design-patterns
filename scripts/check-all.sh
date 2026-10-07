#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${ORESLANG_BIN:-oreslang}"
cd "$root"
shopt -s nullglob
sources=("$root"/patterns/*.ores)
if [[ "${#sources[@]}" -eq 0 ]]; then
  echo "no Oreslang patterns found" >&2
  exit 66
fi

for source in "${sources[@]}"; do
  echo "==> oreslang check ${source#"$root"/}"
  "$compiler" check "$source"
done
