# Abysm

Typed, verified access to private Objective-C API, built on [InternedStrings](https://github.com/Aemi-Studio/aemi).

Private API fails in three ways, and the usual tools handle one of them:

| Failure | `responds(to:)` + `perform` | `value(forKey:)` | Abysm |
|---|---|---|---|
| The selector is gone | caught | raises `NSUnknownKeyException` | reported, never raised |
| The selector exists with another **signature** | **not caught**: the call runs with the wrong ABI | not applicable | refused: `signatureMismatch(expected: "@@:@", actual: "@@:q")` |
| The callee raises | crashes the process (Swift cannot catch it) | crashes | caught in a small Objective-C shim, reported |

The second row is not hypothetical. AemiSDR's `systemStyle(_:)` checked `responds(to: settingsForStyle:)`, then called it with
`perform(_:with:)`; the selector takes an `NSInteger`, so every preset silently resolved to the same fallback
(AemiSDR diary 2026-10-20-01).

## Use

```swift
import Abysm

// A class: image and exported symbol checked, once.
let filter = try PrivateClass("CAFilter", in: .quartzCore, exported: true)

// A method: the Swift function type IS the declaration. `(String) -> NSObject?` is the signature `@@:@`,
// compared with the runtime's before any call.
let make = try filter.method("filterWithType:", kind: .class, as: ((String) -> NSObject?).self)
let blur = try make("gaussianBlur")

// An object: dynamic members, each read or write checked against the real class.
let object = PrivateObject(layer)
let radius: Double? = object.cornerRadius          // getter `cornerRadius`, signature `d@:`
object.isHidden = true                              // setter `setHidden:`, signature `v@:B`

// Throwing forms say why.
let value: Int = try object.read("cornerRadius")   // throws signatureMismatch(expected: "q@:", actual: "d@:")
```

Names come from `@Interned` (re-exported), so they are absent from the binary's string table. Hold handles in a
`static let`: resolution runs once.

```swift
enum Names { @Interned static var settingsClass = "_UIBackdropViewSettings" }
enum Private {
    static let settings = try? PrivateClass(Names.settingsClass, in: .uiKitCore)
}
```

## Policy and the canary

- `PrivateAPI.isEnabled = false` makes every resolution throw `.disabled`: a host's App Review switch or a remote kill switch.
- Every resolution is recorded. A test that touches every symbol a package uses and asserts `PrivateAPI.failures.isEmpty`
  is a drift canary: run it on the floor and the newest OS runtime, and an OS update that renames a symbol fails CI, not a user.
- A failure is logged once per process at `.fault`; reads through `PrivateObject` degrade to `nil`.

## What it is not

- Not a hooking or swizzling library, and not a Swift-symbol or C++ resolver. For those, see
  [ABIBridge](https://github.com/lynnswap/ABIBridge), which is broader and heavier (libffi, MachOKit, iOS 18.4 floor).
- Not a way to make private API safe to ship: it makes it **detectable** and **degradable**. App Review is a policy question.

See [docs/adr](docs/adr) for the decisions and [docs/diary](docs/diary) for the probes behind them.
