# Bounded FSM reference model — Rust migration stage 1

This dependency-free Rust crate models the Oreslang design-pattern FSM proposal
without Python. It is an executable **host-only** contract, not Oreslang guest
execution, native AOT, actor isolation, compiler acceptance or backend parity.

The model explicitly bounds state/event/rule cardinalities, version/generation,
store capacity, physical layout lanes and outbox. It covers a pure Symbol reducer,
three layout representations (AoS, SoA, AoSoA), generation- and
incarnation-fenced handles, failed-guard no-ops, ordered action admission,
borrow/relayout exclusion and staged commit-before-outbox emission, with precommit fault-injection regression tests. The source-contract
test checks the small illustrative `examples/fsm/01-symbol-reducer.ores`
transition table, not its parsing or executable semantics.

```sh
cargo fmt --manifest-path tools/fsm-model/Cargo.toml -- --check
cargo clippy --manifest-path tools/fsm-model/Cargo.toml --locked --offline --all-targets -- -D warnings
cargo test --manifest-path tools/fsm-model/Cargo.toml --locked --offline
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
| Simulated mutation/relayout failure atomicity | Precommit injection tests | Not native crash durability |
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
