# atto-design-patterns

Idiomatic design patterns for actor-based, functional, and data-oriented AttoLang programs.

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

AttoLang is the public name; preserve existing Oreslang/.ores compatibility and use canonical .atto for new portable library source. This README defines scope, not feature readiness.

**Acceptance:** name exact source SHA/tree, runtime/toolchain, positive and negative checks and execution receipt before claiming support. Host-only tests and empty CI steps do not prove guest execution.
