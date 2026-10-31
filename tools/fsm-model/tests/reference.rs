use ores_fsm_reference::{
    demo_table, ecs_tick, is_symbol, step, Layout, LayoutStore, Machine, RuleTable,
    MAX_GENERATION, MAX_VERSION,
};
use std::collections::BTreeMap;

const SOURCE: &str = include_str!("../../../examples/fsm/01-symbol-reducer.ores");
const EVENTS: [&str; 5] = ["#start", "#pause", "#resume", "#stop", "#reset"];
const LAYOUTS: [Layout; 3] = [Layout::Aos, Layout::Soa, Layout::Aosoa];

fn machine(state: &str, version: u8) -> Machine { Machine::new(state, version) }
fn store(layout: Layout, capacity: usize, outbox: usize) -> LayoutStore {
    LayoutStore::new(layout, capacity, 13, 3, outbox).unwrap()
}

#[test]
fn source_edges_match_immutable_reference_table() {
    // This is a deliberately strict source-shape guard, NOT an Oreslang parser.
    let lines: Vec<_> = SOURCE.lines().map(str::trim).collect();
    let mut found: BTreeMap<(String, String), String> = BTreeMap::new();
    let mut guards = 0;
    for (index, line) in lines.iter().enumerate() {
        if !line.starts_with("if state ==") { continue; }
        guards += 1;
        let body = line.strip_prefix("if state == ").unwrap();
        let (src, rest) = body.split_once(" && event == ").expect("known guard form");
        let event = rest.strip_suffix(" then").expect("known guard end");
        let dest = lines.get(index + 1).expect("return line")
            .strip_prefix("return ").expect("transition return")
            .strip_suffix(';').expect("terminated return");
        assert_eq!(lines.get(index + 2), Some(&"fi"), "explicit guard terminator");
        assert!(is_symbol(src) && is_symbol(event) && is_symbol(dest));
        assert!(found.insert((src.to_owned(), event.to_owned()), dest.to_owned()).is_none());
    }
    let expected: BTreeMap<_, _> = demo_table().edges().iter()
        .map(|(edge, (to, _))| (edge.clone(), to.clone())).collect();
    assert_eq!(guards, expected.len(), "unrecognized or missing guard");
    assert_eq!(found, expected);
    assert!(SOURCE.contains("return #rejected;"));
    assert!(SOURCE.contains("define module fsm_symbol_reducer as"));
    assert!(SOURCE.contains("pub routine main(): void"));
    assert!(!demo_table().has_state("#rejected"), "sentinel cannot become a live state");
}

#[test]
fn table_admission_rejects_duplicates_unknowns_and_malformed_symbols() {
    assert!(is_symbol("#snake_case9"));
    for tag in ["#", "no_hash", "#1illegal", "#bad-name", "#not valid"] {
        // Rust cannot construct Unicode surrogate scalar values, unlike Python;
        // use ordinary invalid Unicode as the portable negative test instead.
        assert!(!is_symbol(tag));
    }
    assert!(!is_symbol("#💥"));
    assert!(!is_symbol(&format!("#{}", "a".repeat(128))));
    assert!(RuleTable::new(&["#idle", "#idle"], &["#start"], &[]).is_err());
    assert!(RuleTable::new(&["#idle"], &["#start", "#start"], &[]).is_err());
    assert!(RuleTable::new(&["#idle"], &["#start"],
        &[("#idle", "#start", "#unknown", "#effect")]).is_err());
    assert!(RuleTable::new(&["#idle"], &["#start"], &[
        ("#idle", "#start", "#idle", "#effect"),
        ("#idle", "#start", "#idle", "#duplicate")
    ]).is_err());
}

#[test]
fn guarded_rejections_preserve_machine_version_and_effects() {
    let table = demo_table();
    let initial = machine("#idle", 2);
    for (event, guard, credits, why) in [
        ("#stop", true, 1, "no-rule"),
        ("#bogus", true, 1, "undeclared-event"),
        ("#start", false, 1, "guard"),
        ("#start", true, 0, "effect-capacity"),
        ("#start", true, -1, "effect-capacity"),
    ] {
        let result = step(&table, &initial, event, guard, credits);
        assert!(!result.accepted);
        assert_eq!(result.reason, why);
        assert_eq!(result.machine, initial);
        assert!(result.actions.is_empty());
    }
    assert_eq!(step(&table, &machine("#idle", MAX_VERSION), "#start", true, 1).reason,
        "version-overflow");
    let result = step(&table, &machine("#idle", 0), "#start", true, 1);
    assert_eq!(result.machine, machine("#running", 1));
    assert_eq!(result.actions, ["#started"]);
}

