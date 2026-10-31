# Bounded FSM reference model — Rust migration stage 1

This dependency-free Rust crate models the Oreslang design-pattern FSM proposal
without Python. It is an executable **host-only** contract, not Oreslang guest
execution, native AOT, actor isolation, compiler acceptance or backend parity.

The model explicitly bounds state/event/rule cardinalities, version/generation,
store capacity, physical layout lanes and outbox. It covers a pure Symbol reducer,
three layout representations (AoS, SoA, AoSoA), generation- and
incarnation-fenced handles, failed-guard no-ops, ordered action admission,
borrow/relayout exclusion, non-cloneable public store identity, and staged
commit-before-outbox emission. Precommit fault-injection tests live inside the
crate's **private** unit-test module; they do not expose access to uncommitted
handles or staged stores to public API consumers. The source-contract test checks the small illustrative `examples/fsm/01-symbol-reducer.ores`
transition table, not its parsing or executable semantics.

```sh
cargo fmt --manifest-path tools/fsm-model/Cargo.toml -- --check
cargo clippy --manifest-path tools/fsm-model/Cargo.toml --locked --offline --all-targets -- -D warnings
cargo test --manifest-path tools/fsm-model/Cargo.toml --locked --offline --all-targets
cargo test --manifest-path tools/fsm-model/Cargo.toml --locked --offline --doc
```

The remaining four Python FSM tests are retained until independent parity
review verifies *all* legacy fault-injection, bounded random traces, active
borrows and mutation failure cases. Do **not** remove them or classify model
tests as native .ores checks yet. See issue #10.

## Coverage and release guard

| Existing Python FSM category | Rust stage 1 | Limit |
| --- | --- | --- |
| Closed Symbol rule admission and duplicate edges | Covered by tests | Host model only |
| 781 traces × three layouts | Covered by tests | No guest compiler |
| ECS interleaving and layout relocation | Covered by tests | Sequential, not parallel |
| Generation retirement, store recreation and stale handles | Covered by tests | Issuer IDs are model-only, not authentication |
| Bounded outbox, guard, version overflow | Covered by tests | No external exactly-once delivery |
| Borrow exclusion and panic-safe cleanup | Covered by tests | Not Oreslang borrow checking |
| Simulated mutation/relayout failure atomicity | Private unit-test fault injection | Not native crash durability |
| Mutation-level monkeypatch fault coverage | **Partial** | No direct equivalent of each Python fault patch |
| Full 260-step randomized oracle parity | **Covered in source** | Separate logical-state map and ordered action oracle, pending Rust test execution |
| Unicode surrogate admission | Semantically constrained by Rust strings | Rust strings cannot contain surrogate scalar values |
| Exact native pattern execution and AOT parity | **Not executed** | Requires independently pinned compiler and real runner |

**Promotion rules:** Keep all Python reference files and the legacy CI step until
the Rust suite is compiled and executed, the remaining differential and
fault-injection gaps are filled, and a reviewer compares behavior case-by-case.
Even a green Rust suite would not close issue #8: it is a host-model receipt,
not real Oreslang guest execution. No cross-organization source transfer or
required status-context change is made here.


## Exact-head offline verification on a trusted Linux runner

When GitHub Actions fails before job admission, a trusted Linux machine with
Rust/Cargo/Clippy/rustfmt preinstalled can run the **same** gates. Read the
exact commit SHA from the PR's GitHub head metadata using a trusted connection
and independently confirm the checkout SHA. Do not derive an independent pin
from `git rev-parse HEAD` on the unverified checkout.

```bash
export ORESLANG_EXPECTED_HEAD='<independently-verified-40-hex-PR-head>'
bash scripts/verify-fsm-rust-host.sh --execute
```

This host gate requires a clean top-level checkout matching the exact expected
commit; rejects bad arguments, missing/malformed pins, dirty trees, missing
Rust tools and missing/symlinked core fixtures; runs `cargo fmt --check`,
`cargo clippy --offline --locked --all-targets -- -D warnings`,
`cargo test --offline --locked --all-targets` **and** `cargo test --doc`.
The separate documentation test run proves that attempting to clone a
`LayoutStore` fails at compile time in safe external Rust code and checks that
public clients cannot access staged transaction fault-injection hooks. It uses a separate temporary
Cargo target directory and checks that the source files and Git tree remain
unchanged. Only then does it emit the `RUST_FSM_HOST_CHECKS_PASSED_HEAD`
marker. Record raw command logs, exit code, Rust toolchain versions and exact
source/object digests for review. The marker is **self-reported local output,
not a trustworthy remote execution receipt**.

**As of 2026-10-31:** the exact copy of this shell gate (Git blob
`9ef52c49d378105070fb8a03b59d4c232d0cd806`) passed `bash -n` and
negative admission tests for missing arguments, missing pin, invalid checkout
and missing Rust toolchain; those failures returned 64/69 as designed.
The Rust tests, Rust formatter, Clippy and real Oreslang execution have still
**NOT EXECUTED**. Multiple source-free alternate-organization canaries failed
before executing any steps. Do not promote PR #12 on this evidence alone.
