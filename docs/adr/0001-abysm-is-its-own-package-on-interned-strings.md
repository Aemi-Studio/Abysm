---
status: accepted
date: 2026-10-20
---

# 0001 — Abysm is its own package, built on InternedStrings

## Context

AemiSDR's runtime interop review (its diary 2026-10-20-01) found that `responds(to:)` + `perform` does not catch a changed
signature, unguarded KVC raises, and `@Interned` names decode on every read. A resolver that fixes all three is
generic: anything in the ecosystem that touches a runtime symbol needs it. The first proposal put it in Aemi; the
owner's direction was that InternedStrings should keep providing the easiest way to hold such names, and that the
ergonomic loading of runtime classes and methods should be a new package relying on it.

## Prior art, read and probed

| | Dynamic (mhdhejazi) | ABIBridge (lynnswap) | Abysm |
|---|---|---|---|
| Call style | `@dynamicMemberLookup` + `@dynamicCallable`, `NSInvocation` | resolved handle typed by a Swift function type, libffi | both: dynamic members and typed handles |
| Verifies signature | no (calls whatever is there) | yes, decodes runtime encodings | yes, compares encodings, typed error |
| Catches `NSException` | no | not documented | yes (shim) |
| Floor | old; last commit 2021, Apache-2.0 | iOS 18.4 / macOS 15.4 | iOS 18 / macOS 15 |
| Weight | one file | MachOKit, swift-objc-dump, libffi fork, C++ demangler | one ObjC file, Swift stdlib |
| Scope | ObjC | ObjC, Swift symbols, C++, hooks, SwiftUI hosting | ObjC runtime only |

ABIBridge's central idea — the Swift function type *is* the declaration, checked against the runtime — is the right one
and is adopted. Its scope and floor are wrong for a rendering library targeting applications at iOS 18.0, and the
white paper's first principle is that a binary links only what it uses. Dynamic's ergonomics are adopted; its lack of
verification is the defect Abysm exists to remove.

## Decision

- `Abysm` is a package of its own, depending on `InternedStrings` (re-exported) and nothing else.
- ObjC runtime only: classes, class and instance methods, properties, KVC. No hooks, no Swift mangled names.
- The call mechanism is `NSInvocation`, in a small ObjC target. Probed: Swift rejects a generic `@convention(c)` cast
  ("'(AnyObject, Selector, A) -> R' is not representable in Objective-C"), so a generic typed call needs either an
  Objective-C shim or libffi. The shim is smaller, is public API, and is the only place an `NSException` can be caught.
- Arity is generic through parameter packs (`RuntimeMethod<each Argument, Result>`), which compile at the iOS 18 floor.

## Consequences

- AemiSDR depends on Abysm instead of carrying a resolver (its ADR-0002), and TerminalKit, Ful or any other package that
  touches a runtime symbol gets the same checks.
- Abysm is pre-1.0; AemiSDR pins it by revision.
- `NSInvocation` costs more per call than a typed IMP. Measured in the diary; hot paths hold the result, not the call.
- Not yet covered: C functions (`dlsym` is used only to prove a class is exported), Swift symbols, hooking.
