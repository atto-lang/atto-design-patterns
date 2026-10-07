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
