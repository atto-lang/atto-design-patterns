"""Fault-injection tests for the single-threaded finite FSM reference model.

Run: python3 -m unittest discover -s formal -p 'test_fsm_*.py' -v
No physical crash consistency, lock-free safety, or guest-code proof is implied.
"""

import unittest
from unittest.mock import patch

from fsm_reference import AdmissionError, LayoutStore, Machine, demo_table, step


LAYOUTS = ("aos", "soa", "aosoa")


class FSMTransactionFaultTests(unittest.TestCase):
    def _fingerprint(self, store, handles):
        # Includes internal metadata to catch failures leaving hidden corruption.
        return (
            store.layout,
            store.lanes,
            len(store),
            tuple(store._dense_slots),
            tuple(tuple(x) for x in store._slots),
            tuple(store._free),
            tuple(store._aos),
            tuple(store._states),
            tuple(store._versions),
            tuple((tuple(s), tuple(v)) for s, v in store._chunks),
            tuple(store.queued_actions()),
            tuple(store.read(h) for h in handles),
        )

    def test_partial_insert_then_exception_restores_all_layouts(self):
        for layout in LAYOUTS:
            with self.subTest(layout=layout):
                store = LayoutStore(layout, capacity=3, lanes=2)
                original = store.insert(Machine("#idle"))
                before = self._fingerprint(store, (original,))
                true_push = store._push_dense

                def partial_push(row):
                    true_push(row)  # physical row added, slot map not yet updated
                    raise MemoryError("insert-after-physical-write")

                with patch.object(store, "_push_dense", side_effect=partial_push):
                    with self.assertRaises(MemoryError):
                        store.insert(Machine("#running"))
                self.assertEqual(before, self._fingerprint(store, (original,)))
                store.check_invariants()
                second = store.insert(Machine("#running"))
                self.assertEqual(second.slot, 1)
                store.check_invariants()

    def test_partial_swap_delete_then_exception_restores_all_layouts(self):
        for layout in LAYOUTS:
            with self.subTest(layout=layout):
                store = LayoutStore(layout, capacity=4, lanes=3)
                handles = tuple(store.insert(Machine("#idle", i)) for i in range(3))
                before = self._fingerprint(store, handles)
                true_pop = store._pop_dense

                def partial_pop():
                    true_pop()  # one or more physical writes were already done
                    raise OSError("swap-delete-partial-failure")

                with patch.object(store, "_pop_dense", side_effect=partial_pop):
                    with self.assertRaises(OSError):
                        store.remove(handles[0])
                self.assertEqual(before, self._fingerprint(store, handles))
                store.check_invariants()
                removed = store.remove(handles[0])
                self.assertEqual(removed, Machine("#idle", 0))
                self.assertEqual(store.read(handles[2]), Machine("#idle", 2))
                store.check_invariants()

    def test_partial_state_write_then_exception_restores_outbox(self):
        table = demo_table()
        for layout in LAYOUTS:
            with self.subTest(layout=layout):
                store = LayoutStore(layout, capacity=1, lanes=2, outbox_capacity=2)
                h = store.insert(Machine("#idle"))
                before = self._fingerprint(store, (h,))
                true_put = store._put_dense

                def partial_commit(index, row):
                    true_put(index, row)  # already mutated state/column
                    raise OSError("write-after-mutation")

                with patch.object(store, "_put_dense", side_effect=partial_commit):
                    with self.assertRaises(OSError):
                        store.apply(h, table, "#start")
                self.assertEqual(before, self._fingerprint(store, (h,)))
                store.check_invariants()
                self.assertTrue(store.apply(h, table, "#start").accepted)
                self.assertEqual(store.queued_actions(), ((h, "#started"),))
                store.check_invariants()

    def test_atomic_snapshot_does_not_mutate_on_invalid_admission(self):
        table = demo_table()
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=2, outbox_capacity=0)
            h = store.insert(Machine("#idle"))
            before = self._fingerprint(store, (h,))
            self.assertEqual(store.apply(h, table, "#start").reason, "effect-capacity")
            with self.assertRaises(AdmissionError):
                store.remove(type(h)(h.owner, -1, h.generation, h.incarnation))
            with self.assertRaises(AdmissionError):
                store.insert(Machine("not-a-symbol"))
            self.assertEqual(self._fingerprint(store, (h,)), before)
            store.check_invariants()

    def test_surrogate_symbol_is_rejected_not_unicode_error(self):
        table = demo_table()
        result = step(table, Machine("#idle"), "#\ud800")
        self.assertFalse(result.accepted)
        self.assertEqual(result.reason, "undeclared-event")
        with self.assertRaises(AdmissionError):
            LayoutStore("aos", 1).insert(Machine("#\ud800"))


if __name__ == "__main__":
    unittest.main()
