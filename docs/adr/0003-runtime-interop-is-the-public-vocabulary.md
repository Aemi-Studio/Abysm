---
status: accepted
date: 2026-10-20
---

# 0003 — Describe the package as Objective-C runtime interop

## Context

The package resolves Objective-C classes, verifies selectors and transports values across the message boundary.
That mechanism is general-purpose. The owner requested neutral terminology throughout the repository.

## Decision

- Public types are `RuntimeClass`, `RuntimeObject`, `RuntimeMethod`, `RuntimeAction`, `RuntimeAccess` and `RuntimeError`.
- Examples demonstrate ordinary Foundation and QuartzCore objects.
- Documentation, tests, source filenames and diagnostics use the same vocabulary.
- InternedStrings remains available as a name-management helper; ordinary string names are equally supported.
- Signature checks, exception containment, receiver checks and object ownership rules are unchanged.

## Consequences

This is a source-breaking rename before a stable release. Consumers must migrate to the new names and pin the new revision.
No compatibility aliases are retained. Published commit history is not rewritten.