#[test]
fn exhaustive_bounded_trace_equivalence_three_physical_layouts() {
    let table = demo_table();
    let mut cases = 0;
    for length in 0..=4 {
        let n = 5usize.pow(length);
        for encoded in 0..n {
            cases += 1;
            let mut trace = Vec::new();
            let mut cursor = encoded;
            for _ in 0..length { trace.push(EVENTS[cursor % 5]); cursor /= 5; }
            let mut expected = machine("#idle", 0);
            let mut outcomes = Vec::new();
            for event in &trace {
                let result = step(&table, &expected, event, true, 1);
                expected = result.machine.clone();
                outcomes.push((result.accepted, result.actions, result.reason));
            }
            for layout in LAYOUTS {
                let mut s = store(layout, 1, 64);
                let h = s.insert(machine("#idle", 0)).unwrap();
                let mut got = Vec::new();
                for event in &trace {
                    let result = s.apply(&h, &table, event, true, 1).unwrap();
                    got.push((result.accepted, result.actions, result.reason));
                }
                assert_eq!(s.read(&h).unwrap(), expected);
                assert_eq!(got, outcomes);
                assert!(s.invariants_hold());
            }
        }
    }
    assert_eq!(cases, 781);
}

#[test]
fn interleaved_entities_are_order_preserving_and_independent() {
    let table = demo_table();
    let a_events = ["#start", "#pause", "#resume"];
    let b_events = ["#start", "#stop", "#reset"];
    let mut combinations = 0;
    for x in 0..6 {
        for y in x + 1..6 {
            for z in y + 1..6 {
                combinations += 1;
                for layout in LAYOUTS {
                    let mut s = store(layout, 2, 64);
                    let a = s.insert(machine("#idle", 0)).unwrap();
                    let b = s.insert(machine("#idle", 0)).unwrap();
                    let mut ai = 0;
                    let mut bi = 0;
                    let mut scheduled = Vec::new();
                    for pos in 0..6 {
                        if [x, y, z].contains(&pos) {
                            scheduled.push((a.clone(), a_events[ai])); ai += 1;
                        } else {
                            scheduled.push((b.clone(), b_events[bi])); bi += 1;
                        }
                    }
                    assert!(ecs_tick(&mut s, &table, &scheduled).unwrap()
                        .iter().all(|o| o.accepted));
                    assert_eq!(s.read(&a).unwrap(), machine("#running", 3));
                    assert_eq!(s.read(&b).unwrap(), machine("#idle", 3));
                    assert!(s.invariants_hold());
                }
            }
        }
    }
    assert_eq!(combinations, 20);
}

#[test]
fn swap_delete_and_store_recreation_fence_aba_handles() {
    for layout in LAYOUTS {
        let mut s = store(layout, 3, 64);
        let a = s.insert(machine("#idle", 0)).unwrap();
        let b = s.insert(machine("#running", 2)).unwrap();
        let c = s.insert(machine("#paused", 1)).unwrap();
        assert_eq!(s.remove(&b).unwrap(), machine("#running", 2));
        assert_eq!(s.read(&c).unwrap(), machine("#paused", 1));
        assert!(s.read(&b).is_err());
        let d = s.insert(machine("#done", 3)).unwrap();
        assert_ne!(d, b);
        assert!(s.read(&b).is_err());
        assert_eq!(s.read(&a).unwrap(), machine("#idle", 0));
        assert_eq!(s.read(&d).unwrap(), machine("#done", 3));
        let mut fresh = store(layout, 3, 64);
        fresh.insert(machine("#idle", 0)).unwrap();
        assert!(fresh.read(&a).is_err());
        assert!(s.invariants_hold());
    }
}

#[test]
fn generation_retirement_is_terminal_and_never_wraps() {
    let mut s = store(Layout::Aosoa, 1, 32);
    for _ in 0..usize::from(MAX_GENERATION) {
        let h = s.insert(machine("#idle", 0)).unwrap();
        s.remove(&h).unwrap();
        assert!(s.read(&h).is_err());
        assert!(s.invariants_hold());
    }
    assert!(s.insert(machine("#idle", 0)).is_err());
}

