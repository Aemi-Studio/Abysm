import Foundation
import QuartzCore
import Testing

@testable import Abysm

@objc(AbysmBoundaryFixture)
private final class BoundaryFixture: NSObject {
    @objc func doubleValue() -> Double { 1.0 }
    @objc func stringResult() -> NSObject { NSString(string: "hello") }
    @objc func freshObject() -> NSObject { NSObject() }
}

@objc(AbysmIntegerFixture)
private final class IntegerFixture: NSObject {
    @objc func doubleValue() -> Int { 42 }
}

@Suite("Invocation boundaries")
struct BoundaryTests {
    @Test func wrongObjectClassThrows() {
        let object = RuntimeObject(BoundaryFixture())
        #expect(throws: RuntimeError.self) {
            let _: NSNumber? = try object.call("stringResult")
        }
    }

    @Test func wrongStringClassThrows() {
        #expect(throws: RuntimeError.self) {
            let _: String = try RuntimeObject(BoundaryFixture()).call("freshObject")
        }
    }

    @Test func receiverWithSameSizeDifferentSignatureIsRefused() throws {
        let method = try RuntimeClass("AbysmBoundaryFixture").method("doubleValue", as: (() -> Double).self)
        #expect(throws: RuntimeError.signatureMismatch(selector: "doubleValue", expected: "d@:", actual: "q@:")) {
            try method(on: IntegerFixture())
        }
    }

    @Test func instanceHandleCannotReceiveAClass() throws {
        let action = try RuntimeClass("CALayer").action("setCornerRadius:", as: ((Double) -> Void).self)
        #expect(throws: RuntimeError.wrongReceiver(selector: "setCornerRadius:")) {
            try action(on: CALayer.self, 2.0)
        }
    }

    @Test func borrowedObjectLivesUntilSwiftOwnsItAndDoesNotLeak() throws {
        weak var observed: NSObject?
        try autoreleasepool {
            let value: NSObject? = try RuntimeObject(BoundaryFixture()).call("freshObject")
            observed = value
            #expect(observed != nil)
        }
        #expect(observed == nil)
    }

    @Test func ownedObjectAndInitialiserAreBalanced() throws {
        weak var observed: NSObject?
        try autoreleasepool {
            let cls = try RuntimeClass("NSObject")
            let allocate = try cls.method("alloc", kind: .class, as: (() -> NSObject?).self)
            let initialise = try cls.method("init", as: (() -> NSObject?).self)
            let raw = try #require(try allocate())
            let object = try #require(try initialise(on: raw))
            observed = object
            #expect(observed != nil)
        }
        #expect(observed == nil)
    }
}
