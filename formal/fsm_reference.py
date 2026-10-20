"""Finite, executable reference semantics for proposed Oreslang FSMs.

This is an abstract model, NOT an implementation of Oreslang Symbols, compiler,
AoSoA SIMD, real borrow checking, parallel ECS, or a proof about any backend.
"""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
from typing import Iterable, Iterator


MAX_VERSION = 7


class AdmissionError(ValueError):
    pass


@dataclass(frozen=True)
class Machine:
    state: str
    version: int = 0


@dataclass(frozen=True)
class Outcome:
    machine: Machine
    actions: tuple[str, ...]
    accepted: bool
    reason: str = ""


@dataclass(frozen=True)
class Handle:
    owner: int
    slot: int
    generation: int


class RuleTable:
    """Closed, non-overlapping, immutable logical (state,event)->(state,action)."""

    def __init__(self, states: Iterable[str], events: Iterable[str],
                 rules: Iterable[tuple[str, str, str, str]]) -> None:
        self.states = frozenset(states)
        self.events = frozenset(events)
        if not self.states or not self.events:
            raise AdmissionError("empty FSM vocabulary")
        if any(not isinstance(s, str) or not s.startswith("#") for s in self.states | self.events):
            raise AdmissionError("only symbolic labels admitted in reference model")
        checked: dict[tuple[str, str], tuple[str, str]] = {}
        for src, event, dest, action in rules:
            if src not in self.states or dest not in self.states or event not in self.events:
                raise AdmissionError("undeclared state or event")
            if not isinstance(action, str) or not action.startswith("#"):
                raise AdmissionError("invalid action label")
            key = (src, event)
            if key in checked:
                raise AdmissionError("duplicate transition")
            checked[key] = (dest, action)
        from types import MappingProxyType
        self.rules = MappingProxyType(checked)


def step(table: RuleTable, machine: Machine, event: str, *,
         guard: bool = True, action_credits: int = 1) -> Outcome:
    """Pure, total transition. Rejections never advance version or emit actions."""
    if machine.state not in table.states or not (0 <= machine.version <= MAX_VERSION):
        return Outcome(machine, (), False, "invalid-machine")
    if event not in table.events:
        return Outcome(machine, (), False, "undeclared-event")
    rule = table.rules.get((machine.state, event))
    if rule is None:
        return Outcome(machine, (), False, "no-rule")
    if not guard:
        return Outcome(machine, (), False, "guard")
    if action_credits < 1:
        return Outcome(machine, (), False, "effect-capacity")
    if machine.version == MAX_VERSION:
        return Outcome(machine, (), False, "version-overflow")
    dest, action = rule
    return Outcome(Machine(dest, machine.version + 1), (action,), True)


def demo_table() -> RuleTable:
    return RuleTable(
        {"#idle", "#running", "#paused", "#done"},
        {"#start", "#pause", "#resume", "#stop", "#reset"},
        [
            ("#idle", "#start", "#running", "#started"),
            ("#running", "#pause", "#paused", "#paused_event"),
            ("#paused", "#resume", "#running", "#resumed"),
            ("#running", "#stop", "#done", "#stopped"),
            ("#paused", "#stop", "#done", "#stopped"),
            ("#done", "#reset", "#idle", "#reset_event"),
        ],
    )


