# Abysm

Typed Objective-C runtime interop for Swift: resolve classes, declare method signatures, and read or write properties.

Abysm checks runtime type encodings before invoking a selector, validates object results, and reports Objective-C
exceptions as Swift errors. A small `NSInvocation` bridge handles scalar, object and supported struct values.

## Install

Swift 6.3+, iOS 18+ or macOS 15+. Experimental; no stable release yet.

```swift
.package(url: "https://github.com/g-cqd/Abysm.git", branch: "main")
```

Use a reviewed `revision:` for reproducible builds.

## Typed methods

```swift
import Abysm
import Foundation

let numbers = try RuntimeClass("NSNumber")
let make = try numbers.method(
    "numberWithInteger:", kind: .class, as: ((Int) -> NSNumber?).self)
let answer = try make(42)
```

The Swift function type is the declaration. `(Int) -> NSNumber?` describes `@@:q`; declaring an object argument instead
of an integer throws `RuntimeError.signatureMismatch` before dispatch. Hold resolved handles for repeated calls.

An optional `Image` checks which framework defines a class. `exported: true` additionally checks its linker symbol.

## Dynamic properties

```swift
import QuartzCore

let layer = CALayer()
let object = RuntimeObject(layer)
object.cornerRadius = 12.0
let radius: Double? = object.cornerRadius

// Throwing forms explain a failed read or write.
let value: Double = try object.read("cornerRadius")
try object.write(18.0, to: "cornerRadius")
```

Missing or incompatible dynamic members return `nil` and record a diagnostic. The throwing forms preserve the reason.
Objects cross method boundaries as optionals, so nil results remain representable.

## Resolution reporting

`RuntimeAccess.resolutions` records each symbol and its result; `failures` selects unsuccessful resolutions.
Integration tests can inspect these records across supported OS versions.
Setting `RuntimeAccess.isEnabled = false` disables resolution and invocation, including previously resolved handles.

InternedStrings is re-exported for adopters that already use it to manage runtime names; ordinary strings work too.

## Interop limits

Object results are checked against the requested Swift class and retained through decoding. Standard Objective-C
ownership families (`alloc`, `new`, `copy`, `mutableCopy`, `init`) are balanced. Custom ownership attributes are
not in runtime type encodings and are **not supported**. Neither are variadic methods, blocks, or concurrent method
swizzling. Verification caches assume loaded classes and their method signatures stay unchanged.
Custom `ObjCValue` conformances are an unsafe interop contract: encoding, byte count and decoder must agree.

Abysm does not implement hooks, Swift symbol resolution or C++ dispatch. [ABIBridge](https://github.com/lynnswap/ABIBridge)
covers a broader range of interop use cases.

## Development and licence

See [ADRs](docs/adr), [probe diary](docs/diary), [roadmap](docs/roadmap) and [white paper](docs/WHITE-PAPER.md).
[MIT](LICENSE). Third-party dependencies retain their own licences.
