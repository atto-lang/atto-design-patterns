> **AI agent instructions (organization-wide):** Before working on code, issues, or pull requests, read and follow the [organization `AGENTS.md`](https://github.com/ores-truffle-oreslang/.github/blob/main/AGENTS.md), including its **merge-first stealth-development policy**. Honor any repository-local `AGENTS.md`, explicit holds, and GitHub-enforced rules.

# Oreslang Design Patterns

## AttoLang migration and current documentation (2026-11-18)

**AttoLang (formerly Oreslang)** is the current language brand. This `ores-truffle-oreslang/oreslang-design-patterns` checkout is a historical organization location; the corresponding new-home project is **[atto-lang/atto-design-patterns](https://github.com/atto-lang/atto-design-patterns)**. Do not assume a same-named project has identical Git commits, issues, PRs, Actions or feature status without checking exact history. Keep the historical example commands below for this checkout until independently validated replacements exist.

**Source of truth:** [atto-lang/atto-spec](https://github.com/atto-lang/atto-spec) defines current and proposed language semantics; [atto-platform-conformance](https://github.com/atto-lang/atto-platform-conformance) provides portable positive/negative guest tests; [atto-common-source](https://github.com/atto-lang/atto-common-source) owns shared portable `.atto` code. New source aims for `snake_case` callables, `borrow!`/`take!`/`copy!`/`copy!!`/`share!`, [implicit borrowing](https://github.com/atto-lang/atto-spec/blob/main/language/implicit-argument-borrow-v1.md), [file/module constants with guarded one-time `os.read_env`](https://github.com/atto-lang/atto-spec/blob/main/language/file-module-const-v1.md), and [bitwise `<<<`/`>>>`/`ashr` distinct from stream `<<`/`>>`](https://github.com/atto-lang/atto-spec/blob/main/language/bitwise-and-stream-operators-v1.md). These are spec targets, not guaranteed executable features of this legacy repository.

Preserve legacy `.ores` paths, CLI/package/ABI names and wire formats where implemented. No Python support scripts, CI or tests; prefer Rust helper tooling. Document exact compiler SHA/tree, toolchain, executed guest positive/negative checks and unsupported/failed/not-executed outcomes. Host-only or zero-step CI cannot certify feature or backend parity.

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


## 2026-10-30 audit and native evidence boundaries

The latest source/CI findings, open P0 migration blockers, exact native verification
order and the opt-in SHA-256-pinned FSM execution oracle are recorded in
[docs/design-pattern-hardening-2026-10-30.md](docs/design-pattern-hardening-2026-10-30.md).
`scripts/check-fsm-native.sh --execute` now requires the independently pinned
`ORESLANG_COMPILER_SHA256`, an independently pinned clean `ORESLANG_EXPECTED_HEAD`,
a 60-second timeout per compiler step, post-run binary/source integrity and
exact six-line guest stdout. Its fake-compiler
self-test remains a **runner contract test**, never native Oreslang evidence.
Neither these checks nor the Rust receipt inspector certify compiler provenance.

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
