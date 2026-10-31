# Design-pattern audit and native-evidence gates (2026-10-30)

Base inspected: `main` at `59f47ba359e645a3e209db02e32c4a43451f3a27`.
This is a source/CI audit, **not** a native Oreslang compiler or backend certification.

## Verified inventory and outstanding blockers

- 20 self-contained `patterns/*.ores` examples exist. The sample runner uses a fake CLI; it proves path ordering, failure propagation and script behavior, **not** successful parsing, type checking or execution on a real compiler.
- Five tracked Python files under `formal/` and their invocation in `.github/workflows/runner.yml` violate the new first-party Rust-only test-tooling policy. Track full behavioral migration and removal under [issue #10](https://github.com/ores-truffle-oreslang/oreslang-design-patterns/issues/10). The Rust rollout receipt checker is not an FSM-model replacement. **Do not remove reference tests or silently mark them green before equivalent Rust cases exist.**
- The corpus uses legacy `obj{...}` construction in Command/State/Chain/Adapter/Factory/Builder, a potentially consumed Visitor value reused in `pretty`, and mutable collection/borrow contracts requiring clarification in ECS/SoA. The historical compiler probe and [issue #8](https://github.com/ores-truffle-oreslang/oreslang-design-patterns/issues/8) identify these as pending exact compiler revision and execution tests.
- Latest examined `main` workflow run `40447099913` and receipt-checker run `40441831102` report failing jobs but no executed steps in the job-step response; this is **runner/admission/setup-unresolved**, not evidence that assertions ran and failed. Do not count zero-step runs as test passes or implementation failures.

## Bounded FSM execution gate

The check-only command still checks a single illustrative `.ores` FSM fixture:

```bash
ORESLANG_BIN=/absolute/trusted/compiler bash scripts/check-fsm-native.sh
```

For `--execute`, set a **previously independently established** lowercase 64-digit SHA-256 digest of the chosen compiler executable. The command hashes the executable before the check and again immediately before the run, isolates the compiler's environment, and requires **byte-exact** six-line stdout:

```text
#running
#paused
#running
#done
#idle
#rejected
```

Example invocation, with no assumed digest:

```bash
ORESLANG_BIN=/absolute/trusted/compiler \\
ORESLANG_COMPILER_SHA256='<trusted-64-hex-sha256>' \\
bash scripts/check-fsm-native.sh --execute
```

The program must be on a trusted, non-writable path to rule out concurrent binary replacement. This digest is a binary integrity check, **not** a substitute for binding a Git compiler commit/tree, build provenance, toolchain, source fixture digest, executed run/job/steps, and reviewed output artifacts. An executable returning the expected text can still be a test double. Neither this script nor its self-tests authenticate provenance or certify native semantics.

## Minimum promotion order

1. Replace all five Python FSM model/test files with behaviorally equivalent Rust tests, preserving deterministic oracle, negative/fault-injection, incarnation/generation, outbox, borrow, relayout and bounded-trace coverage. Remove the Python CI invocation only after equivalent Rust assertions execute.
2. Pin source fixture Git blobs and independently verified compiler Git SHA/tree, toolchain and binary SHA-256; update source examples to a grammar actually supported by the pinned compiler. Do not conflate parser acceptance with guest execution.
3. Execute every one of the 20 pattern programs with a per-file output oracle; add negative ownership/cancellation tests for Observer, Command, State, Visitor, ECS/SoA, Memoization, and any actor-backed variant. Keep scalar/ownership checks and physical runtime quiescence separately observed.
4. Record checks for Java/GraalVM, LLVM, Wasm, .NET and Forge independently as supported. Unsupported/unexecuted backends are `NOT_EXECUTED`, not green parity.
5. Confirm real runner admission and nonzero executed steps, then independently check raw artifacts and receipt issuer before promotion. If source-org minutes are exhausted, a private cross-org runner/mirror requires explicit authorization and source-blob SHA checks; no private mirror or cross-org export is enabled here.

## Patch scope

This hardening adds an exact stdout oracle and digest requirement to the **opt-in FSM execute path**, expands its test-double negative cases, and rejects receipts without a terminal LF. It does not change pattern examples, compiler pins, required status contexts, permissions, exporter configuration, or the source default branch.
