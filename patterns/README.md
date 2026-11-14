# AttoLang actor-oriented patterns

These are educational source patterns. Their inclusion is **not** evidence of parser acceptance, executed guest behavior, native AOT, or multi-backend parity.

## Namespace-scoped actor receiver methods

[namespace-actor-receivers.atto](namespace-actor-receivers.atto) declares two actor types in one `.atto` file under `use namespace workers;`. The `mtd` receiver explicitly ties methods to `Foo1` or `Foo2`; state reads and writes are illustrated only inside `self.handle_state(critical-read|critical-write ...)` callbacks.

**Evidence:** `syntax-preview`, `not_executed`. It has no complete actor implementations or verified linking/dispatch. Do not run or advertise it as a production example until compiled guest tests and exact toolchain receipts are attached.

The machine-readable [catalog](catalog.json) declares this evidence boundary. Run `node --test tests/*.test.mjs` to validate the catalog and shape; these are **host-only structural checks**, not Atto compiler tests.

See the [language specification](https://github.com/atto-lang/atto-spec), [platform conformance](https://github.com/atto-lang/atto-platform-conformance), and [browser syntax preview](https://github.com/atto-lang/atto-lang.github.io/blob/main/play/examples/preview/actor-receiver-methods.atto) for context.
