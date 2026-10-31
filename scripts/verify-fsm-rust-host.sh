#!/usr/bin/env bash
# Trusted Linux host: exact-commit Rust-only FSM verification.
# A local result is NOT a GitHub Actions job or Oreslang guest execution.
set -euo pipefail

if [[ "${1:-}" != --execute || "$#" -ne 1 ]]; then
  echo 'usage: ORESLANG_EXPECTED_HEAD=<independently-pinned-40-hex-commit> bash scripts/verify-fsm-rust-host.sh --execute' >&2
  exit 64
fi
expected="${ORESLANG_EXPECTED_HEAD:-}"
if [[ ! "$expected" =~ ^[0-9a-f]{40}$ || "$expected" =~ ^0{40}$ ]]; then
  echo 'rust FSM blocked: independently pinned PR HEAD is required' >&2
  exit 69
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -- "$root"
if [[ "$(git rev-parse --show-toplevel)" != "$root" ]]; then
  echo 'rust FSM blocked: expected a top-level trusted checkout' >&2
  exit 69
fi
actual="$(git rev-parse --verify HEAD)"
if [[ "$actual" != "$expected" ]]; then
  echo "rust FSM blocked: HEAD mismatch (actual $actual)" >&2
  exit 69
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'rust FSM blocked: working tree is not clean' >&2
  exit 69
fi

for command_name in git rustc cargo rustfmt sha256sum mktemp; do
  if ! command -v -- "$command_name" > /dev/null 2>&1; then
    echo "rust FSM blocked: required host tool missing: $command_name" >&2
    exit 69
  fi
done
files=(
  tools/fsm-model/Cargo.toml
  tools/fsm-model/Cargo.lock
  tools/fsm-model/src/lib.rs
  tools/fsm-model/tests/reference.rs
  examples/fsm/01-symbol-reducer.ores
)
for f in "${files[@]}"; do
  if [[ ! -f "$f" || -L "$f" ]]; then
    echo "rust FSM blocked: expected regular, non-symlink file: $f" >&2
    exit 69
  fi
done

before="$(sha256sum -- "${files[@]}")"
target_dir="$(mktemp -d "${TMPDIR:-/tmp}/ores-fsm-rust.XXXXXXXX")"
trap 'rm -rf -- "$target_dir"' EXIT
export CARGO_TARGET_DIR="$target_dir" CARGO_NET_OFFLINE=true
manifest="$root/tools/fsm-model/Cargo.toml"

printf '%s\n' "HEAD=$actual"
printf '%s\n' "TREE=$(git rev-parse HEAD^{tree})"
printf '%s\n' "$before"
rustc --version
cargo --version
rustfmt --version

cargo fmt --manifest-path "$manifest" -- --check
cargo clippy --manifest-path "$manifest" --offline --locked --all-targets -- -D warnings
cargo test --manifest-path "$manifest" --offline --locked --all-targets

after="$(sha256sum -- "${files[@]}")"
if [[ "$before" != "$after" || "$(git rev-parse HEAD)" != "$expected" ||
      -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'rust FSM blocked: inputs or repository changed during verification' >&2
  exit 70
fi
printf 'RUST_FSM_HOST_CHECKS_PASSED_HEAD=%s\n' "$expected"
