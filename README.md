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

## Legacy migration provenance and gates

The original `ores-truffle-oreslang/oreslang-design-patterns` repository is archived; this AttoLang repository has a separate numeric GitHub identity. Historical `.ores` files, imports, package names and CLI identifiers are compatibility history, not evidence of current `.atto` execution. Curated design patterns and side-by-side testable idioms belong here; normative semantics and production backend implementation do not.

[atto-lang](https://github.com/atto-lang) owns language libraries, compilers, tooling, tests and examples; [atto-co](https://github.com/atto-co) owns hosted deployment, tenant infrastructure, identity and billing. A future original-ID transfer or product carve-out requires separate source/target owner and independent security approval. Inventory exact SHA/tree, numeric ID, visibility, permissions, protections, PRs, releases, packages, dependencies, runners, secrets, applications, webhooks, Pages and rollback owner; verify preservation and rerun exact-head tests after an actual transfer. Never mirror private source without authorization. Zero-step jobs are NOT_EXECUTED; host-only checks do not establish native guest/compiler execution.
