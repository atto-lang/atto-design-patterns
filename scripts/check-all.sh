#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for source in "$root"/patterns/*.ores; do
  echo "==> oreslang check ${source#$root/}"
  oreslang check "$source"
done
