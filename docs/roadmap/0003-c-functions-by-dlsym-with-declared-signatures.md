---
status: pending
blocked-by: 
date: 2026-10-20
---

# 0003 — C functions by `dlsym`, with the declared signature as the contract

Abysm uses `dlsym` only to prove a class is exported. C functions need the same treatment: resolve once
with `dlsym`, and call through a typed cast of a closed set of shapes (a generic `@convention(c)` is not
representable, probed), refusing anything else.

## Probes

- Which C symbols AemiSDR or TerminalKit would use today, if any (none are called now).
- Whether `dlsym(RTLD_DEFAULT, …)` finds the symbol on the iOS 18.6 and 27.0 simulators for a few known candidates.

## What lands

`RuntimeFunction<each Argument, Result>` over the closed set, or an explicit decision that ABIBridge's libffi backend is
the right tool for that case and Abysm should say so.
