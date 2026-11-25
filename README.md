> **AI agent instructions (organization-wide):** Before working on code, issues, or pull requests, read and follow the [organization `AGENTS.md`](https://github.com/atto-lang/.github/blob/main/AGENTS.md), including its **merge-first stealth-development policy**. Honor any repository-local `AGENTS.md`, explicit holds, and GitHub-enforced rules.

# atto-design-patterns

Idiomatic design patterns for actor-based, functional, and data-oriented AttoLang programs.

## Naming migration and language authority

This repository is maintained at [atto-lang/atto-design-patterns](https://github.com/atto-lang/atto-design-patterns); use `https://github.com/atto-lang/atto-design-patterns.git` for Git remotes and canonical `.atto` source examples. The normative language contract is [atto-spec](https://github.com/atto-lang/atto-spec), with executable guest evidence tracked by [atto-platform-conformance](https://github.com/atto-lang/atto-platform-conformance). Follow current ownership, borrowing, effects, actor, and syntax rules there; do not infer implemented features from a README or unexecuted CI.

## What this project explores

Reusable design approaches, including actors, ownership, pipelines, and error handling.

## How to use these examples

1. Check the repository contents for `.atto` examples and target-specific project manifests.
2. Use the compiler/backend indicated by each example's actual files and scripts.
3. Run checked-in tests or example commands only where documented and verified.
4. Record compiler revision, expected output, and actual result when reporting an issue.

## Portability and status

These examples are intended to demonstrate AttoLang concepts. Examples may depend on unfinished language features or particular backends; their presence is not evidence that every listed feature executes on all targets. Unsupported features should be marked in the individual example's documentation.

## Links

- [AttoLang repositories](https://github.com/atto-lang)
- [Canonical language specification](https://github.com/atto-lang/atto-spec)
- [Backend conformance](https://github.com/atto-lang/atto-platform-conformance)

## Repository ownership and contribution routing

**Belongs here:** Curated, explained .atto design patterns for actors, ownership, structured concurrency, immutable data and safe resource lifetimes.

**Belongs elsewhere:** Reusable production libraries live in their respective module repos; spec rules in atto-spec; exploratory spikes in atto-proof-of-concepts.

**Security and portability boundary:** Every pattern should carry the needed target, exact compiler head, expected output and tests including failure/cancellation/ownership cases, not an unverified portability claim.

AttoLang is the canonical project name; new source, examples and documentation use `.atto` and the `atto-lang` repository organization. This README defines scope, not feature readiness.

**Acceptance:** name exact source SHA/tree, runtime/toolchain, positive and negative checks and execution receipt before claiming support. Host-only tests and empty CI steps do not prove guest execution.

## Legacy provenance and transfer verification

The historical predecessor, `ores-truffle-oreslang/oreslang-design-patterns`, is archived; the current `atto-lang/atto-design-patterns` has a separate numeric GitHub repository ID. Preserve working legacy `.ores` examples and package/CLI aliases until their canonical `.atto` replacements are verified. Design pattern samples and side-by-side testable idioms belong here, not normative language semantics or production backend implementations. Historical or illustrative syntax is not a verified execution receipt.

[atto-lang](https://github.com/atto-lang) owns language and portable tooling; [atto-co](https://github.com/atto-co) separately governs managed infrastructure, tenant hosting, identity and billing. Any future original-ID transfer or commercial carve-out requires separate owner authorization and independent security review. Inventory exact SHA/tree, numeric ID, access, protections, PRs, releases, packages, runners, secrets, deploy keys, apps, webhooks, Pages, consumers and rollback ownership; verify identity and retest after an authorized transfer. Never mirror private source without authorization. Zero-step jobs are NOT_EXECUTED; host/reference checks are not compiled guest evidence.

## Pattern catalog

The [namespace-scoped actor receiver pattern](patterns/README.md) demonstrates `use namespace workers;`, two distinct actor declarations, `mtd` receivers and sealed state access. It is explicitly **syntax preview / not executed**. A checked-in JSON catalog and host-only Node tests enforce this distinction.

## Rust FSM reference migration (stage 1)

The [Rust host reference](tools/fsm-model/README.md) models bounded transitions, incarnation/generation fences, outbox credits, three physical layouts, loan exclusion and failure atomicity. The Python suite remains in place. Neither suite establishes native guest execution.
