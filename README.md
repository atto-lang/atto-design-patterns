# Oreslang Design Patterns

Twenty design-pattern implementations written in native Oreslang.

The goal is not to force every classic object-oriented pattern into class-heavy code. The examples intentionally choose the smallest Oreslang formulation that preserves each pattern's intent: higher-order functions where functions are the abstraction, pattern matching where double dispatch would be ceremony, modules for facades/singletons, and flat data/system loops for data-oriented patterns.

## Patterns

| # | Pattern | Primary Oreslang formulation |
|---|---|---|
| 01 | Strategy | higher-order function |
| 02 | Observer | callback/event channel |
| 03 | Command | command as data + interpreter |
| 04 | State | pure reducer |
| 05 | Visitor | nominal variants + pattern matching |
| 06 | Chain of Responsibility | Option-returning handler chain |
| 07 | Decorator | function composition |
| 08 | Proxy | higher-order access wrapper |
| 09 | Facade | module facade |
| 10 | Adapter | typed record transform |
| 11 | Composite | uniform function-valued nodes |
| 12 | Factory | pure constructor function |
| 13 | Builder | immutable builder state |
| 14 | Dependency Injection | explicit function dependencies |
| 15 | Singleton | immutable module singleton |
| 16 | ECS | entity IDs + component data + systems |
| 17 | Structure of Arrays | parallel typed arrays |
| 18 | Monad / Functor | Option map / flat_map composition |
| 19 | Memoization | stateful closure cache |
| 20 | Interceptor / Pointcut | predicate + interceptor composition |

## Repository rules

- Pattern implementations are Oreslang, not Java adapters.
- Each example is self-contained and independently checkable.
- Prefer current Oreslang syntax: callable declarations use `:` or `->`; executable branches/lambdas use `->`; `=>` stays type-level.
- Prefer static records/structs over dynamic object shapes. Open-ended keyed data belongs in `Map<K,V>`.
- Nested behavior is represented with local function expressions, not nested callable declarations.
- The examples double as compiler/type-checker regression material.

## Check

With the canonical Oreslang CLI on `PATH`:

```bash
bash scripts/check-all.sh
```

The script checks each pattern as a separate source unit so every file can own a `main` routine without cross-example symbol collisions.

See [LANGUAGE_FINDINGS.md](LANGUAGE_FINDINGS.md) for language-design pressure exposed by the examples.

## 2026-10-06 compiler PR compatibility

For the latest 10 upstream Oreslang compiler PRs, see [docs/compiler-pr-sync.md](docs/compiler-pr-sync.md). These features remain unmerged; this repo preserves its existing compiler reference and defaults until exact-SHA integration evidence is available.

## Runner CI and native-pattern coverage

The `Test runner contracts` workflow checks shell syntax and uses a compiler
test double to prove independent, ordered checks, repository-root execution,
paths with spaces, exact failure propagation, and rejection of an empty pattern
directory. `ORESLANG_BIN` can select an explicit CLI executable. The workflow
uses read-only permissions and no secrets.

This runner gate does not claim that all 20 patterns compile. The 2026-10-07
probe against compiler `5ffc52d9297d175307094d530293c69f1cafc7cd` found removed
`obj{...}` syntax, reuse of moved `expr` in Visitor, and readonly collection
mutation in ECS/SoA. Migrate to `infer struct`, explicit borrowing, and owned
mutable buffers before pinning that compiler for complete native pattern CI.


## Proposed native stdout oracles for all 20 patterns

The repo now has 20 candidate per-pattern stdout fixtures under
`tests/native-pattern-oracles/` and an opt-in SHA-256-pinned exact-output gate
at `scripts/check-native-patterns.sh --execute`. This gate now
also requires an independently verified exact `ORESLANG_EXPECTED_HEAD`
(40 lowercase hexadecimal characters) and a clean checkout; see
[docs/native-pattern-oracles.md](docs/native-pattern-oracles.md) for the
required compiler provenance, negative ownership checks and strict
`NOT_EXECUTED` limitations. The CI workflow runs only a **fake-compiler
runner contract** for this gate; actual native execution is blocked until a
trusted real compiler and functioning runner are available.

## Draft FSM alternatives: Symbol reducers vs ECS / layout stores

A proposed follow-on to pattern 04 (State), 16 (ECS) and 17 (SoA) is documented in
[docs/fsm-alternatives.md](docs/fsm-alternatives.md). It compares a closed
Symbol-driven pure reducer/static transition table with a data-oriented FSM
system using ECS entity IDs and one selectable AoS, SoA or AoSoA physical
storage layout. Neither design requires actors; optional stdlib/otp/gen_statem
may wrap the same reducer over an actor in a later PR.

The accompanying [bounded Python reference model](formal/fsm_reference.py),
[exhaustive small-trace tests](formal/test_fsm_reference.py) and
[adversarial hardening regressions](formal/test_fsm_hardening.py) exercise
transition parity, failed-guard no-op semantics, bounded outbox admission,
store-incarnation and generation fencing, swap-delete, injected relayout failure,
tail lanes and borrow/relayout exclusion:

~~~bash
python3 -m unittest discover -s formal -p 'test_fsm_*.py' -v
~~~

This is an abstract executable conformance model, **not** proof of the real
Oreslang compiler, an actor runtime, or native SoA/AoSoA codegen. The guest
syntax in the RFC is illustrative until exact-head compiler verification.
