# Language findings from the pattern corpus

This repository is intentionally a language-design stress test as much as a pattern catalog.

## Keep the language small by collapsing patterns into features

1. **Strategy, Decorator, Proxy, DI, Chain, and Interceptor** should remain cheap with first-class typed functions. Oreslang should not require a class/interface pair when a callable value is enough.
2. **Visitor and State** become substantially smaller with exhaustive pattern matching, sum types, and typed records.
3. **Facade and safe Singleton** map naturally to modules. Avoid adding a special singleton construct.
4. **Command** is clearest as plain typed data plus an interpreter when queueing, serialization, replay, or undo matter.
5. **ECS and SoA** should stay data-first. Class/object allocation should never be required for hot component loops.

## Standard-library pressure

The examples become materially shorter if the standard library provides:

- `Option.map`, `Option.flat_map`, `Result.map`, and `Result.flat_map`;
- `compose` / `pipe` helpers for typed callables;
- stable `Map<K,V>` lookup/update APIs for general memoization;
- stream/event-channel primitives for Observer;
- collection combinators such as `map`, `filter`, `fold`, `zip`, and indexed iteration;
- an ergonomic `memoize` helper restricted to functions whose cache semantics are sound.

## Syntax pressure

Useful simplifications to preserve or pursue:

- keep both concise record values and nominal classes; do not make one replace the other;
- allow local compile-time `struct` / `interface` declarations where they help a single callable, while keeping classes/modules/namespaces static;
- keep local executable behavior as function expressions, not nested declarations;
- provide concise immutable record update/spread syntax so reducers and builders do not repeat every field;
- keep spread usable both for collections and call arguments;
- keep executable arrows distinct from type-level arrows;
- make sum/data-enum declarations concise enough that Command/State/Visitor do not fall back to string tags.

## AOT / optimization pressure

- Avoid dynamic structs for modeling ordinary application data; static shapes are friendlier to AOT analysis and optimization.
- SoA/ECS code benefits from compiler-visible contiguous arrays, read/write effect sets, vectorization metadata, and CPU/GPU placement.
- Pure reducers, strategies, adapters, and functor/monad combinators are optimization-friendly and should be easy for the compiler to inline.
- Memoization must be explicit about key equality, cache lifetime, ownership, and concurrency; hidden global caches would undermine actor isolation.

## AOP pressure

The Interceptor example deliberately uses explicit composition first. Annotation/pointcut sugar is worthwhile only if it lowers to ordinary, inspectable Oreslang metadata and callable composition rather than introducing a second hidden execution model.
