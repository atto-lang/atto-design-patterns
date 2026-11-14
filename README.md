# atto-design-patterns

Idiomatic design patterns for actor-based, functional, and data-oriented AttoLang programs.

## What this project explores

Reusable design approaches, including actors, ownership, pipelines, and error handling.

## Pattern catalog

The [namespace-scoped actor receiver pattern](patterns/README.md) demonstrates `use namespace workers;`, two distinct actor declarations, `mtd` receivers and sealed state access. It is explicitly **syntax preview / not executed**. A checked-in JSON catalog and host-only Node tests enforce this distinction.

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
