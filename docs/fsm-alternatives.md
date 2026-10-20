# FSM alternatives for Oreslang: symbols, reducers, tables, ECS and layout stores

**Status: draft RFC / example-design contract (2026-10-19).** This does not assert that these guest-source APIs compile on Java, LLVM or Rust today. Existing pattern 04 is a reducer with string actions; pattern 16 demonstrates ECS; pattern 17 demonstrates SoA. The intent here is to unify their transition semantics without making Oreslang an actor-only or game-specific language.

## Decision requested

Prototype two primary families against one observable transition contract:

1. **A: typed symbol-driven pure reducer / sparse static transition table.** A normal function computes a new machine value and a bounded ordered list of declared effects. A hand-authored branch/switch or build-time generated sparse table is a choice of lowering, not different semantics. Ideal for one instance, workflows, protocol handlers, actors and replay.
2. **B: batch FSM system over ECS IDs + a layout-selectable store.** A hot loop applies the *same* checked transitions to multiple independent entities. Physical storage is selected once from AoS, SoA or AoSoA; ECS is the composition/query/execution model, **not** a fourth layout. Ideal for high-cardinality telemetry, simulations and schedulers.

Defer full hierarchical/orthogonal statecharts to an optional userland library atop the same transition kernel; avoid adding a new language keyword or a separate FSM runtime. An OTP-style gen_statem belongs in optional stdlib/otp over actor, never freestanding core. A plain reducer or batch FSM needs **no actor**.

## Canonical semantics for both families (v0)

- State/event/action tags are immutable logical Symbols: #idle, #running, #start, #stop, etc. Symbol equality uses canonical (kind,key), **not** pointer/handle identity. Only declared symbols are eligible in a closed AOT machine. A Symbol is **not** a capability, secret or namespace authorization.
- Each rule has (source_state, event, target_state, guard_id, action_ids). Compile-time tooling rejects duplicate (source_state,event) keys, unknown states/events/action IDs and ambiguous priorities. Multiple guarded edges per pair are deferred pending provable disjointness or an explicit total priority order.
- The transition kernel is total: unsupported (state,event), guard=false or rejected admission returns a typed Rejected result **without changing state/version or emitting effects**; no implicit self-transition silently counted as successful. Successful transitions increment a checked version and yield effects in deterministic declared order. Version overflow rejects before writing.
- Guards are pure, bounded, non-suspending and cannot mutate state, allocate unexpectedly, call host/FFI or consult wall time. Side effects are descriptions only; dispatch separately *after* committed state. Exactly-once external delivery requires an outbox/idempotency policy and is NOT guaranteed by a reducer.
- A tick/batch consumes events in a specified order **per entity**. Independent entity streams may be interleaved if no cross-entity effects/shared writable state exist. Ordering-dependent global effects require a separate deterministic merge order; parallel ECS processing may not silently reorder them.
- Explicit fixed maximum states, events, rules, actions, queued events, instance count and guard cost for strict real-time admission. Unknown WCET, dynamic dispatch, dynamic table growth, reflection, time-dependent guards and unbounded retries must fail strict AOT/RT admission.
- Closed-world compile-time registration exports only reachable symbols/rules; no runtime reflection or hidden registry roots. User-defined names in a closed machine are module-private by default; any cross-module export is explicit.
- For actor use, actor-owned state remains sealed and subject to normal mailbox/await/CONTROL rules. Stateless reducer kernels work in a serial actor callback or ordinary code. ECS workers must not bypass actor isolation or acquire privileged CONTROL access.

### Alternative A: symbol reducer and table (illustrative future syntax, not checked)

~~~ores
define symbol #idle;
define symbol #running;
define symbol #start;
define symbol #stop;

type Machine = struct{state: Symbol, version: int};
type Event = struct{kind: Symbol};

