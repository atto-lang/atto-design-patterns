"""Finite, executable reference semantics for proposed Oreslang FSMs.

This is an abstract model, NOT an implementation of Oreslang Symbols, compiler,
AoSoA SIMD, real borrow checking, parallel ECS, or a proof about any backend.
"""

from __future__ import annotations

from contextlib import contextmanager
from copy import deepcopy
from dataclasses import dataclass, field
from itertools import count, islice
from re import fullmatch
from types import MappingProxyType
from typing import Iterable, Iterator


MAX_VERSION = 7
MAX_GENERATION = 7  # deliberately small model bound; production generations must not wrap
MAX_STATES = 32
MAX_EVENTS = 32
MAX_RULES = 256
MAX_CAPACITY = 64
MAX_LANES = 16
MAX_OUTBOX = 256
_NEXT_INCARNATION = count(1)


def _symbol(value: object) -> bool:
    """Conservative subset of canonical ASCII #symbol literals (not guest lexer)."""
    return (type(value) is str and value.isascii()
            and len(value) <= 128
            and fullmatch(r"#[A-Za-z_][A-Za-z0-9_]*", value) is not None)


def _bounded_labels(values: Iterable[str], limit: int, kind: str) -> frozenset[str]:
    entries = list(islice(values, limit + 1))
    if not entries or len(entries) > limit or any(not _symbol(v) for v in entries):
        raise AdmissionError("invalid or excessive " + kind)
    if len(set(entries)) != len(entries):
        raise AdmissionError("duplicate " + kind)
    return frozenset(entries)


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
    incarnation: int = 0  # minted per store; default represents an inadmissible forged handle
    _issuer: object = field(default=None, repr=False)

    def __deepcopy__(self, memo):
        # Immutable bearer handles retain their issuer identity during an
        # outbox/snapshot rollback. deepcopy(object()) otherwise invents a
        # different issuer and silently corrupts restored receipts.
        return self


@dataclass(frozen=True, init=False)
class RuleTable:
    """Closed immutable table; supported tags are a bounded ASCII Symbol subset."""

    states: frozenset[str]
    events: frozenset[str]
    rules: object

    def __init__(self, states: Iterable[str], events: Iterable[str],
                 rules: Iterable[tuple[str, str, str, str]]) -> None:
        known_states = _bounded_labels(states, MAX_STATES, "states")
        known_events = _bounded_labels(events, MAX_EVENTS, "events")
        checked: dict[tuple[str, str], tuple[str, str]] = {}
        for index, rule in enumerate(rules):
            if index >= MAX_RULES:
                raise AdmissionError("excessive transitions")
            if not isinstance(rule, tuple) or len(rule) != 4:
                raise AdmissionError("malformed transition")
            src, event, dest, action = rule
            if not all(_symbol(tag) for tag in (src, event, dest, action)):
                raise AdmissionError("invalid transition tag")
            if src not in known_states or dest not in known_states or event not in known_events:
                raise AdmissionError("undeclared state or event")
            key = (src, event)
            if key in checked:
                raise AdmissionError("duplicate transition")
            checked[key] = (dest, action)
        object.__setattr__(self, "states", known_states)
        object.__setattr__(self, "events", known_events)
        object.__setattr__(self, "rules", MappingProxyType(checked))