class LayoutStore:
    """One live AoS/SoA/AoSoA representation and generational logical handles."""

    def __init__(self, layout: str, capacity: int, *, owner: int = 1, lanes: int = 4):
        if layout not in ("aos", "soa", "aosoa"):
            raise AdmissionError("unsupported layout")
        if capacity < 0 or owner <= 0 or (layout == "aosoa" and lanes < 1):
            raise AdmissionError("invalid storage configuration")
        self.layout = layout
        self.capacity = capacity
        self.owner = owner
        self.lanes = lanes
        self._slots: list[list[int | None]] = []  # generation, dense offset
        self._free: list[int] = []
        self._dense_slots: list[int] = []
        self._loans = 0
        self._aos: list[Machine] = []
        self._states: list[str] = []
        self._versions: list[int] = []
        self._chunks: list[tuple[list[str | None], list[int | None]]] = []

    def __len__(self) -> int:
        return len(self._dense_slots)

    def _ensure_exclusive(self) -> None:
        if self._loans:
            raise AdmissionError("active borrow")

    def _get_dense(self, dense: int) -> Machine:
        if self.layout == "aos":
            return self._aos[dense]
        if self.layout == "soa":
            return Machine(self._states[dense], self._versions[dense])
        state, version = self._chunks[dense // self.lanes]
        lane = dense % self.lanes
        assert state[lane] is not None and version[lane] is not None
        return Machine(state[lane], version[lane])

    def _put_dense(self, dense: int, machine: Machine) -> None:
        if self.layout == "aos":
            self._aos[dense] = machine
        elif self.layout == "soa":
            self._states[dense] = machine.state
            self._versions[dense] = machine.version
        else:
            state, version = self._chunks[dense // self.lanes]
            state[dense % self.lanes] = machine.state
            version[dense % self.lanes] = machine.version

    def _push_dense(self, machine: Machine) -> None:
        dense = len(self._dense_slots)
        if self.layout == "aos":
            self._aos.append(machine)
        elif self.layout == "soa":
            self._states.append(machine.state)
            self._versions.append(machine.version)
        else:
            if dense % self.lanes == 0:
                self._chunks.append(([None] * self.lanes, [None] * self.lanes))
            self._put_dense(dense, machine)

    def _pop_dense(self) -> None:
        dense = len(self._dense_slots) - 1
        if self.layout == "aos":
            self._aos.pop()
        elif self.layout == "soa":
            self._states.pop()
            self._versions.pop()
        else:
            state, version = self._chunks[dense // self.lanes]
            state[dense % self.lanes] = None
            version[dense % self.lanes] = None
            if dense % self.lanes == 0:
                self._chunks.pop()

    def _resolve(self, handle: Handle) -> int:
        if handle.owner != self.owner or not (0 <= handle.slot < len(self._slots)):
            raise AdmissionError("foreign or out-of-bounds handle")
        gen, dense = self._slots[handle.slot]
        if gen != handle.generation or dense is None:
            raise AdmissionError("stale handle")
        if self._dense_slots[dense] != handle.slot:
            raise AssertionError("broken dense/slot bijection")
        return dense

    def insert(self, machine: Machine) -> Handle:
        self._ensure_exclusive()
        if len(self) >= self.capacity:
            raise AdmissionError("capacity exhausted")
        if machine.version < 0 or machine.version > MAX_VERSION or not machine.state.startswith("#"):
            raise AdmissionError("invalid machine")
        # All admission checks precede changes; no failed half-insert.
        slot = self._free.pop() if self._free else len(self._slots)
        if slot == len(self._slots):
            self._slots.append([0, None])
        gen = self._slots[slot][0]
        dense = len(self._dense_slots)
        self._push_dense(machine)
        self._dense_slots.append(slot)
        self._slots[slot][1] = dense
        return Handle(self.owner, slot, gen)

    def read(self, handle: Handle) -> Machine:
        return self._get_dense(self._resolve(handle))

    def apply(self, handle: Handle, table: RuleTable, event: str, *,
              guard: bool = True, action_credits: int = 1) -> Outcome:
        self._ensure_exclusive()
        dense = self._resolve(handle)
        outcome = step(table, self._get_dense(dense), event,
                       guard=guard, action_credits=action_credits)
        if outcome.accepted:
            self._put_dense(dense, outcome.machine)
        return outcome

    def remove(self, handle: Handle) -> Machine:
        self._ensure_exclusive()
        dense = self._resolve(handle)
        old = self._get_dense(dense)
        last = len(self) - 1
        if dense != last:
            moved_slot = self._dense_slots[last]
            self._put_dense(dense, self._get_dense(last))
            self._dense_slots[dense] = moved_slot
            self._slots[moved_slot][1] = dense
        self._pop_dense()
        self._dense_slots.pop()
        self._slots[handle.slot][0] += 1
        self._slots[handle.slot][1] = None
        self._free.append(handle.slot)
        return old

    def relayout(self, layout: str, *, lanes: int | None = None) -> None:
        self._ensure_exclusive()
        if layout not in ("aos", "soa", "aosoa"):
            raise AdmissionError("unsupported layout")
        lane_count = self.lanes if lanes is None else lanes
        if lane_count < 1:
            raise AdmissionError("invalid lane count")
        rows = [self._get_dense(i) for i in range(len(self))]
        # Rebuild as an independent proposed physical layout.
        self.layout, self.lanes = layout, lane_count
        self._aos, self._states, self._versions, self._chunks = [], [], [], []
        for i, row in enumerate(rows):
            if self.layout == "aos":
                self._aos.append(row)
            elif self.layout == "soa":
                self._states.append(row.state)
                self._versions.append(row.version)
            else:
                if i % self.lanes == 0:
                    self._chunks.append(([None] * self.lanes, [None] * self.lanes))
                self._put_dense(i, row)

    @contextmanager
    def read_loan(self) -> Iterator[None]:
        self._loans += 1
        try:
            yield
        finally:
            self._loans -= 1

    def check_invariants(self) -> None:
        assert len(set(self._dense_slots)) == len(self)
        assert len(self) <= self.capacity
        for dense, slot in enumerate(self._dense_slots):
            assert self._slots[slot][1] == dense
            assert self._slots[slot][0] >= 0
        assert set(self._free).isdisjoint(self._dense_slots)
        if self.layout == "aos":
            assert len(self._aos) == len(self)
            assert not self._states and not self._versions and not self._chunks
        elif self.layout == "soa":
            assert len(self._states) == len(self._versions) == len(self)
            assert not self._aos and not self._chunks
        else:
            assert len(self._chunks) == (len(self) + self.lanes - 1) // self.lanes
            assert not self._aos and not self._states and not self._versions
            for i in range(len(self._chunks) * self.lanes):
                states, versions = self._chunks[i // self.lanes]
                if i < len(self):
                    assert states[i % self.lanes] is not None
                    assert versions[i % self.lanes] is not None
                else:
                    assert states[i % self.lanes] is None
                    assert versions[i % self.lanes] is None


def ecs_tick(store: LayoutStore, table: RuleTable,
             ordered_events: Iterable[tuple[Handle, str]]) -> tuple[Outcome, ...]:
    """Sequential reference ECS pass preserving event order per entity."""
    return tuple(store.apply(entity, table, event) for entity, event in ordered_events)