#[test]
fn outbox_reservation_guard_loan_and_relayout_fail_closed() {
    let table = demo_table();
    for layout in LAYOUTS {
        let mut s = store(layout, 2, 1);
        let h = s.insert(machine("#idle", 0)).unwrap();
        assert!(s.apply(&h, &table, "#start", true, 1).unwrap().accepted);
        let unchanged = s.read(&h).unwrap();
        assert!(!s.apply(&h, &table, "#pause", true, 1).unwrap().accepted);
        assert_eq!(s.read(&h).unwrap(), unchanged);
        assert_eq!(s.queued_actions().len(), 1);
        s.with_read_loan(|locked| {
            assert!(locked.insert(machine("#idle", 0)).is_err());
            assert!(locked.remove(&h).is_err());
            assert!(locked.apply(&h, &table, "#pause", true, 1).is_err());
            assert!(locked.relayout(Layout::Aosoa, 4).is_err());
            assert_eq!(locked.read(&h).unwrap(), unchanged);
        });
        s.relayout(Layout::Soa, 4).unwrap();
        s.relayout(Layout::Aosoa, 3).unwrap();
        s.relayout(Layout::Aos, 2).unwrap();
        assert_eq!(s.read(&h).unwrap(), unchanged);
        assert_eq!(s.queued_actions().len(), 1);
        assert_eq!(s.drain_actions(1).unwrap().len(), 1);
        assert!(s.apply(&h, &table, "#pause", true, 1).unwrap().accepted);
        assert!(s.invariants_hold());
    }
}

#[test]
fn malformed_and_over_capacity_admission_never_changes_slots() {
    for layout in LAYOUTS {
        let mut s = store(layout, 1, 0);
        assert!(s.insert(machine("no_hash", 0)).is_err());
        assert_eq!(s.len(), 0);
        let h = s.insert(machine("#idle", 0)).unwrap();
        assert!(s.insert(machine("#running", 0)).is_err());
        assert!(!s.apply(&h, &demo_table(), "#start", true, 1).unwrap().accepted);
        assert_eq!(s.read(&h).unwrap(), machine("#idle", 0));
        assert!(s.invariants_hold());
    }
    assert!(LayoutStore::new(Layout::Aos, 65, 1, 4, 64).is_err());
    assert!(LayoutStore::new(Layout::Aos, 1, 0, 4, 64).is_err());
    assert!(LayoutStore::new(Layout::Aosoa, 1, 1, 0, 64).is_err());
    assert!(LayoutStore::new(Layout::Aosoa, 1, 1, 17, 64).is_err());
    assert!(LayoutStore::new(Layout::Aos, 1, 1, 4, 257).is_err());
}

#[test]
fn deterministic_corpus_has_no_implicit_global_scheduler_state() {
    let table = demo_table();
    for layout in LAYOUTS {
        let mut s = store(layout, 5, 256);
        let mut seed: u64 = 20261019;
        let mut handles = Vec::new();
        for _ in 0..260 {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            match seed % 5 {
                0 if handles.len() < 5 => {
                    if let Ok(h) = s.insert(machine("#idle", 0)) { handles.push(h); }
                },
                1 if !handles.is_empty() => {
                    let h = handles[(seed as usize) % handles.len()].clone();
                    let e = EVENTS[(seed as usize / 5) % EVENTS.len()];
                    let _ = s.apply(&h, &table, e, true, 1).unwrap();
                },
                2 if !handles.is_empty() => {
                    let index = (seed as usize) % handles.len();
                    let h = handles.swap_remove(index);
                    s.remove(&h).unwrap();
                    assert!(s.read(&h).is_err());
                },
                3 => { s.relayout(LAYOUTS[(seed as usize / 5) % 3], 3).unwrap(); },
                _ => { s.drain_actions(2).unwrap(); },
            }
            assert!(s.invariants_hold());
            assert_eq!(s.len(), handles.len());
        }
    }
}

#[test]
fn mutation_guard_bypass_is_detected_by_oracle() {
    let table = demo_table();
    let m = machine("#idle", 0);
    let real = step(&table, &m, "#start", false, 1);
    let mutant = step(&table, &m, "#start", true, 1);
    assert!(!real.accepted);
    assert!(mutant.accepted);
    assert_ne!(real.machine, mutant.machine);
}
