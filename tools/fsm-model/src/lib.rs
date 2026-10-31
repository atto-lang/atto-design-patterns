//! Bounded, host-only FSM oracle. This is not native Oreslang execution.
use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::{AtomicU64, Ordering};

pub const MAX_VERSION: u8 = 7;
pub const MAX_GENERATION: u8 = 7;
pub const MAX_STATES: usize = 32;
pub const MAX_EVENTS: usize = 32;
pub const MAX_RULES: usize = 256;
pub const MAX_CAPACITY: usize = 64;
pub const MAX_LANES: usize = 16;
pub const MAX_OUTBOX: usize = 256;
static NEXT_INCAR: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdmissionError(pub &'static str);
pub type Admitted<T> = Result<T, AdmissionError>;

pub fn is_symbol(tag: &str) -> bool {
    let bytes = tag.as_bytes();
    bytes.len() >= 2
        && bytes.len() <= 128
        && bytes[0] == b'#'
        && (bytes[1].is_ascii_alphabetic() || bytes[1] == b'_')
        && bytes[2..]
            .iter()
            .all(|b| b.is_ascii_alphanumeric() || *b == b'_')
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Machine {
    pub state: String,
    pub version: u8,
}
impl Machine {
    pub fn new(state: &str, version: u8) -> Self {
        Self { state: state.to_owned(), version }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Outcome {
    pub machine: Machine,
    pub actions: Vec<String>,
    pub accepted: bool,
    pub reason: &'static str,
}
fn reject(machine: &Machine, reason: &'static str) -> Outcome {
    Outcome { machine: machine.clone(), actions: Vec::new(), accepted: false, reason }
}

#[derive(Clone, Debug)]
pub struct RuleTable {
    states: BTreeSet<String>,
    events: BTreeSet<String>,
    rules: BTreeMap<(String, String), (String, String)>,
}
impl RuleTable {
    pub fn new(states: &[&str], events: &[&str], rules: &[(&str, &str, &str, &str)]) -> Admitted<Self> {
        fn vocabulary(values: &[&str], bound: usize) -> Admitted<BTreeSet<String>> {
            if values.is_empty() || values.len() > bound || !values.iter().all(|s| is_symbol(s)) {
                return Err(AdmissionError("invalid vocabulary"));
            }
            let set: BTreeSet<_> = values.iter().map(|s| (*s).to_owned()).collect();
            if set.len() != values.len() { return Err(AdmissionError("duplicate symbol")); }
            Ok(set)
        }
        let states = vocabulary(states, MAX_STATES)?;
        let events = vocabulary(events, MAX_EVENTS)?;
        if rules.len() > MAX_RULES { return Err(AdmissionError("excessive rules")); }
        let mut table = BTreeMap::new();
        for &(from, event, to, action) in rules {
            if !states.contains(from) || !states.contains(to)
                || !events.contains(event) || !is_symbol(action) {
                return Err(AdmissionError("undeclared transition"));
            }
            if table.insert((from.to_owned(), event.to_owned()),
                (to.to_owned(), action.to_owned())).is_some() {
                return Err(AdmissionError("duplicate transition"));
            }
        }
        Ok(Self { states, events, rules: table })
    }
    pub fn edges(&self) -> &BTreeMap<(String, String), (String, String)> { &self.rules }
    pub fn has_state(&self, state: &str) -> bool { self.states.contains(state) }
}
pub fn demo_table() -> RuleTable {
    RuleTable::new(
        &["#idle", "#running", "#paused", "#done"],
        &["#start", "#pause", "#resume", "#stop", "#reset"],
        &[
            ("#idle", "#start", "#running", "#started"),
            ("#running", "#pause", "#paused", "#paused_event"),
            ("#paused", "#resume", "#running", "#resumed"),
            ("#running", "#stop", "#done", "#stopped"),
            ("#paused", "#stop", "#done", "#stopped"),
            ("#done", "#reset", "#idle", "#reset_event"),
        ],
    ).expect("closed reference rules")
}
pub fn step(table: &RuleTable, machine: &Machine, event: &str,
            guard: bool, action_credits: i32) -> Outcome {
    if !is_symbol(&machine.state) || !table.states.contains(&machine.state)
        || machine.version > MAX_VERSION {
        return reject(machine, "invalid-machine");
    }
    if !is_symbol(event) || !table.events.contains(event) {
        return reject(machine, "undeclared-event");
    }
    let Some((to, action)) = table.rules.get(&(machine.state.clone(), event.to_owned())) else {
        return reject(machine, "no-rule");
    };
    if !guard { return reject(machine, "guard"); }
    if action_credits < 1 { return reject(machine, "effect-capacity"); }
    if machine.version == MAX_VERSION { return reject(machine, "version-overflow"); }
    Outcome {
        machine: Machine::new(to, machine.version + 1),
        actions: vec![action.clone()], accepted: true, reason: "",
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Layout { Aos, Soa, Aosoa }

#[derive(Clone, Debug)]
enum Storage {
    Aos(Vec<Machine>),
    Soa { states: Vec<String>, versions: Vec<u8> },
    Aosoa(Vec<Vec<Option<Machine>>>),
}
impl Storage {
    fn from_rows(rows: &[Machine], layout: Layout, lanes: usize) -> Self {
        match layout {
            Layout::Aos => Self::Aos(rows.to_vec()),
            Layout::Soa => Self::Soa {
                states: rows.iter().map(|r| r.state.clone()).collect(),
                versions: rows.iter().map(|r| r.version).collect(),
            },
            Layout::Aosoa => {
                let mut chunks = Vec::new();
                for row in rows.chunks(lanes) {
                    let mut chunk: Vec<Option<Machine>> = row.iter().cloned().map(Some).collect();
                    chunk.resize(lanes, None);
                    chunks.push(chunk);
                }
                Self::Aosoa(chunks)
            }
        }
    }
    fn rows(&self) -> Vec<Machine> {
        match self {
            Self::Aos(rows) => rows.clone(),
            Self::Soa { states, versions } => states.iter().zip(versions.iter())
                .map(|(s, v)| Machine::new(s, *v)).collect(),
            Self::Aosoa(chunks) => chunks.iter().flat_map(|c| c.iter().flatten().cloned()).collect(),
        }
    }
    fn shape_valid(&self, len: usize, lanes: usize) -> bool {
        match self {
            Self::Aos(r) => r.len() == len,
            Self::Soa { states, versions } => states.len() == len && versions.len() == len,
            Self::Aosoa(chunks) => chunks.len() == len.div_ceil(lanes)
                && chunks.iter().flatten().enumerate()
                    .all(|(i, r)| r.is_some() == (i < len)),
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Handle {
    owner: u64,
    slot: usize,
    generation: u8,
    incarnation: u64,
    issuer: u64,
}
#[derive(Clone, Debug)]
struct Slot { generation: u8, dense: Option<usize> }

/// Store identity must never be copied into another independently mutable
/// public instance. Internal staged snapshots are private transaction details.
///
/// A public Clone impl would duplicate the issuer and incarnation, letting
/// previously minted handles authorize access to *both* stores.
///
/// ```compile_fail
/// use ores_fsm_reference::{Layout, LayoutStore};
/// let store = LayoutStore::new(Layout::Aos, 2, 1, 4, 8).unwrap();
/// let duplicate = store.clone(); // forbidden: two stores with same issuer
/// ```
///
/// ```compile_fail
/// use ores_fsm_reference::{Layout, LayoutStore};
/// let mut store = LayoutStore::new(Layout::Aos, 2, 1, 4, 8).unwrap();
/// // Staged transaction references must never escape to public callers.
/// let _ = store.inject_precommit_failure(|staged| staged.insert(
///     ores_fsm_reference::Machine::new("#idle", 0)
/// ));
/// ```
#[derive(Debug)]
pub struct LayoutStore {
    layout: Layout,
    storage: Storage,
    capacity: usize,
    owner: u64,
    lanes: usize,
    incarnation: u64,
    issuer: u64,
    slots: Vec<Slot>,
    free: Vec<usize>,
    dense_slots: Vec<usize>,
    outbox: Vec<(Handle, String)>,
    outbox_capacity: usize,
    loans: usize,
}
impl LayoutStore {
    // Private snapshot is only used inside atomic_mutation. Never expose a
    // cloneable store: the issuer is a one-store capability domain.
    fn staged_snapshot(&self) -> Self {
        Self {
            layout: self.layout,
            storage: self.storage.clone(),
            capacity: self.capacity,
            owner: self.owner,
            lanes: self.lanes,
            incarnation: self.incarnation,
            issuer: self.issuer,
            slots: self.slots.clone(),
            free: self.free.clone(),
            dense_slots: self.dense_slots.clone(),
            outbox: self.outbox.clone(),
            outbox_capacity: self.outbox_capacity,
            loans: self.loans,
        }
    }
    pub fn new(layout: Layout, capacity: usize, owner: u64,
               lanes: usize, outbox_capacity: usize) -> Admitted<Self> {
        if capacity > MAX_CAPACITY || owner == 0 || !(1..=MAX_LANES).contains(&lanes)
            || outbox_capacity > MAX_OUTBOX {
            return Err(AdmissionError("invalid configuration"));
        }
        // Fail closed forever on u64 exhaustion. fetch_add would wrap and
        // eventually reuse an old store incarnation/issuer.
        let nonce = NEXT_INCAR.fetch_update(Ordering::Relaxed, Ordering::Relaxed,
            |current| current.checked_add(1))
            .map_err(|_| AdmissionError("incarnation exhausted"))?;
        Ok(Self {
            layout, storage: Storage::from_rows(&[], layout, lanes),
            capacity, owner, lanes, incarnation: nonce, issuer: nonce,
            slots: Vec::new(), free: Vec::new(), dense_slots: Vec::new(),
            outbox: Vec::new(), outbox_capacity, loans: 0,
        })
    }
    pub fn len(&self) -> usize { self.dense_slots.len() }
    pub fn is_empty(&self) -> bool { self.dense_slots.is_empty() }
    pub fn layout(&self) -> Layout { self.layout }
    pub fn queued_actions(&self) -> &[(Handle, String)] { &self.outbox }
    fn exclusive(&self) -> Admitted<()> {
        if self.loans > 0 { Err(AdmissionError("active borrow")) } else { Ok(()) }
    }
    fn resolve(&self, h: &Handle) -> Admitted<usize> {
        if h.owner != self.owner || h.incarnation != self.incarnation
            || h.issuer != self.issuer || h.generation > MAX_GENERATION {
            return Err(AdmissionError("foreign handle"));
        }
        let Some(slot) = self.slots.get(h.slot) else { return Err(AdmissionError("out of bounds")); };
        let Some(dense) = slot.dense else { return Err(AdmissionError("stale handle")); };
        if slot.generation != h.generation || self.dense_slots.get(dense) != Some(&h.slot) {
            return Err(AdmissionError("stale handle"));
        }
        Ok(dense)
    }
    pub fn read(&self, h: &Handle) -> Admitted<Machine> {
        let dense = self.resolve(h)?;
        self.storage.rows().get(dense).cloned().ok_or(AdmissionError("invalid dense index"))
    }
    // Reference-only O(n) snapshot transaction: stage all writes and publish
    // as one logical operation. Failed closures/panics never touch the live store.
    fn atomic_mutation<T, F, P>(&mut self, mutate: F, before_publish: P) -> Admitted<T>
    where
        F: FnOnce(&mut Self) -> Admitted<T>,
        P: FnOnce() -> Admitted<()>,
    {
        self.exclusive()?;
        let mut staged = self.staged_snapshot();
        let output = mutate(&mut staged)?;
        before_publish()?;
        *self = staged;
        Ok(output)
    }

    pub fn insert(&mut self, machine: Machine) -> Admitted<Handle> {
        self.atomic_mutation(|staged| staged.insert_raw(machine), || Ok(()))
    }
    fn insert_raw(&mut self, machine: Machine) -> Admitted<Handle> {
        self.exclusive()?;
        if self.len() >= self.capacity {
            return Err(AdmissionError("capacity exhausted"));
        }
        if self.free.is_empty() && self.slots.len() >= self.capacity {
            // All remaining physical slots may be permanently retired after
            // generation exhaustion; expanding the table would violate the
            // bounded store contract even though no live row remains.
            return Err(AdmissionError("retired slots exhausted"));
        }
        if !is_symbol(&machine.state) || machine.version > MAX_VERSION {
            return Err(AdmissionError("invalid machine"));
        }
        let slot_id = self.free.pop().unwrap_or(self.slots.len());
        if slot_id == self.slots.len() {
            self.slots.push(Slot { generation: 0, dense: None });
        }
        let dense = self.len();
        let h = Handle { owner: self.owner, slot: slot_id,
            generation: self.slots[slot_id].generation,
            incarnation: self.incarnation, issuer: self.issuer };
        let mut rows = self.storage.rows();
        rows.push(machine);
        self.storage = Storage::from_rows(&rows, self.layout, self.lanes);
        self.slots[slot_id].dense = Some(dense);
        self.dense_slots.push(slot_id);
        Ok(h)
    }
    pub fn remove(&mut self, h: &Handle) -> Admitted<Machine> {
        self.atomic_mutation(|staged| staged.remove_raw(h), || Ok(()))
    }
    fn remove_raw(&mut self, h: &Handle) -> Admitted<Machine> {
        self.exclusive()?;
        let dense = self.resolve(h)?;
        let mut rows = self.storage.rows();
        let old = rows.swap_remove(dense);
        let removed_slot = self.dense_slots.swap_remove(dense);
        debug_assert_eq!(removed_slot, h.slot);
        if dense < self.len() {
            let moved = self.dense_slots[dense];
            self.slots[moved].dense = Some(dense);
        }
        let slot = &mut self.slots[h.slot];
        slot.dense = None;
        if slot.generation + 1 < MAX_GENERATION {
            slot.generation += 1;
            self.free.push(h.slot);
        } else {
            slot.generation = MAX_GENERATION;
        }
        self.storage = Storage::from_rows(&rows, self.layout, self.lanes);
        Ok(old)
    }
    pub fn apply(&mut self, h: &Handle, table: &RuleTable, event: &str,
                 guard: bool, credits: i32) -> Admitted<Outcome> {
        self.atomic_mutation(|staged| staged.apply_raw(h, table, event, guard, credits), || Ok(()))
    }
    fn apply_raw(&mut self, h: &Handle, table: &RuleTable, event: &str,
                 guard: bool, credits: i32) -> Admitted<Outcome> {
        self.exclusive()?;
        let dense = self.resolve(h)?;
        let mut rows = self.storage.rows();
        let available = if credits < 0 { 0 } else {
            credits.min(self.outbox_capacity.saturating_sub(self.outbox.len()) as i32)
        };
        let outcome = step(table, &rows[dense], event, guard, available);
        if outcome.accepted {
            // Both updates are staged before publishing: no partial outbox/state.
            rows[dense] = outcome.machine.clone();
            let staged = Storage::from_rows(&rows, self.layout, self.lanes);
            self.storage = staged;
            self.outbox.push((h.clone(), outcome.actions[0].clone()));
        }
        Ok(outcome)
    }
    pub fn drain_actions(&mut self, limit: usize) -> Admitted<Vec<(Handle, String)>> {
        self.atomic_mutation(|staged| staged.drain_raw(limit), || Ok(()))
    }
    fn drain_raw(&mut self, limit: usize) -> Admitted<Vec<(Handle, String)>> {
        self.exclusive()?;
        Ok(self.outbox.drain(..limit.min(self.outbox.len())).collect())
    }
    pub fn relayout(&mut self, layout: Layout, lanes: usize) -> Admitted<()> {
        self.atomic_mutation(|staged| staged.relayout_raw(layout, lanes), || Ok(()))
    }
    fn relayout_raw(&mut self, layout: Layout, lanes: usize) -> Admitted<()> {
        self.exclusive()?;
        if !(1..=MAX_LANES).contains(&lanes) { return Err(AdmissionError("invalid lanes")); }
        let staged = Storage::from_rows(&self.storage.rows(), layout, lanes);
        self.storage = staged;
        self.layout = layout;
        self.lanes = lanes;
        Ok(())
    }
    pub fn with_read_loan<F, T>(&mut self, callback: F) -> T where F: FnOnce(&mut Self) -> T {
        self.loans += 1;
        // Match Python's try/finally: a panicking observer must release its loan.
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| callback(self)));
        self.loans -= 1;
        match result {
            Ok(value) => value,
            Err(payload) => std::panic::resume_unwind(payload),
        }
    }
    pub fn invariants_hold(&self) -> bool {
        let active: BTreeSet<_> = self.dense_slots.iter().copied().collect();
        let free: BTreeSet<_> = self.free.iter().copied().collect();
        self.len() <= self.capacity
            && self.slots.len() <= self.capacity
            && self.storage.shape_valid(self.len(), self.lanes)
            && matches!((self.layout, &self.storage),
                (Layout::Aos, Storage::Aos(_))
                    | (Layout::Soa, Storage::Soa { .. })
                    | (Layout::Aosoa, Storage::Aosoa(_)))
            && active.len() == self.len() && free.len() == self.free.len()
            && active.is_disjoint(&free)
            && self.outbox.len() <= self.outbox_capacity
            && self.dense_slots.iter().enumerate()
                .all(|(i, &s)| self.slots.get(s).is_some_and(|x| x.dense == Some(i)))
            && self.slots.iter().enumerate().all(|(i, s)| {
                s.generation <= MAX_GENERATION
                    && match s.dense {
                        Some(d) => self.dense_slots.get(d) == Some(&i),
                        None if s.generation < MAX_GENERATION => free.contains(&i),
                        None => !free.contains(&i),
                    }
            })
            && self.outbox.iter().all(|(h, action)| {
                h.owner == self.owner && h.incarnation == self.incarnation
                    && h.issuer == self.issuer && is_symbol(action)
            })
    }
}
pub fn ecs_tick(store: &mut LayoutStore, table: &RuleTable,
                events: &[(Handle, &str)]) -> Admitted<Vec<Outcome>> {
    events.iter().map(|(h, e)| store.apply(h, table, e, true, 1)).collect()
}

#[cfg(test)]
mod internal_rollback_tests {
    use super::*;

    fn fixture(layout: Layout) -> LayoutStore {
        LayoutStore::new(layout, 3, 13, 3, 2).unwrap()
    }

    fn denied() -> Admitted<()> {
        Err(AdmissionError("injected precommit failure"))
    }

    #[test]
    fn rejected_staged_insert_remove_apply_relayout_and_outbox_are_atomic() {
        let table = demo_table();
        for layout in [Layout::Aos, Layout::Soa, Layout::Aosoa] {
            let mut store = fixture(layout);
            let a = store.insert(Machine::new("#idle", 0)).unwrap();
            let b = store.insert(Machine::new("#running", 2)).unwrap();
            let before = (
                store.read(&a).unwrap(),
                store.read(&b).unwrap(),
                store.len(),
                store.layout(),
                store.queued_actions().to_vec(),
            );
            assert!(store.atomic_mutation(
                |staged| staged.insert_raw(Machine::new("#paused", 1)),
                denied,
            ).is_err());
            assert!(store.atomic_mutation(
                |staged| staged.remove_raw(&a),
                denied,
            ).is_err());
            assert!(store.atomic_mutation(
                |staged| staged.apply_raw(&a, &table, "#start", true, 1),
                denied,
            ).is_err());
            assert!(store.atomic_mutation(
                |staged| staged.relayout_raw(Layout::Aosoa, 2),
                denied,
            ).is_err());
            assert_eq!((
                store.read(&a).unwrap(),
                store.read(&b).unwrap(),
                store.len(),
                store.layout(),
                store.queued_actions().to_vec(),
            ), before);
            assert!(store.invariants_hold());

            assert!(store.apply(&a, &table, "#start", true, 1).unwrap().accepted);
            let outbox = store.queued_actions().to_vec();
            assert!(store.atomic_mutation(
                |staged| staged.apply_raw(&b, &table, "#pause", true, 1),
                denied,
            ).is_err());
            assert_eq!(store.queued_actions(), outbox.as_slice());
            assert_eq!(store.read(&b).unwrap(), Machine::new("#running", 2));
            assert!(store.invariants_hold());
        }
    }

    #[test]
    fn panic_during_staged_mutation_never_publishes_partial_store() {
        for layout in [Layout::Aos, Layout::Soa, Layout::Aosoa] {
            let mut store = fixture(layout);
            let a = store.insert(Machine::new("#idle", 0)).unwrap();
            let previous = store.read(&a).unwrap();
            let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let _: Admitted<()> = store.atomic_mutation(
                    |staged| {
                        staged.remove_raw(&a).unwrap();
                        panic!("injected partial mutation");
                    },
                    || Ok(()),
                );
            }));
            assert!(panic.is_err());
            assert_eq!(store.read(&a).unwrap(), previous);
            assert!(store.invariants_hold());
        }
    }

    #[test]
    fn public_mutation_can_reuse_a_slot_only_after_a_committed_transaction() {
        let mut store = fixture(Layout::Aosoa);
        let a = store.insert(Machine::new("#idle", 0)).unwrap();
        assert!(store.atomic_mutation(
            |staged| staged.remove_raw(&a),
            denied,
        ).is_err());
        // A rolled-back remove cannot retire a committed handle.
        assert_eq!(store.read(&a).unwrap(), Machine::new("#idle", 0));
        store.remove(&a).unwrap();
        assert!(store.read(&a).is_err());
        let b = store.insert(Machine::new("#idle", 0)).unwrap();
        assert_ne!(a, b);
        assert!(store.invariants_hold());
    }
}