def step(table: RuleTable, machine: Machine, event: str, *,
         guard: bool = True, action_credits: int = 1) -> Outcome:
    """Pure transition; every rejection preserves state/version and emits nothing."""
    if (not isinstance(machine, Machine) or not _symbol(machine.state)
            or type(machine.version) is not int
            or machine.state not in table.states
            or not (0 <= machine.version <= MAX_VERSION)):
        return Outcome(machine, (), False, "invalid-machine")
    if not _symbol(event) or event not in table.events:
        return Outcome(machine, (), False, "undeclared-event")
    rule = table.rules.get((machine.state, event))
    if rule is None:
        return Outcome(machine, (), False, "no-rule")
    if guard is not True:
        return Outcome(machine, (), False, "guard")
    if type(action_credits) is not int or action_credits < 1:
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

    def __init__(self, layout: str, capacity: int, *, owner: int = 1, lanes: int = 4,
                 outbox_capacity: int = 64):
        if layout not in ("aos", "soa", "aosoa"):
            raise AdmissionError("unsupported layout")
        if (type(capacity) is not int or not 0 <= capacity <= MAX_CAPACITY
                or type(owner) is not int or owner <= 0
                or type(lanes) is not int or not 1 <= lanes <= MAX_LANES
                or type(outbox_capacity) is not int
                or not 0 <= outbox_capacity <= MAX_OUTBOX):
            raise AdmissionError("invalid storage configuration")
        self.layout = layout
        self.capacity = capacity
        self.owner = owner
        self.lanes = lanes
        self.incarnation = next(_NEXT_INCARNATION)
        self._issuer = object()  # reference-only opaque bearer capability
        self.outbox_capacity = outbox_capacity
        self._outbox: list[tuple[Handle, str]] = []
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

    def _snapshot(self):
        """Whole-store rollback witness; deliberately O(n), model-only."""
        names = ("_slots", "_free", "_dense_slots", "_aos", "_states",
                 "_versions", "_chunks", "_outbox")
        return tuple(deepcopy(getattr(self, name)) for name in names)

    def _restore(self, snapshot) -> None:
        names = ("_slots", "_free", "_dense_slots", "_aos", "_states",
                 "_versions", "_chunks", "_outbox")
        for name, value in zip(names, snapshot):
            setattr(self, name, value)

    @contextmanager
    def _atomic_mutation(self) -> Iterator[None]:
        """Roll back Python list operations even on injected MemoryError.

        An executable reference protocol, NOT native crash-atomic storage.
        """
        snapshot = self._snapshot()
        try:
            yield
        except BaseException:
            self._restore(snapshot)
            raise

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
        if (type(handle) is not Handle or handle._issuer is not self._issuer
                or type(handle.owner) is not int or handle.owner != self.owner
                or type(handle.incarnation) is not int
                or handle.incarnation != self.incarnation
                or type(handle.slot) is not int
                or not (0 <= handle.slot < len(self._slots))
                or type(handle.generation) is not int
                or not (0 <= handle.generation <= MAX_GENERATION)):
            raise AdmissionError("foreign, obsolete or out-of-bounds handle")
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
        if (not isinstance(machine, Machine) or not _symbol(machine.state)
                or type(machine.version) is not int
                or not 0 <= machine.version <= MAX_VERSION):
            raise AdmissionError("invalid machine")
        if not self._free and len(self._slots) >= self.capacity:
            raise AdmissionError("retired slots exhausted")
        # Prototype reference uses a snapshot for failure atomicity; a real
        # runtime should preallocate and implement bounded rollback/commit.
        with self._atomic_mutation():
            slot = self._free.pop() if self._free else len(self._slots)
            if slot == len(self._slots):
                self._slots.append([0, None])
            gen = self._slots[slot][0]
            dense = len(self._dense_slots)
            self._push_dense(machine)
            self._dense_slots.append(slot)
            self._slots[slot][1] = dense
            return Handle(self.owner, slot, gen, self.incarnation, self._issuer)

    def read(self, handle: Handle) -> Machine:
        return self._get_dense(self._resolve(handle))

    def apply(self, handle: Handle, table: RuleTable, event: str, *,
              guard: bool = True, action_credits: int = 1) -> Outcome:
        self._ensure_exclusive()
        dense = self._resolve(handle)
        old = self._get_dense(dense)
        available = min(action_credits, self.outbox_capacity - len(self._outbox)) if (
            type(action_credits) is int) else 0
        outcome = step(table, old, event, guard=guard, action_credits=available)
        if outcome.accepted:
            # Reserve bounded local outbox before state publication; any
            # partial Python mutation is reverted by the reference snapshot.
            with self._atomic_mutation():
                self._outbox.append((handle, outcome.actions[0]))
                self._put_dense(dense, outcome.machine)
        return outcome

    def drain_actions(self, max_count: int | None = None) -> tuple[tuple[Handle, str], ...]:
        self._ensure_exclusive()
        if max_count is None:
            max_count = len(self._outbox)
        if type(max_count) is not int or max_count < 0:
            raise AdmissionError("invalid drain bound")
        drained = tuple(self._outbox[:max_count])
        del self._outbox[:max_count]
        return drained

    def queued_actions(self) -> tuple[tuple[Handle, str], ...]:
        return tuple(self._outbox)

    def remove(self, handle: Handle) -> Machine:
        self._ensure_exclusive()
        dense = self._resolve(handle)
        old = self._get_dense(dense)
        with self._atomic_mutation():
            last = len(self) - 1
            if dense != last:
                moved_slot = self._dense_slots[last]
                self._put_dense(dense, self._get_dense(last))
                self._dense_slots[dense] = moved_slot
                self._slots[moved_slot][1] = dense
            self._pop_dense()
            self._dense_slots.pop()
            # No wraparound: MAX_GENERATION is terminal retirement.
            if self._slots[handle.slot][0] + 1 < MAX_GENERATION:
                self._slots[handle.slot][0] += 1
                self._free.append(handle.slot)
            else:
                self._slots[handle.slot][0] = MAX_GENERATION
            self._slots[handle.slot][1] = None
        return old

    @staticmethod
    def _encode_rows(rows: list[Machine], layout: str, lane_count: int):
        """Build full target storage off to the side before publication."""
        aos: list[Machine] = []
        states: list[str] = []
        versions: list[int] = []
        chunks: list[tuple[list[str | None], list[int | None]]] = []
        for i, row in enumerate(rows):
            if layout == "aos":
                aos.append(row)
            elif layout == "soa":
                states.append(row.state)
                versions.append(row.version)
            else:
                if i % lane_count == 0:
                    chunks.append(([None] * lane_count, [None] * lane_count))
                chunk_states, chunk_versions = chunks[i // lane_count]
                chunk_states[i % lane_count] = row.state
                chunk_versions[i % lane_count] = row.version
        return aos, states, versions, chunks

    def relayout(self, layout: str, *, lanes: int | None = None) -> None:
        self._ensure_exclusive()
        if layout not in ("aos", "soa", "aosoa"):
            raise AdmissionError("unsupported layout")
        lane_count = self.lanes if lanes is None else lanes
        if type(lane_count) is not int or not 1 <= lane_count <= MAX_LANES:
            raise AdmissionError("invalid lane count")
        rows = [self._get_dense(i) for i in range(len(self))]
        # Exceptions during construction leave the old representation intact.
        new_storage = self._encode_rows(rows, layout, lane_count)
        self.layout, self.lanes = layout, lane_count
        self._aos, self._states, self._versions, self._chunks = new_storage


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
        assert len(self._slots) <= self.capacity
        assert len(set(self._free)) == len(self._free)
        assert all(0 <= x < len(self._slots) for x in self._free)
        assert set(self._free) | set(self._dense_slots) <= set(range(len(self._slots)))
        assert all(0 <= slot[0] <= MAX_GENERATION for slot in self._slots)
        assert len(self._outbox) <= self.outbox_capacity
        assert all(h.incarnation == self.incarnation and h.owner == self.owner
                   and h._issuer is self._issuer and _symbol(tag)
                   for h, tag in self._outbox)
        for dense, slot in enumerate(self._dense_slots):
            assert self._slots[slot][1] == dense
            assert self._slots[slot][0] >= 0
        assert set(self._free).isdisjoint(self._dense_slots)
        for slot, (gen, dense) in enumerate(self._slots):
            assert (dense is None) == (slot not in self._dense_slots)
            if dense is None and gen < MAX_GENERATION:
                assert slot in self._free
            if dense is None and gen == MAX_GENERATION:
                assert slot not in self._free
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
