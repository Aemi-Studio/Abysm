---
status: accepted
date: 2026-10-20
---

# 0002 — The signature is the contract, and a mismatch is an error value

## Context

A selector that responds is not a selector that may be called: `+[_UIBackdropViewSettings settingsForStyle:]` responds, has
encoding `@24@0:8q16`, and `perform(_:with:)` passes an object where an integer is expected. Nothing raised; every
preset resolved to the same fallback.

## Decision

- A declaration is a Swift function type. Each parameter and the result are `ObjCValue`s that state their own encoding
  (`Int` is `q`, `Double` `d`, `Bool` `B`, `CGRect` `{CGRect={CGPoint=dd}{CGSize=dd}}`, an object `@`).
- The runtime's signature (`abysm_signature`: return type, receiver, selector, arguments, offsets removed) must equal
  `result + "@:" + arguments`. Otherwise `RuntimeError.signatureMismatch(expected:, actual:)`, with both strings.
- Sizes are checked again in the shim against `NSMethodSignature` before an argument is copied, so a wrong declaration
  that somehow passed cannot overrun a buffer.
- Objects are `Optional`-only: a runtime method returning nil is routine, and a non-optional would have to invent an object.
- Structs are declared by the adopter (`ObjCValue` + `BitwiseCopyable` + an encoding). Probed: a 4×`CGSize` struct return
  (`_UICornerInsets`) cannot be expressed as a Swift `@convention(c)` type at all; through the shim it is one declaration.
- Verification is exact. A looser match (ignoring struct tag names) is a later, measured decision, not a default.

## Evidence

Eighteen tests run on macOS; two mutants were killed: disabling the comparison fails four tests, and removing the
`@catch` kills the test process with an uncaught `NSRangeException`.