// A generated table or an exhaustive switch can implement exactly this operation.
fnc step(Machine current, Event event) -> Result<Transition, TransitionError>
    if current.state == #idle and event.kind == #start then
        return Ok(Transition{next: #running, action: #started});
    else
        if current.state == #running and event.kind == #stop then
            return Ok(Transition{next: #idle, action: #stopped});
        else
            return Err(TransitionError.Rejected);
        fi
    fi
end
~~~

The names/types and construction forms above are *proposal notation*, NOT evidence that a compiler supports this entire snippet. The current checked state example at patterns/04-state.ores still uses string actions and legacy record construction. Keep implementation in userland first; the only proposed core dependency is existing immutable Symbol value/equality plus Result/Option and static exhaustive pattern matching where supported.

### Alternative B: ECS system and single authoritative layout store (pseudocode)

~~~text
Store<MachineRow>(layout = SoA | AoS | AoSoA(lanes=4), capacity=N)
  handle = store.insert(state=#idle, version=0)  // owner+slot+generation
  for (entity, event) in bounded_ordered_events:
      with store.write(entity, fields={state,version}) as row:
          result = compiled_step(row.state, event)   // pure bounded kernel
          if result is Accepted:
              validate_version_and_commit(row, result)
              queue_declared_effects(entity, result) // bounded outbox
  dispatch_effects_after_commit()
~~~

The API above is aspirational: there is no claim that field-loans, dynamic layout selection or the exact Store surface compile today.

## Physical layout tradeoffs (one live representation)

| Plan | Advantages | Costs / admission risk | Fit |
| --- | --- | --- | --- |
| AoS (array of records) | Locality for per-entity multi-field transitions; simple debugging | Poor locality when scanning only state tags | Small/branchy workflows |
| SoA (one dense column per field) | Fast state-tag scans; SIMD-friendly filtering | More indirections for multi-field rule execution | Millions of homogeneous machines |
| AoSoA (fixed-size chunks of columns) | SIMD batches plus moderate per-entity locality | Padding/tail masks, chunk indexing, explicit lane width and alignment | Vectorized batches with chosen lanes |
| ECS + any layout | Query-based systems and disjoint read/write sets; data-first composition | Query/schedule determinism, archetype moves and component-lifetime fences | Systems acting on subsets of entities |

Use **one authoritative physical layout at a time**, never parallel AoS + SoA + AoSoA copies that must be kept synchronized. A relayout is an explicit quiescent relocation operation with stable logical handle slots, generational invalidation for deleted rows, and complete rollback on failure. Resolve entity handle to current dense index on every access. Changing dense index on swap-delete must not change surviving logical entity identity.

AoSoA constraints: lane count and alignment are configuration, not semantic identity; validate active-lane masks, avoid reading padding, handle partially filled final chunk, avoid vectorizing impure guards, and prevent unsafe raw column access across relocation/await. ECS component access should carry compile-time read/write declarations and runtime bounds for dynamic dispatch.

## Failure and isolation rules

1. Reject duplicate rules, invalid state/event IDs, unmatched guards, out-of-bounds entity IDs, wrong-owner/tenant handles, generation mismatch and stale handles after reuse.
2. Reject insert, delete, swap-delete or relayout while any live column/row loan exists. For an individual transition, require an exclusive loan for written fields and compatible read loans for other fields. No write loan may cross await or a scheduler/actor boundary.
3. Guard rejects / overflows / table misses are transactional: original machine state, version, row count and action queue are unchanged. A bounded outbox must reserve capacity before commit; if reserve fails, reject atomically.
4. A parallel ECS pass requires disjoint write sets *and* disjoint effect targets or an explicit ordering/atomicity contract. Separate actor arenas, isolation domains and generations remain enforced.
5. Hot reload publishes an immutable generation of rules; an in-flight turn pins its generation. Migration to new state IDs is an explicit checked operation; never reinterpret old indices as new state identities. No mutable global Symbol registry.

## Proposed placement and dependency boundary

| Layer | Belongs here | Must NOT go here |
| --- | --- | --- |
| freestanding core | Symbol identity/portable equality, closed enums/Result, bounds, ownership, static metadata | ECS scheduler, actor services, heap allocation, timers, registry, I/O |
| optional alloc | Bounded layout-store, explicit arena provider, SoA/AoSoA backing and safe relocation | Ambient allocator or unbounded hidden resizing |
| userland patterns | Pure reducer, generated tables, explicit batched loops, ECS adapter, statechart composition | Compiler-specific reflection/runtime magic |
| optional stdlib/otp | gen_statem actor behaviour wrapping reducer/table, mailbox/timer/CONTROL policies | Required dependency of core |
| compiler/static analysis | AOT table lowering, rule-exhaustiveness/overlap checks, borrow/effect/WCET admission | New FSM keyword or privileged runtime execution |

Cross-references: common-source/docs/SYMBOLS.md, common-source/docs/CORE_ALLOC_ACTOR_OTP_BOUNDARY_V1.md, source.java/formal/INVERTED_ARRAY_MODEL.md, common-source/docs/REALTIME_AOT_EXECUTION_PROFILES.md.

## Validation plan and evidence honesty

This draft ships a **stdlib-only Python executable bounded reference model** (formal/fsm_reference.py) and exhaustive small-trace parity checks (formal/test_fsm_reference.py) for reducer vs AoS/SoA/AoSoA, independent-entity ECS stepping, stable generation-fenced handles, reject-no-mutation, relayout and active-loan fences. It is *finite model exploration*, NOT TLA+/Dafny proof, not checked guest Oreslang, not real SIMD, and not compiler or backend certification.

Promotion gates:
- G0: pass independent Python reference tests and negative mutant/counterexample tests; link rule/version schema and bounded state-space configuration.
- G1: parse/check/execute real guest-source reducer/table examples on exact Java compiler commit, then LLVM and Rust with identical traces and rejection errors; independent compiler check is not enough.
- G2: execute physical AoS/SoA/AoSoA rows and ECS batch systems, field-sensitive borrow/await negatives, outbox failure atomicity, cross-actor ownership, hot reload generation fences.
- G3: add a pinned TLA+/Apalache machine for interleavings and transaction/swap-delete invariants (safety), plus any fairness-qualified liveness claims. Relate each model operation to actual backend code.
- G4: benchmark per-event ns, events/s, bytes/instance, allocation rate, cache misses, tail-lane performance and WCET bounds on named CPU/hardware/profile. Do not mistake throughput measurements for deadline certification.

No compiler/library source is claimed implemented by this RFC. Keep the PR **draft** until G1-G2 exact-source evidence is recorded.


## Audit/hardening addendum — October 19, 2026

### Resolved in the finite Python reference (not yet real guest code)

- **Store-recreation ABA:** a logical handle now includes a store-incarnation stamp minted for each new instance, in addition to the caller-visible owner, slot and generation. A recreated store with the same owner/slot/generation will reject a previous incarnation. The stamp is *not* a security capability or cross-process identity standard; actual systems must derive an authoritative namespace/epoch from supervisor lifecycle and reject forgeable cross-domain handles.
- **Finite generation exhaustion:** generations are deliberately model-bounded to \`0..6\`, with \`7\` representing terminal retirement. A retired slot is never recycled in its incarnation; a full retired-slot table refuses insertion rather than wrapping and triggering ABA. Production shall use an explicit wide nonwrapping generation and a defined exhaustion policy.
- **Transactional relayout:** conversion first builds a complete independent AoS/SoA/AoSoA representation, then publishes it; invalid lanes or a failed builder do not rewrite the original layout, row values, dense-slot map or outbox. This does not prove allocation-failure handling in an actual native allocator.
- **Bounded action admission:** \`LayoutStore.apply\` reserves one local outbox item *before* publishing each accepted machine transition; full outbox rejects without changing state/version or previously queued actions. \`drain_actions\` provides a bounded explicit handoff, **not** durable delivery, distributed exactly-once effects or an external transport protocol. A production implementation requires durable/idempotent dispatch where necessary.
- **Closed Symbol admission:** the model accepts the conservative unquoted ASCII literal subset \`#[A-Za-z_][A-Za-z0-9_]*\` with a 128-byte bound; rejects duplicate state/event registrations, repeated edges, undeclared or malformed tags, and non-Boolean guards. This is not the full normative Unicode, quoted-literal or visibility model from \`common-source/docs/SYMBOLS.md\`.
- **Finiteness:** model maxima are 32 states, 32 events, 256 edges, 64 live/retired slots, 16 lanes, 256 outbox entries and version 7. These are test bounds, *not* suggested runtime defaults or WCET certificates.
- **Adversarial regression corpus:** deterministic cross-layout randomized oracles, malicious handles and malformed labels, stale-incarnation and bounded-generation exhaustion, drained/rejected effects, injected relayout failure and fixed-layout parity complement exhaustive 781-trace runs.

### Additional handle-capability hardening — October 20, 2026

The finite Python model now includes a fresh, per-store bearer-issuer object in each
issued handle. A handle reconstructed from public owner/slot/generation/incarnation
integers is rejected even when every integer matches, and the issuer also participates
in equality/hash semantics. Immutable handle deepcopy preserves issuer identity across
rollback snapshots, outbox retention and physical layout migration. Targeted tests
include forged reads, writes, deletions, equality collisions and fault rollback.

**Threat-model boundary:** Python's `_issuer` attribute is inspectable and is **not**
a cryptographic secret, production authorization proof, or protection from arbitrary
host Python with reflection. Real Oreslang must represent the issuer as a
verifier-minted, unforgeable opaque capability scoped to actor/heap/tenant and
lifecycle generation, not caller-constructible public fields. Refuse deserialized
capabilities unless an authorized import/export policy reissues and binds them.
This draft is still a synchronous abstract model, not a parallel or crash-consistent
implementation.

### Explicit limitations / review blockers

1. \`read_loan\` is a **whole-store synchronous model fence**, not a field-sensitive borrow checker. It does not model \`await\`, actual suspension frames, aliasing across Task/actor domains, or adversarial concurrent threads.
2. \`ecs_tick\` is sequential and **per-event atomic**, not all-or-none across the full batch. A later bad handle may leave earlier successful transitions committed. Real parallel ECS dispatch needs determinism, read/write set proofs, locking/partitioning and bounded scheduling contracts.
3. The Python reference assumes operations execute on one thread without asynchronous mutation, and does not promise recovery from arbitrary Python \`MemoryError\` during insert, removal or a partially written \`_put_dense\`. Native implementation must explicitly preallocate, commit/rollback structural changes and test injected allocator failures.
4. The RuleTable is not a fully validated executable guest AST. Guards are modeled by a Boolean input; actual compilation must prove guard purity/termination, bounded execution, type-correct action payloads, causal ordering, and allowed Symbol visibility. Any rule upgrade/hot reload requires an exact policy/generation pin.
5. Exhaustive traces are bounded to five event choices and lengths 0..4; randomized traces are deterministic finite samples, **not** formal proof of all interleavings, progress, fairness, liveness, or hard real-time WCET.
6. The only available GitHub Actions result for the original PR head reported failure before recorded job steps, with logs unavailable. Do not claim the new tests have executed remotely until a runner emits a successful exact-head receipt. Do not copy private source to an unrelated organization without explicit authorization.

### Concrete exit criteria for promoting the PR

- [ ] Execute \`python3 -m unittest discover -s formal -p 'test_fsm_*.py' -v\` on the actual PR head, recording commit SHA, Python version, test counts and logs.
- [ ] Execute real \`.ores\` FSM semantics and negative admission fixtures on current Java/LLVM/Rust backend heads; distinguish syntax compilation, native runtime execution and model-only passes.
- [ ] Add allocator-failure/injected crash tests, lifecycle epoch ownership, field-sensitive borrow checks, version-fenced hot reload, and a durable outbox if cross-process effects are supported.
- [ ] Add a bounded TLA+/Apalache model for interleavings/restarts and separately justified fairness/liveness properties.
- [ ] Benchmark AoS/SoA/AoSoA for different machine sizes, access patterns, SIMD lane widths and target hardware. Profile strict RT only with platform-specific timing certification.

