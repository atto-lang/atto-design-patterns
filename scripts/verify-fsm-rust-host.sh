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

# Reject external Rust tool/config injection. A trusted runner uses its
# provisioned, unmodified toolchain/configuration.
for forbidden in RUSTC RUSTDOC RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER \
  CARGO_BUILD_RUSTC CARGO_BUILD_RUSTDOC CARGO_BUILD_RUSTC_WRAPPER \
  CARGO_BUILD_RUSTC_WORKSPACE_WRAPPER CARGO_HOME RUSTUP_HOME \
  RUSTFLAGS CARGO_ENCODED_RUSTFLAGS RUSTDOCFLAGS; do
  if [[ -v "$forbidden" ]]; then
    echo "rust FSM blocked: external toolchain/config override: $forbidden" >&2
    exit 69
  fi
done
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

for command_name in git rustc cargo rustfmt sha256sum mktemp readlink; do
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

# Record resolved host executable paths and digests as integrity fences.
# The hashes are local integrity evidence, NOT independent toolchain provenance.
declare -A host_tool_paths host_tool_digests
for command_name in git rustc cargo rustfmt; do
  resolved="$(command -v -- "$command_name")"
  resolved="$(readlink -f -- "$resolved")"
  if [[ ! -f "$resolved" || ! -x "$resolved" ]]; then
    echo "rust FSM blocked: invalid host tool: $command_name" >&2
    exit 69
  fi
  host_tool_paths[$command_name]="$resolved"
  digest="$(sha256sum -- "$resolved")"
  host_tool_digests[$command_name]="${digest%% *}"
  printf 'HOST_TOOL_%s=%s\n' "$command_name" "$resolved"
  printf 'HOST_TOOL_SHA256_%s=%s\n' "$command_name" "${host_tool_digests[$command_name]}"
done
printf '%s\n' "HEAD=$actual"
printf '%s\n' "TREE=$(git rev-parse HEAD^{tree})"
printf '%s\n' "$before"
rustc --version
cargo --version
rustfmt --version

cargo fmt --manifest-path "$manifest" -- --check
cargo clippy --manifest-path "$manifest" --offline --locked --all-targets -- -D warnings
cargo test --manifest-path "$manifest" --offline --locked --all-targets
cargo test --manifest-path "$manifest" --offline --locked --doc

# A matching final result cannot certify a toolchain that changed during
# verification. Recheck both the PATH resolution and the binary contents.
for command_name in git rustc cargo rustfmt; do
  current="$(readlink -f -- "$(command -v -- "$command_name")")"
  if [[ "$current" != "${host_tool_paths[$command_name]}" || ! -f "$current" ]]; then
    echo "rust FSM blocked: host tool path changed: $command_name" >&2
    exit 70
  fi
  digest="$(sha256sum -- "$current")"
  if [[ "${digest%% *}" != "${host_tool_digests[$command_name]}" ]]; then
    echo "rust FSM blocked: host tool changed during execution: $command_name" >&2
    exit 70
  fi
done

after="$(sha256sum -- "${files[@]}")"
if [[ "$before" != "$after" || "$(git rev-parse HEAD)" != "$expected" ||
      -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'rust FSM blocked: inputs or repository changed during verification' >&2
  exit 70
fi
printf 'RUST_FSM_HOST_CHECKS_PASSED_HEAD=%s\n' "$expected"
