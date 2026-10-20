"""Adversarial FSM model checks; intentionally bounded and deterministic.

These tests certify only the Python abstract reference implementation, not an
Oreslang compiler, a real atomic outbox, parallel ECS or physical realtime code.
"""

import random
import unittest
from copy import deepcopy
from dataclasses import FrozenInstanceError, replace
from unittest.mock import patch

from fsm_reference import (
    AdmissionError,
    Handle,
    LayoutStore,
    Machine,
    MAX_GENERATION,
    MAX_LANES,
    MAX_STATES,
    RuleTable,
    demo_table,
    step,
)


LAYOUTS = ("aos", "soa", "aosoa")


class FSMHardeningTests(unittest.TestCase):
    def setUp(self):
        self.table = demo_table()

    def test_store_epoch_prevents_cross_recreation_aba(self):
        for layout in LAYOUTS:
            old = LayoutStore(layout, capacity=1, owner=42)
            stale = old.insert(Machine("#idle"))
            new = LayoutStore(layout, capacity=1, owner=42)
            valid = new.insert(Machine("#running"))
            self.assertEqual(stale.owner, valid.owner)
            self.assertEqual(stale.slot, valid.slot)
            self.assertEqual(stale.generation, valid.generation)
            self.assertNotEqual(stale.incarnation, valid.incarnation)
            with self.assertRaises(AdmissionError):
                new.read(stale)
            self.assertEqual(new.read(valid), Machine("#running"))
            new.check_invariants()

    def test_predictable_id_handle_reconstruction_does_not_grant_access(self):
        # The ordinal/generation/incarnation fields are deliberately visible
        # in the host model. Knowledge of them alone must not mint a capability.
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=2, owner=42)
            h = store.insert(Machine("#idle"))
            reconstructed = Handle(h.owner, h.slot, h.generation, h.incarnation)
            with self.assertRaises(AdmissionError):
                store.read(reconstructed)
            with self.assertRaises(AdmissionError):
                store.apply(reconstructed, self.table, "#start")
            with self.assertRaises(AdmissionError):
                store.remove(reconstructed)
            with self.assertRaises(AdmissionError):
                store.read(replace(h, _issuer=object()))
            self.assertEqual(store.read(h), Machine("#idle"))
            self.assertEqual(deepcopy(h), h)
            self.assertIs(deepcopy(h), h)
            store.check_invariants()

    def test_issuer_is_stable_through_rollback_and_layout_migration(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=1, owner=42, outbox_capacity=2)
            h = store.insert(Machine("#idle"))
            self.assertTrue(store.apply(h, self.table, "#start").accepted)
            recorded = store.queued_actions()
            with patch.object(store, "_put_dense", side_effect=MemoryError("injected")):
                with self.assertRaises(MemoryError):
                    store.apply(h, self.table, "#stop")
            self.assertEqual(store.queued_actions(), recorded)
            self.assertIs(store.queued_actions()[0][0], h)
            store.relayout({"aos":"soa", "soa":"aosoa", "aosoa":"aos"}[layout])
            self.assertEqual(store.read(h), Machine("#running", 1))
            self.assertEqual(store.drain_actions(), ((h, "#started"),))
            store.check_invariants()

    def test_generation_exhaustion_never_wraps(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=1)
            retired = []
            for generation in range(MAX_GENERATION):
                h = store.insert(Machine("#idle"))
                self.assertEqual(h.generation, generation)
                store.remove(h)
                retired.append(h)
                store.check_invariants()
            with self.assertRaises(AdmissionError):
                store.insert(Machine("#idle"))
            for h in retired:
                with self.assertRaises(AdmissionError):
                    store.read(h)

    def test_malformed_symbols_and_duplicate_labels_are_rejected(self):
        for tag in ("#", "##idle", "#0start", "#has space", "idle", "#x!", "#é",
                    "#a" * 100, "#x\n", "#x\u202e"):
            with self.subTest(tag=repr(tag)), self.assertRaises(AdmissionError):
                RuleTable([tag], ["#go"], [])
        for state_tags in (["#idle", "#idle"], []):
            with self.assertRaises(AdmissionError):
                RuleTable(state_tags, ["#go"], [])
        with self.assertRaises(AdmissionError):
            RuleTable(["#idle"], ["#go", "#go"], [])
        with self.assertRaises(AdmissionError):
            RuleTable(["#idle"], ["#go"], [(["#idle"], "#go", "#idle", "#ok")])
        with self.assertRaises(AdmissionError):
            RuleTable(("#s" + str(i) for i in range(MAX_STATES + 1)), ["#go"], [])
        bad = Machine("#idle", -1)
        self.assertEqual(step(self.table, bad, "#start").reason, "invalid-machine")
        self.assertEqual(step(self.table, Machine("#idle", True), "#start").reason,
                         "invalid-machine")
        self.assertEqual(step(self.table, Machine("#idle"), "#start",
                              guard=1).reason, "guard")

    def test_closed_table_is_immutable(self):
        with self.assertRaises(FrozenInstanceError):
            self.table.rules = {}
        with self.assertRaises(TypeError):
            self.table.rules[("#idle", "#start")] = ("#done", "#bad")

    def test_bad_machine_insert_is_rejected_without_allocating_slots(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=2)
            for invalid in (Machine("#"), Machine("idle"), Machine("#idle", -1),
                            Machine("#idle", True), Machine("#idle", 999)):
                with self.subTest(layout=layout, invalid=invalid), self.assertRaises(AdmissionError):
                    store.insert(invalid)
                self.assertEqual(len(store), 0)
                store.check_invariants()
            h = store.insert(Machine("#idle"))
            self.assertEqual(h.slot, 0)

    def test_bounded_outbox_reserve_then_commit(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=1, outbox_capacity=1)
            h = store.insert(Machine("#idle"))
            first = store.apply(h, self.table, "#start")
            self.assertTrue(first.accepted)
            self.assertEqual(store.read(h), Machine("#running", 1))
            self.assertEqual(store.queued_actions(), ((h, "#started"),))
            before = (store.read(h), store.queued_actions())
            refused = store.apply(h, self.table, "#stop")
            self.assertEqual(refused.reason, "effect-capacity")
            self.assertEqual((store.read(h), store.queued_actions()), before)
            for wrong in (-1, "2", True):
                with self.assertRaises(AdmissionError):
                    store.drain_actions(wrong)
                self.assertEqual(store.queued_actions(), before[1])
            self.assertEqual(store.drain_actions(0), ())
            self.assertEqual(store.drain_actions(1), ((h, "#started"),))
            self.assertEqual(store.queued_actions(), ())
            self.assertTrue(store.apply(h, self.table, "#stop").accepted)
            self.assertEqual(store.read(h), Machine("#done", 2))
            store.check_invariants()

    def test_zero_effect_capacity_does_not_commit(self):
        for layout in LAYOUTS:
            store = LayoutStore(layout, capacity=1, outbox_capacity=0)
            h = store.insert(Machine("#idle"))
            result = store.apply(h, self.table, "#start")
            self.assertEqual(result.reason, "effect-capacity")
            self.assertEqual(store.read(h), Machine("#idle"))
            self.assertEqual(store.queued_actions(), ())
            store.check_invariants()

    def test_relayout_exception_keeps_old_physical_representation(self):
        for source in LAYOUTS:
            store = LayoutStore(source, capacity=3, lanes=2)
            handles = [store.insert(Machine("#idle", i)) for i in range(3)]
            pre = ([store.read(h) for h in handles], store.layout, store.lanes,
                   store.queued_actions(), list(store._dense_slots))
            with patch.object(LayoutStore, "_encode_rows", side_effect=MemoryError("injected")):
                with self.assertRaises(MemoryError):
                    store.relayout("aosoa", lanes=3)
            post = ([store.read(h) for h in handles], store.layout, store.lanes,
                    store.queued_actions(), list(store._dense_slots))
            self.assertEqual(pre, post)
            store.check_invariants()

    def test_outbox_is_preserved_by_layout_relocation(self):
        for source in LAYOUTS:
            store = LayoutStore(source, capacity=2, outbox_capacity=2)
            h = store.insert(Machine("#idle"))
            store.apply(h, self.table, "#start")
            expected = store.queued_actions()
            for target in LAYOUTS:
                store.relayout(target, lanes=3)
                self.assertEqual(store.read(h), Machine("#running", 1))
                self.assertEqual(store.queued_actions(), expected)
                store.check_invariants()

    def test_bounded_config_validation(self):
        cases = (
            {"layout": "aosoa", "capacity": 1, "lanes": MAX_LANES + 1},
            {"layout": "aosoa", "capacity": 1, "lanes": True},
            {"layout": "aos", "capacity": True},
            {"layout": "soa", "capacity": 65},
            {"layout": "soa", "capacity": 1, "owner": True},
            {"layout": "aos", "capacity": 1, "outbox_capacity": -1},
        )
        for args in cases:
            with self.subTest(args=args), self.assertRaises(AdmissionError):
                LayoutStore(**args)

    def test_deterministic_randomized_layout_and_oracle_parity(self):
        # Deterministic randomized state sequences, plus per-operation invariants.
        for layout in LAYOUTS:
            rng = random.Random(20261019)
            store = LayoutStore(layout, capacity=5, lanes=3, outbox_capacity=256)
            oracle = {}
            live = []
            for _ in range(260):
                choice = rng.choice(("insert", "apply", "apply", "remove", "relayout", "drain"))
                if choice == "insert":
                    try:
                        h = store.insert(Machine("#idle"))
                    except AdmissionError:  # capacity or deliberately bounded generation exhaustion
                        pass
                    else:
                        oracle[h] = Machine("#idle")
                        live.append(h)
                elif choice == "apply" and live:
                    h = rng.choice(live)
                    event = rng.choice(("#start", "#stop", "#pause", "#resume", "#reset"))
                    expected = step(self.table, oracle[h], event,
                                    action_credits=store.outbox_capacity - len(store.queued_actions()))
                    actual = store.apply(h, self.table, event)
                    self.assertEqual(actual, expected)
                    oracle[h] = actual.machine
                elif choice == "remove" and live:
                    h = rng.choice(live)
                    self.assertEqual(store.remove(h), oracle.pop(h))
                    live.remove(h)
                    with self.assertRaises(AdmissionError):
                        store.read(h)
                elif choice == "relayout":
                    store.relayout(rng.choice(LAYOUTS), lanes=rng.randint(1, 5))
                elif choice == "drain":
                    store.drain_actions(rng.randint(0, 4))
                for h, machine in oracle.items():
                    self.assertEqual(store.read(h), machine)
                self.assertEqual(len(store), len(oracle))
                store.check_invariants()


if __name__ == "__main__":
    unittest.main()
