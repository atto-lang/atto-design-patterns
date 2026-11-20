"""Static drift guard between the first Oreslang FSM fixture and the Python oracle.

This checks *source shape and listed edge identity*, not Oreslang parser
acceptance, executable guest behavior, Symbol lowering or side-effect safety.
"""

from pathlib import Path
import re
import unittest

from fsm_reference import demo_table


SOURCE = Path(__file__).resolve().parent.parent / "examples/fsm/01-symbol-reducer.ores"
EDGE = re.compile(
    r"if state == (#[A-Za-z_][A-Za-z_0-9]*)"
    r" && event == (#[A-Za-z_][A-Za-z_0-9]*) then\s*"
    r"return (#[A-Za-z_][A-Za-z_0-9]*);\s*fi"
)


class FsmSourceContract(unittest.TestCase):
    def test_native_fixture_has_same_closed_transition_edges_as_model(self):
        text = SOURCE.read_text(encoding="utf-8")
        found = EDGE.findall(text)
        oracle = demo_table()
        expected = {(state, event): dest
                    for (state, event), (dest, _action) in oracle.rules.items()}
        self.assertEqual(len(found), len(expected))
        self.assertEqual(len({(src, event) for src, event, _ in found}),
                         len(found), "fixture duplicates an edge")
        self.assertEqual({(src, event): dest for src, event, dest in found},
                         expected)
        self.assertEqual(text.count("if state =="), len(expected),
                         "unrecognized transition guard escapes the drift check")

    def test_rejection_sentinel_is_not_in_live_state_vocabulary(self):
        text = SOURCE.read_text(encoding="utf-8")
        self.assertIn("return #rejected;", text)
        self.assertNotIn("#rejected", demo_table().states)
        self.assertIn("define module fsm_symbol_reducer as", text)
        self.assertIn("pub routine main(): void", text)


if __name__ == "__main__":
    unittest.main()
