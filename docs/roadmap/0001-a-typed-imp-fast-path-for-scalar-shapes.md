---
status: pending
blocked-by: 
date: 2026-10-20
---

# 0001 — A typed-IMP fast path for the common scalar shapes

Resolved calls cost ~1.6 µs, dominated by `NSInvocation` and argument buffers; a hand-written typed IMP is ~96 ns.
Most runtime calls in AemiSDR are `()`, `(Bool)`, `(Double)`, `(object)` and `() -> Double/Bool/object`.

## Probes

- Allocations per call (malloc hook, as Aemi's `expectAllocations`): count for `RuntimeAction` today.
- A closed set of concrete `@convention(c)` shapes selected by the declared encodings, falling back to `NSInvocation`.
- Equality: the fast path and the shim return identical results for the same declaration (characterisation tests).

## What lands

The fast path for the closed set, with the numbers before and after in the diary.
