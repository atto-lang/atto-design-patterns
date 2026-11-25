"""Finite exhaustive tests of the FSM reference contract.

Run: python3 -m unittest discover -s formal -p 'test_fsm_*.py' -v
A passing reference model is NOT guest-source/compiler/runtime verification.
"""

import itertools
import unittest

from fsm_reference import (
    AdmissionError,
    Handle,
    LayoutStore,
    Machine,
    MAX_VERSION,
    RuleTable,
    demo_table,
    ecs_tick,
    step,
)


EVENTS = ("#start", "#pause", "#resume", "#stop", "#reset")
LAYOUTS = ("aos", "soa", "aosoa")


class FSMReferenceTests(unittest.TestCase):
    def setUp(self):
        self.table = demo_table()

    def test_closed_table_rejects_overlap_and_undeclared_vocabulary(self):
        for rules in (
            [("#idle", "#start", "#running", "#ok"),
             ("#idle", "#start", "#idle", "#other")],
            [("#idle", "#unknown", "#running", "#ok")],
            [("#outside", "#start", "#running", "#ok")],
            [("#idle", "#start", "#outside", "#ok")],
            [("#idle", "#start", "#running", "not-a-symbol")],
        ):
            with self.subTest(rules=rules), self.assertRaises(AdmissionError):
                RuleTable({"#idle", "#running"}, {"#start"}, rules)

    def test_rejections_are_noops_and_do_not_emit_actions(self):
        original = Machine("#idle", 2)
        cases = [
            ("#stop", True, 1, "no-rule"),
            ("#bogus", True, 1, "undeclared-event"),
            ("#start", False, 1, "guard"),
            ("#start", True, 0, "effect-capacity"),
        ]
        for event, guard, credits, reason in cases:
            result = step(self.table, original, event, guard=guard,
                          action_credits=credits)
            self.assertFalse(result.accepted)
            self.assertEqual(result.machine, original)
            self.assertEqual(result.actions, ())
            self.assertEqual(result.reason, reason)

    def test_successful_transition_and_version_overflow(self):
        first = step(self.table, Machine("#idle"), "#start")
        self.assertEqual(first.machine, Machine("#running", 1))
        self.assertEqual(first.actions, ("#started",))
        rejected = step(self.table, Machine("#idle", MAX_VERSION), "#start")
        self.assertEqual(rejected.reason, "version-overflow")
        self.assertEqual(rejected.machine, Machine("#idle", MAX_VERSION))

    def test_exhaustive_small_traces_equivalent_in_all_layouts(self):
        # 1+5+25+125+625=781 traces/layout, including invalid transition paths.
        for length in range(5):
            for trace in itertools.product(EVENTS, repeat=length):
                expected = Machine("#idle")
                reference_results = []
                for event in trace:
                    result = step(self.table, expected, event)
                    expected = result.machine
                    reference_results.append((result.accepted, result.actions, result.reason))
                for layout in LAYOUTS:
                    store = LayoutStore(layout, capacity=1, lanes=3)
                    handle = store.insert(Machine("#idle"))
                    got = []
                    for event in trace:
                        result = store.apply(handle, self.table, event)
                        got.append((result.accepted, result.actions, result.reason))
                    self.assertEqual(store.read(handle), expected)
                    self.assertEqual(got, reference_results)
                    store.check_invariants()

    def test_ecs_stream_interleavings_are_entity_local(self):
        # All 20 order-preserving shuffles of three events per entity.
        a_events = ("#start", "#pause", "#resume")
        b_events = ("#start", "#stop", "#reset")
        for positions_a in itertools.combinations(range(6), 3):
            for layout in LAYOUTS:
                store = LayoutStore(layout, capacity=2, lanes=4)
                a = store.insert(Machine("#idle"))
                b = store.insert(Machine("#idle"))
                ia = ib = 0
                events = []
                for pos in range(6):
                    if pos in positions_a:
                        events.append((a, a_events[ia]))
                        ia += 1
                    else:
                        events.append((b, b_events[ib]))
                        ib += 1
                effects = ecs_tick(store, self.table, events)
                self.assertTrue(all(x.accepted for x in effects))
                self.assertEqual(store.read(a), Machine("#running", 3))
                self.assertEqual(store.read(b), Machine("#idle", 3))
                store.check_invariants()

    def test_swap_delete_keeps_surviving_handle_and_reuse_is_fenced(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=3, owner=42, lanes=2)
            a = store.insert(Machine("#idle"))
            b = store.insert(Machine("#running", 2))
            c = store.insert(Machine("#paused", 1))
            self.assertEqual(store.remove(b), Machine("#running", 2))
            self.assertEqual(store.read(c), Machine("#paused", 1))
            with self.assertRaises(AdmissionError):
                store.read(b)
            d = store.insert(Machine("#done", 3))
            self.assertEqual(d.slot, b.slot)
            self.assertNotEqual(d.generation, b.generation)
            with self.assertRaises(AdmissionError):
                store.apply(b, self.table, "#reset")
            self.assertEqual(store.read(a), Machine("#idle"))
            self.assertEqual(store.read(c), Machine("#paused", 1))
            self.assertEqual(store.read(d), Machine("#done", 3))
            store.check_invariants()

    def test_foreign_negative_and_out_of_bounds_handles(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=1, owner=33)
            h = store.insert(Machine("#idle"))
            for forged in (Handle(44, h.slot, h.generation),
                           Handle(33, -1, h.generation),
                           Handle(33, 10000, h.generation),
                           Handle(33, h.slot, h.generation + 1)):
                with self.subTest(layout=layout, forged=forged), self.assertRaises(AdmissionError):
                    store.read(forged)

    def test_capacity_failure_is_atomic(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=1)
            h = store.insert(Machine("#idle"))
            with self.assertRaises(AdmissionError):
                store.insert(Machine("#running"))
            self.assertEqual(len(store), 1)
            self.assertEqual(store.read(h), Machine("#idle"))
            store.check_invariants()

    def test_borrow_blocks_mutation_and_relayout(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=2)
            h = store.insert(Machine("#idle"))
            with store.read_loan():
                self.assertEqual(store.read(h), Machine("#idle"))
                for op in (
                    lambda: store.apply(h, self.table, "#start"),
                    lambda: store.remove(h),
                    lambda: store.insert(Machine("#idle")),
                    lambda: store.relayout("aosoa"),
                ):
                    with self.assertRaises(AdmissionError):
                        op()
            self.assertTrue(store.apply(h, self.table, "#start").accepted)
            store.check_invariants()

    def test_relayout_preserves_handles_and_logical_order(self):
        for source in LAYOUTS:
            store = LayoutStore(source, capacity=7, lanes=2)
            hs = [store.insert(Machine("#idle", i)) for i in range(6)]
            store.remove(hs[1])
            store.remove(hs[4])
            expected = {h: store.read(h) for h in (hs[0], hs[2], hs[3], hs[5])}
            for target, lanes in (("soa", 2), ("aosoa", 3), ("aosoa", 4), ("aos", 2)):
                store.relayout(target, lanes=lanes)
                for h, machine in expected.items():
                    self.assertEqual(store.read(h), machine)
                store.check_invariants()
            with self.assertRaises(AdmissionError):
                store.relayout("aosoa", lanes=0)
            self.assertEqual(store.layout, "aos")

    def test_aosoa_tail_padding_never_visible(self):
        for lanes in (1, 2, 3, 4, 8):
            store = LayoutStore("aosoa", capacity=10, lanes=lanes)
            handles = [store.insert(Machine("#idle")) for _ in range(7)]
            for h in handles[::2]:
                store.remove(h)
                store.check_invariants()
            for _ in range(3):
                store.insert(Machine("#running"))
                store.check_invariants()

    def test_invalid_layout_configuration(self):
        for args in (
            {"layout": "xyz", "capacity": 5},
            {"layout": "aos", "capacity": -1},
            {"layout": "aosoa", "capacity": 1, "lanes": 0},
            {"layout": "soa", "capacity": 1, "owner": 0},
        ):
            with self.assertRaises(AdmissionError):
                LayoutStore(**args)

    def test_negative_mutant_detects_guard_bypass(self):
        # Deliberately faulty reducer: ignores the guard. This must diverge.
        baseline = Machine("#idle")
        correct = step(self.table, baseline, "#start", guard=False)
        mutant = step(self.table, baseline, "#start", guard=True)
        self.assertFalse(correct.accepted)
        self.assertTrue(mutant.accepted)
        self.assertNotEqual(correct.machine, mutant.machine)


if __name__ == "__main__":
    unittest.main()
