# Bounded FSM reference model — Rust migration stage 1

This dependency-free Rust crate models the Oreslang design-pattern FSM proposal
without Python. It is an executable **host-only** contract, not Oreslang guest
execution, native AOT, actor isolation, compiler acceptance or backend parity.

The model explicitly bounds state/event/rule cardinalities, version/generation,
store capacity, physical layout lanes and outbox. It covers a pure Symbol reducer,
three layout representations (AoS, SoA, AoSoA), generation- and
incarnation-fenced handles, failed-guard no-ops, ordered action admission,
borrow/relayout exclusion and commit-before-outbox emission. The source-contract
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
