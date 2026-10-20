# FSM Oreslang compiler fixtures

The first real `.ores` example is `01-symbol-reducer.ores`. It uses the
ordinary Symbol values `#idle`, `#start`, etc., and returns `#rejected`
on unsupported transitions. This is an **illustrative pure reducer**, not
the full transactional FSM API: versions, guards, effect metadata, bounded
outbox and ownership checks remain in the Python abstract protocol and are
future language/stdlib work.

The companion static test `formal/test_fsm_source_contract.py` checks that
the six closed source transitions match `formal/fsm_reference.py`. This is a
**static drift check only**; it does not parse or execute Oreslang.

Run actual compiler checks using:

```bash
ORESLANG_BIN=/path/to/oreslang bash scripts/check-fsm-native.sh
# If the compiler has a 'run' subcommand, explicitly check and execute:
ORESLANG_BIN=/path/to/oreslang bash scripts/check-fsm-native.sh --execute
```

A missing compiler or unsupported syntax MUST fail; never report a Python
reference-model pass as native guest compilation. Do not enable the source
fixture in `scripts/check-all.sh` until the target compiler version supports
the Symbol type and literal expressions and an exact-head check is passing.
LLVM and Rust parity are separately gated. There is no actor requirement.
