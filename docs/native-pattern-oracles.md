# Native pattern output-oracle proposal (2026-10-31)

**Evidence status: PROPOSED_EXPECTATIONS / NOT_EXECUTED.**

This folder contains 20 newline-terminated candidate stdout fixtures
(`tests/native-pattern-oracles/*.stdout`), one for each independent
`patterns/*.ores` sample. Expected output was derived by source inspection,
**not** by successfully executing an Oreslang compiler. The 2026-10-07
historical compiler probe documented unsupported legacy record shapes
(`obj{...}`), Visitor ownership, and ECS/SoA mutation; these are still
blockers. Do not edit the oracles to match a failing implementation without
reviewing semantics. Never call these fixtures runtime proof.

## Opt-in real-compiler gate

```bash
ORESLANG_BIN=/absolute/path/to/trusted/oreslang \
ORESLANG_COMPILER_SHA256='<independently-pinned-64-hex-sha256>' \
bash scripts/check-native-patterns.sh --execute
```

The script requires exactly 20 `.ores` files, exactly 20 `.stdout`
fixtures, an absolute executable path and an independently supplied binary
digest. It rejects symlinked or escaping fixture paths, hashes the compiler
before checking and again before running each example, isolates ambient
environment variables, applies 60-second check/run timeouts and compares
stdout byte-for-byte. A mismatch, missing fixture, compiler failure, changed
compiler hash or timeout is a hard failure. It does not claim to sandbox an
untrusted compiler binary or authenticate its build provenance. Execute
only a trusted compiler from a controlled, non-writable location.

The generated success marker `NATIVE_PATTERN_OUTPUT_ORACLES_MATCHED=20`
means only that the chosen executable returned matching stdout for the
chosen files in that invocation. Independently record the source Git tree,
each source/oracle SHA, compiler commit/tree and executable SHA-256,
toolchain, command line, actual GitHub run/job/steps, stderr and real
test outputs before promoting. A test double can print these same strings,
so the marker alone is never an acceptable native execution receipt.

## Candidate stdout corpus

| Pattern | Last expected observation | Main review risk |
| --- | --- | --- |
| Strategy | `90` | integer pricing semantics |
| Observer | `order.created` | callback ordering and borrowed captures |
| Command | `115` | legacy `obj` / command ADT admission |
| State | `13` | record/reducer ownership |
| Visitor | `(2 + 3)` | moved value reused in multiple operations |
| Chain | `401` | `Option` and record syntax |
| Decorator | `42` | closure capture and effect ordering |
| Proxy | `403 forbidden` | policy checked before service |
| Facade | `label:book-1` | host I/O and sequential effects |
| Adapter | `true` | boolean rendering and records |
| Composite | `60` | closure lifetime and call chain |
| Factory | `12` | legacy `obj` and constructors |
| Builder | `3` | immutable record updates |
| Dependency injection | `user:42` | callable capture |
| Singleton | `oreslang-design-patterns` | immutable module scope |
| ECS | `35` | mutable component storage and bounds |
| SoA | `28` | mutable column borrows |
| Option map/flat_map | `5` | `Option` semantics and inference |
| Memoization | `169` | single-owner captured mutable cache |
| Interceptor | `ran:save_user` | intercept ordering and typed callable |

## Runner contract test

```bash
bash scripts/test-native-pattern-runner.sh
```

This uses an isolated temporary project, a fake `oreslang` command,
paths containing spaces and intentionally wrong hashes/outputs/failures.
The workflow executes only this **test-double** harness, not the
`--execute` native compiler gate. Do not add a fake compiler artifact
to production receipts. Keep the real gate manual/opt-in until pinned
compiler-backed CI and source export approvals exist.

## Promotion

1. Review each `.ores` example against the pinned compiler grammar and
   fix record/ownership incompatibilities; do not mask compiler failures.
2. Run the pinned real compiler gate, collect raw command and output
   artifacts and independently verify the compiler binary provenance.
3. Add compile-fail ownership/borrow/cancellation fixtures, particularly
   Observer, Command, State, Visitor, ECS/SoA and Memoization.
4. Repeat separately for Java/GraalVM, LLVM, Wasm, .NET and Forge where
   available; keep missing backend claims `NOT_EXECUTED`.
