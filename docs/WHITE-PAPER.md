# Abysm — Project White Paper

The rules this package runs on. **Paste this at the start of every iteration.** The ecosystem's law (the evidence rule,
red TDD, the performance doctrine, strictness, documentation law) is `ask`'s and TerminalKit's white paper, adapted
for AemiSDR; this is the copy for the package that makes runtime access safe to *use*. Where they disagree on a shared
principle, that is a defect to reconcile (Aemi ADR-0013 proposes one synced core).

## What Abysm promises

**A signature is a contract.** A selector that responds is not a selector that may be called. Every call is checked
against the runtime's own signature for the real class before it is sent, and a mismatch is an error value that names
both signatures (ADR-0002).

**Nothing the host cannot survive.** An `NSException` from runtime access is caught, never unwound through Swift. A
missing symbol degrades to `nil`/an error and is reported once at `.fault`. The host can switch it all off.

**Nothing silent.** Every resolution is recorded; a test can assert the whole set. A renamed symbol fails CI.

**Small.** One Objective-C file and Swift standard library. No libffi, no Mach-O parsing, no hooking: those are
ABIBridge's scope, and a binary links only what it uses.

## 0. The Evidence Rule

> **Every claim is challenged and backed by an actual probe before it is adopted or acted on.**

Name the claim → design a probe that would make it false → run it, record the command → record the verdict in the
diary → act. A probe that cannot fail is not a probe: every test here was run against a mutant that breaks the
behaviour it guards, and the mutant was seen to fail (diary 2026-10-20-01).

Claims specific to this package are about **runtimes**, not documentation: a selector's encoding, an image name, an
exception, a floor. Probe them on the floor runtime and the newest, on a simulator, and say which.

## 1. Red TDD

Red first, for the right reason; one behaviour per test, named in backticks as a sentence; red and green in one
commit; never assert on nothing. Global state (the policy switch, the resolution log) lives in one serialized suite.

## 2. Performance doctrine

Measured, release, median and spread with units. Numbers so far (diary): a resolved call ≈ 1.6 µs, a verified dynamic
member ≈ 1.9–2.3 µs, a hand-written typed IMP ≈ 96 ns. A hot path holds a resolved handle and never resolves per
frame. Verification verdicts are cached; every performance change is benchmarked before and after.

## 3. Safety

Strict memory safety, Swift 6 mode, warnings as errors, upcoming features as in the ecosystem. Every `unsafe` is at a
boundary the shim checks: sizes are compared with `NSMethodSignature` before bytes are copied. `NSObject` is not an
`ObjCValue`, only `Optional<NSObject>` is: a runtime method returning nil is routine and a non-optional would have to
invent an object (probed: the first draft did, with an `unsafeDowncast` of `NSNull`, which is undefined behaviour).

## 4. Documentation law

`docs/adr` one decision per file with `status:`; `docs/roadmap` one unit of work per file with `status:`;
`docs/diary` the probe history, at most 256 lines a file; this file at most 200 lines. Enforced by
`DocumentationLayoutTests`.

## 5. Bans

Unprobed claims. `perform(_:with:)` with a scalar. A call before its signature is verified. A recorded failure that is
only logged. Unbenchmarked performance changes. A dependency for convenience — a dependency is an architectural decision.
