import CoreGraphics
import Foundation
import QuartzCore
import Testing

@testable import Abysm

/// One serialized suite: the policy switch and the resolution log are process-wide.
@Suite("Abysm", .serialized)
struct AbysmTests {
    init() { PrivateAPI.resetResolutions() }

    // MARK: Classes

    @Test func `a private class resolves with its image and its exported symbol checked`() throws {
        let filter = try PrivateClass("CAFilter", in: .quartzCore, exported: true)
        #expect(filter.name == "CAFilter")
    }

    @Test func `a class from a different image than expected is reported as such`() {
        #expect(throws: PrivateAPIError.wrongImage(class: "CAFilter", expected: "UIKitCore", actual: "QuartzCore")) {
            try PrivateClass("CAFilter", in: .uiKitCore)
        }
    }

    @Test func `a class that does not exist is reported by name`() {
        #expect(throws: PrivateAPIError.classNotFound("CAFilterThatNoLongerExists")) {
            try PrivateClass("CAFilterThatNoLongerExists")
        }
    }

    @Test func `a class that is not an exported symbol is reported when the symbol is required`() {
        // `__NSArrayI` is a real class, registered by Foundation, that no image exports as a linker symbol.
        #expect(throws: PrivateAPIError.symbolNotExported("__NSArrayI")) {
            try PrivateClass("__NSArrayI", exported: true)
        }
    }

    // MARK: Typed methods

    @Test func `a class method is called through a verified Swift function type`() throws {
        let filter = try PrivateClass("CAFilter", in: .quartzCore)
        let make = try filter.method("filterWithType:", kind: .class, as: ((String) -> NSObject?).self)
        let blur = try make("gaussianBlur")
        #expect(blur != nil)
    }

    @Test func `a selector that responds but has a different signature is refused, as AemiSDR's settingsForStyle was`()
        throws
    {
        // `+[NSNumber numberWithInteger:]` takes an NSInteger. `perform(_:with:)` would box an object into it.
        let number = try PrivateClass("NSNumber")
        #expect(
            throws: PrivateAPIError.signatureMismatch(selector: "numberWithInteger:", expected: "@@:@", actual: "@@:q")
        ) {
            try number.method("numberWithInteger:", kind: .class, as: ((String) -> NSNumber?).self)
        }
        let correct = try number.method("numberWithInteger:", kind: .class, as: ((Int) -> NSNumber?).self)
        #expect(try correct(42) == 42)
    }

    @Test func `a selector the class does not implement is reported`() throws {
        let filter = try PrivateClass("CAFilter")
        #expect(throws: PrivateAPIError.selectorNotFound(class: "CAFilter", selector: "filterWithKind:")) {
            try filter.method("filterWithKind:", kind: .class, as: ((String) -> NSObject?).self)
        }
    }

    @Test func `an action sends a message that returns nothing`() throws {
        let layer = try PrivateClass("CALayer")
        let setRadius = try layer.action("setCornerRadius:", as: ((Double) -> Void).self)
        let instance = CALayer()
        try setRadius(on: instance, 12)
        #expect(instance.cornerRadius == 12)
    }

    // MARK: Dynamic members

    @Test func `properties are read and written through dynamic members with their types checked`() {
        let layer = CALayer()
        let object = PrivateObject(layer)
        object.cornerRadius = 9.0
        #expect(layer.cornerRadius == 9)
        let radius: Double? = object.cornerRadius
        #expect(radius == 9)

        object.isHidden = true
        #expect(layer.isHidden)
        let hidden: Bool? = object.isHidden
        #expect(hidden == true)

        let bounds = CGRect(x: 1, y: 2, width: 30, height: 40)
        object.bounds = bounds
        let read: CGRect? = object.bounds
        #expect(read == bounds)
    }

    @Test func `a property read with the wrong type is nil and recorded, never reinterpreted`() {
        let object = PrivateObject(CALayer())
        let wrong: Int? = object.cornerRadius
        #expect(wrong == nil)
        #expect(PrivateAPI.failures.contains { $0.symbol == "-[CALayer cornerRadius]" })
    }

    @Test func `a property that does not exist is nil and recorded once`() {
        let object = PrivateObject(CALayer())
        let missing: Double? = object.aemiDefinitelyMissing
        #expect(missing == nil)
        #expect(PrivateAPI.failures.map(\.symbol).contains("-[CALayer aemiDefinitelyMissing]"))
    }

    @Test func `the throwing form says why`() {
        let object = PrivateObject(CALayer())
        #expect(throws: PrivateAPIError.signatureMismatch(selector: "cornerRadius", expected: "q@:", actual: "d@:")) {
            let _: Int = try object.read("cornerRadius")
        }
    }

    @Test func `a call with the wrong number of arguments is refused before it is sent`() {
        let object = PrivateObject(CALayer())
        #expect(throws: PrivateAPIError.argumentCount(selector: "setCornerRadius:", expected: 1, actual: 2)) {
            try object.send("setCornerRadius:", 1.0, 2.0)
        }
    }

    // MARK: Exceptions

    @Test func `an exception raised by the callee is caught and reported`() {
        let array = PrivateObject(NSArray())
        #expect(throws: PrivateAPIError.raised(selector: "objectAtIndex:", exception: "NSRangeException")) {
            let _: NSObject? = try array.call("objectAtIndex:", UInt(5))
        }
    }

    @Test func `a missing key in key-value coding is a reported error, not a crash`() {
        let object = PrivateObject(NSObject())
        #expect(
            throws: PrivateAPIError.raised(selector: "valueForKey:aemiMissingKey", exception: "NSUnknownKeyException")
        ) {
            _ = try object.value(forKey: "aemiMissingKey")
        }
    }

    // MARK: Policy and report

    @Test func `the host can switch private API off and every resolution then refuses`() throws {
        PrivateAPI.isEnabled = false
        defer { PrivateAPI.isEnabled = true }
        #expect(throws: PrivateAPIError.disabled) { try PrivateClass("CAFilter") }
        let object = PrivateObject(CALayer())
        let value: Double? = object.cornerRadius
        #expect(value == nil)
    }

    @Test func `every resolution is recorded so a canary test can assert the whole set`() throws {
        _ = try PrivateClass("CAFilter", in: .quartzCore)
        _ = try? PrivateClass("CAFilterThatNoLongerExists")
        let symbols = Dictionary(uniqueKeysWithValues: PrivateAPI.resolutions.map { ($0.symbol, $0.isAvailable) })
        #expect(symbols["CAFilter"] == true)
        #expect(symbols["CAFilterThatNoLongerExists"] == false)
    }

    @Test func `a setter name follows the Objective-C convention for a Boolean property`() {
        #expect(PrivateObject.setterName(for: "isEnabled") == "setEnabled:")
        #expect(PrivateObject.setterName(for: "cornerRadius") == "setCornerRadius:")
        #expect(PrivateObject.setterName(for: "island") == "setIsland:")
    }
}
