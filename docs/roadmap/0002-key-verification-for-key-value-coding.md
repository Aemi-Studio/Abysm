---
status: pending
blocked-by: 
date: 2026-10-20
---

# 0002 — Verified key-value coding for objects that accept any key

`CALayer` and `CAFilter` accept unknown keys silently (probed), so a renamed key is a no-op. A selector check cannot
verify a `CAFilter` input (`inputRadius` has no setter). Needs a per-class key source: `+[CAFilter filterTypes]` for the
type (both platforms), `inputKeys` where it exists (macOS), and for iOS a probe of what lists a filter's inputs.

## Probes

- Find any iOS-side list of filter input keys (`attributesForKey:` exists on macOS as a class method).
- Round trip: set then read back for each key AemiSDR uses; a key that does not read back is reported.

## What lands

A `KeyValidator` an adopter supplies per class, and a read-back check as the fallback.
