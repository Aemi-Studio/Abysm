import Foundation
import ObjectiveC

/// A private Objective-C class, resolved and verified once.
///
/// ```swift
/// let filter = try PrivateClass("CAFilter", in: .quartzCore, exported: true)
/// let make = try filter.method("filterWithType:", kind: .class, as: ((String) -> NSObject?).self)
/// let blur = try make("gaussianBlur")
/// ```
public struct PrivateClass: @unchecked Sendable {
    // `AnyClass` is an immutable pointer to runtime-owned metadata; sharing it across threads is safe.
    public let name: String
    public let value: AnyClass

    /// Whether a selector is sent to the class or to its instances.
    public enum Kind: Sendable { case instance, `class` }

    /// Resolves `name` and verifies where it came from.
    ///
    /// - Parameters:
    ///   - name: The Objective-C class name.
    ///   - image: The framework that must define the class. A class of the same name from another image is missing.
    ///   - exported: Also require the linker symbol `OBJC_CLASS_$_<name>` via `dlsym`. Stronger than a runtime
    ///     lookup, which also finds classes registered by anyone; not every private class is exported.
    /// - Throws: ``PrivateAPIError`` for a disabled policy, a missing class, a wrong image or an unexported symbol.
    public init(_ name: String, in image: Image? = nil, exported: Bool = false) throws(PrivateAPIError) {
        do {
            try PrivateAPI.checkEnabled()
            guard let found = unsafe objc_lookUpClass(name) else { throw PrivateAPIError.classNotFound(name) }
            if let image {
                let actual = unsafe class_getImageName(found).map { unsafe String(cString: $0) }
                let actualName = actual.map { ($0 as NSString).lastPathComponent }
                guard actualName == image.name else {
                    throw PrivateAPIError.wrongImage(class: name, expected: image.name, actual: actualName)
                }
            }
            if exported, unsafe dlsym(UnsafeMutableRawPointer(bitPattern: -2), "OBJC_CLASS_$_" + name) == nil {
                throw PrivateAPIError.symbolNotExported(name)
            }
            self.name = name
            self.value = found
            PrivateAPI.record(name, nil)
        } catch let error as PrivateAPIError {
            PrivateAPI.record(name, error)
            throw error
        } catch {
            fatalError("unreachable: only PrivateAPIError is thrown")
        }
    }

    /// The class object, the receiver for class methods.
    public var object: AnyObject { value }

    /// Resolves a selector that returns a value, verifying it against the declared Swift function type.
    public func method<each Argument: ObjCValue, Result: ObjCValue>(
        _ selector: String,
        kind: Kind = .instance,
        as _: ((repeat each Argument) -> Result).Type
    ) throws(PrivateAPIError) -> PrivateMethod<repeat each Argument, Result> {
        var arguments: [String] = []
        repeat arguments.append((each Argument).objcEncoding)
        let expected = Invocation.signature(result: Result.objcEncoding, arguments: arguments)
        try resolve(selector, kind: kind, expected: expected)
        return PrivateMethod(class: self, selector: selector, isClassMethod: kind == .class)
    }

    /// Resolves a selector that returns nothing.
    public func action<each Argument: ObjCValue>(
        _ selector: String,
        kind: Kind = .instance,
        as _: ((repeat each Argument) -> Void).Type
    ) throws(PrivateAPIError) -> PrivateAction<repeat each Argument> {
        var arguments: [String] = []
        repeat arguments.append((each Argument).objcEncoding)
        let expected = Invocation.signature(result: "v", arguments: arguments)
        try resolve(selector, kind: kind, expected: expected)
        return PrivateAction(class: self, selector: selector, isClassMethod: kind == .class)
    }

    private func resolve(_ selector: String, kind: Kind, expected: String) throws(PrivateAPIError) {
        let key = (kind == .class ? "+" : "-") + "[\(name) \(selector)]"
        do {
            try PrivateAPI.checkEnabled()
            try Invocation.verify(class: value, selector: selector, classMethod: kind == .class, expected: expected)
            PrivateAPI.record(key, nil)
        } catch {
            PrivateAPI.record(key, error)
            throw error
        }
    }
}

/// A verified selector with a result. Hold it in a `static let`: resolution runs once.
public struct PrivateMethod<each Argument: ObjCValue, Result: ObjCValue>: @unchecked Sendable {
    // `Selector` and the class are immutable runtime handles.
    public let className: String
    public let selectorName: String
    let selector: Selector
    let isClassMethod: Bool
    let classObject: AnyObject

    init(class privateClass: PrivateClass, selector: String, isClassMethod: Bool) {
        className = privateClass.name
        selectorName = selector
        self.selector = NSSelectorFromString(selector)
        self.isClassMethod = isClassMethod
        classObject = privateClass.object
    }

    /// Calls an instance method on `target`.
    public func callAsFunction(on target: AnyObject, _ arguments: repeat each Argument) throws(PrivateAPIError)
        -> Result
    {
        var buffer = ArgumentBuffer()
        repeat (each arguments).encode(into: &buffer)
        var result: Result?
        try unsafe Invocation.send(
            to: target, selector: selector, arguments: buffer, resultEncoding: Result.objcEncoding
        ) {
            result = unsafe Result.decode(from: $0)
        }
        guard let result else { throw .sizeMismatch(selector: selectorName) }
        return result
    }

    /// Calls a class method.
    public func callAsFunction(_ arguments: repeat each Argument) throws(PrivateAPIError) -> Result {
        guard isClassMethod else { throw .selectorNotFound(class: className, selector: "+" + selectorName) }
        return try self(on: classObject, repeat each arguments)
    }
}

/// A verified selector with no result.
public struct PrivateAction<each Argument: ObjCValue>: @unchecked Sendable {
    public let className: String
    public let selectorName: String
    let selector: Selector
    let isClassMethod: Bool
    let classObject: AnyObject

    init(class privateClass: PrivateClass, selector: String, isClassMethod: Bool) {
        className = privateClass.name
        selectorName = selector
        self.selector = NSSelectorFromString(selector)
        self.isClassMethod = isClassMethod
        classObject = privateClass.object
    }

    public func callAsFunction(on target: AnyObject, _ arguments: repeat each Argument) throws(PrivateAPIError) {
        var buffer = ArgumentBuffer()
        repeat (each arguments).encode(into: &buffer)
        try unsafe Invocation.send(to: target, selector: selector, arguments: buffer, resultEncoding: nil) { _ in }
    }

    public func callAsFunction(_ arguments: repeat each Argument) throws(PrivateAPIError) {
        guard isClassMethod else { throw .selectorNotFound(class: className, selector: "+" + selectorName) }
        try self(on: classObject, repeat each arguments)
    }
}
