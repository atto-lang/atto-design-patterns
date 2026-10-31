#!/usr/bin/env bash
# Self-contained shell contract test. Test doubles do NOT compile Rust.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/fsm-rust-gate.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
work="$tmp/project with spaces"
bin="$tmp/fake tools"
mkdir -p "$work/scripts" "$work/tools/fsm-model/src" "$work/tools/fsm-model/tests" "$work/examples/fsm" "$bin"
cp "$root/scripts/verify-fsm-rust-host.sh" "$work/scripts/verify-fsm-rust-host.sh"
for f in Cargo.toml Cargo.lock; do printf 'dummy\n' > "$work/tools/fsm-model/$f"; done
for f in src/lib.rs tests/reference.rs; do printf 'dummy\n' > "$work/tools/fsm-model/$f"; done
printf 'dummy\n' > "$work/examples/fsm/01-symbol-reducer.ores"
(
  cd "$work"
  git init -q
  git -c user.name=Test -c user.email=test@example.invalid add .
  git -c user.name=Test -c user.email=test@example.invalid commit -qm 'synthetic fixtures, not source repo'
)
head="$(git -C "$work" rev-parse HEAD)"
cat > "$bin/cargo" <<'CARGO'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then echo 'cargo fake-tool 0'; exit 0; fi
printf '%s\n' "$1" >> "$FSM_TEST_LOG"
if [[ "${FSM_TEST_FAIL:-}" == "$1" ]]; then exit 45; fi
if [[ "${FSM_TEST_MUTATE:-}" == "$1" ]]; then printf 'injected mutation\n' >> tools/fsm-model/src/lib.rs; fi
if [[ "${FSM_TEST_MUTATE_TOOL:-}" == last-doc-test && " $* " == *" --doc "* ]]; then
  printf '\n# injected compiler wrapper mutation after final stage\n' >> "$0"
fi
CARGO
cat > "$bin/rustc" <<'RUSTC'
#!/usr/bin/env bash
echo 'rustc fake-tool 0'
RUSTC
cat > "$bin/rustfmt" <<'RUSTFMT'
#!/usr/bin/env bash
echo 'rustfmt fake-tool 0'
RUSTFMT
chmod +x "$bin"/*
export PATH="$bin:$PATH" FSM_TEST_LOG="$tmp/stages.log"
check_status() {
  local expected_status="$1"
  shift
  local status=0
  (cd "$work" && "$@" > "$tmp/output.log" 2>&1) || status=$?
  if [[ "$status" -ne "$expected_status" ]]; then
    echo "unexpected status: expected $expected_status got $status" >&2
    cat "$tmp/output.log" >&2
    exit 1
  fi
}

check_status 64 bash "$work/scripts/verify-fsm-rust-host.sh"
check_status 69 env ORESLANG_EXPECTED_HEAD=invalid bash "$work/scripts/verify-fsm-rust-host.sh" --execute
check_status 69 env ORESLANG_EXPECTED_HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bash "$work/scripts/verify-fsm-rust-host.sh" --execute

: > "$FSM_TEST_LOG"
check_status 69 env ORESLANG_EXPECTED_HEAD="$head" RUSTC_WRAPPER=/bin/true bash "$work/scripts/verify-fsm-rust-host.sh" --execute
test ! -s "$FSM_TEST_LOG"
grep -Fq "external toolchain/config override: RUSTC_WRAPPER" "$tmp/output.log"

: > "$FSM_TEST_LOG"
check_status 69 env ORESLANG_EXPECTED_HEAD="$head" CARGO_HOME="$tmp/rogue-home" bash "$work/scripts/verify-fsm-rust-host.sh" --execute
test ! -s "$FSM_TEST_LOG"
grep -Fq "external toolchain/config override: CARGO_HOME" "$tmp/output.log"

# No Git provenance or Rust build configuration may come from ambient vars.
# Rejection must happen before executing even a fake Cargo stage.
for entry in \
  'GIT_INDEX_FILE=rogue-index' \
  'GIT_CONFIG_COUNT=1' \
  'CARGO_BUILD_TARGET=malicious-target' \
  'CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS=-Cpanic=abort' \
  'RUSTUP_TOOLCHAIN=unreviewed'; do
  : > "$FSM_TEST_LOG"
  check_status 69 env ORESLANG_EXPECTED_HEAD="$head" "$entry" bash "$work/scripts/verify-fsm-rust-host.sh" --execute
  grep -Fq "external Git/Cargo/rustup override: ${entry%%=*}" "$tmp/output.log"
  test ! -s "$FSM_TEST_LOG"
done
: > "$FSM_TEST_LOG"
check_status 0 env ORESLANG_EXPECTED_HEAD="$head" bash "$work/scripts/verify-fsm-rust-host.sh" --execute
grep -Fxq "RUST_FSM_HOST_CHECKS_PASSED_HEAD=$head" "$tmp/output.log"
cat > "$tmp/stages.expected" <<'EXPECTED'
fmt
clippy
test
test
EXPECTED
cmp -s -- "$tmp/stages.expected" "$FSM_TEST_LOG"

: > "$FSM_TEST_LOG"
check_status 45 env ORESLANG_EXPECTED_HEAD="$head" FSM_TEST_FAIL=clippy bash "$work/scripts/verify-fsm-rust-host.sh" --execute
if grep -q 'RUST_FSM_HOST_CHECKS_PASSED' "$tmp/output.log"; then exit 1; fi

: > "$FSM_TEST_LOG"
check_status 70 env ORESLANG_EXPECTED_HEAD="$head" FSM_TEST_MUTATE=test bash "$work/scripts/verify-fsm-rust-host.sh" --execute
if grep -q 'RUST_FSM_HOST_CHECKS_PASSED' "$tmp/output.log"; then exit 1; fi
# Reset synthetic fixture after mutation.
(cd "$work" && git restore tools/fsm-model/src/lib.rs)

printf 'dirty fixture\n' >> "$work/examples/fsm/01-symbol-reducer.ores"
: > "$FSM_TEST_LOG"
check_status 69 env ORESLANG_EXPECTED_HEAD="$head" bash "$work/scripts/verify-fsm-rust-host.sh" --execute
test ! -s "$FSM_TEST_LOG"
(cd "$work" && git restore examples/fsm/01-symbol-reducer.ores)

# The test double alters its own bytes only after the final Cargo doc-test
# invocation. A success marker must not be emitted for changed toolchain bytes.
: > "$FSM_TEST_LOG"
check_status 70 env ORESLANG_EXPECTED_HEAD="$head" FSM_TEST_MUTATE_TOOL=last-doc-test bash "$work/scripts/verify-fsm-rust-host.sh" --execute
grep -Fq 'host tool changed during execution: cargo' "$tmp/output.log"
if grep -q 'RUST_FSM_HOST_CHECKS_PASSED' "$tmp/output.log"; then exit 1; fi
cmp -s -- "$tmp/stages.expected" "$FSM_TEST_LOG"

mv "$work/tools/fsm-model/Cargo.lock" "$tmp/Cargo.lock"
: > "$FSM_TEST_LOG"
check_status 69 env ORESLANG_EXPECTED_HEAD="$head" bash "$work/scripts/verify-fsm-rust-host.sh" --execute
test ! -s "$FSM_TEST_LOG"

printf '%s\n' 'fsm rust host verification shell contracts: PASS (fake tools only)'
