import Foundation
import ObjectiveC

/// An Objective-C class, resolved by name and verified against its defining image when requested.
///
/// ```swift
/// let filter = try RuntimeClass("CAFilter", in: .quartzCore, exported: true)
/// let make = try filter.method("filterWithType:", kind: .class, as: ((String) -> NSObject?).self)
/// let blur = try make("gaussianBlur")
/// ```
public struct RuntimeClass: @unchecked Sendable {
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
    ///     lookup, which also finds classes registered by anyone; not every runtime class is exported.
    /// - Throws: ``RuntimeError`` for a disabled policy, a missing class, a wrong image or an unexported symbol.
    public init(_ name: String, in image: Image? = nil, exported: Bool = false) throws(RuntimeError) {
        do {
            try RuntimeAccess.checkEnabled()
            guard let found = unsafe objc_lookUpClass(name) else { throw RuntimeError.classNotFound(name) }
            if let image {
                let actual = unsafe class_getImageName(found).map { unsafe String(cString: $0) }
                let actualName = actual.map { ($0 as NSString).lastPathComponent }
                guard actualName == image.name else {
                    throw RuntimeError.wrongImage(class: name, expected: image.name, actual: actualName)
                }
            }
            if exported, unsafe dlsym(UnsafeMutableRawPointer(bitPattern: -2), "OBJC_CLASS_$_" + name) == nil {
                throw RuntimeError.symbolNotExported(name)
            }
            self.name = name
            self.value = found
            RuntimeAccess.record(name, nil)
        } catch let error as RuntimeError {
            RuntimeAccess.record(name, error)
            throw error
        } catch {
            fatalError("unreachable: only RuntimeError is thrown")
        }
    }

    /// The class object, the receiver for class methods.
    public var object: AnyObject { value }

    /// Resolves a selector that returns a value, verifying it against the declared Swift function type.
    public func method<each Argument: ObjCValue, Result: ObjCValue>(
        _ selector: String,
        kind: Kind = .instance,
        as _: ((repeat each Argument) -> Result).Type
    ) throws(RuntimeError) -> RuntimeMethod<repeat each Argument, Result> {
        var arguments: [String] = []
        repeat arguments.append((each Argument).objcEncoding)
        let expected = Invocation.signature(result: Result.objcEncoding, arguments: arguments)
        try resolve(selector, kind: kind, expected: expected)
        return RuntimeMethod(class: self, selector: selector, isClassMethod: kind == .class)
    }

    /// Resolves a selector that returns nothing.
    public func action<each Argument: ObjCValue>(
        _ selector: String,
        kind: Kind = .instance,
        as _: ((repeat each Argument) -> Void).Type
    ) throws(RuntimeError) -> RuntimeAction<repeat each Argument> {
        var arguments: [String] = []
        repeat arguments.append((each Argument).objcEncoding)
        let expected = Invocation.signature(result: "v", arguments: arguments)
        try resolve(selector, kind: kind, expected: expected)
        return RuntimeAction(class: self, selector: selector, isClassMethod: kind == .class)
    }

    private func resolve(_ selector: String, kind: Kind, expected: String) throws(RuntimeError) {
        let key = (kind == .class ? "+" : "-") + "[\(name) \(selector)]"
        do {
            try RuntimeAccess.checkEnabled()
            try Invocation.verify(class: value, selector: selector, classMethod: kind == .class, expected: expected)
            RuntimeAccess.record(key, nil)
        } catch {
            RuntimeAccess.record(key, error)
            throw error
        }
    }
}

private func verifyReceiver(_ target: AnyObject, selector: String, classMethod: Bool, expected: String)
    throws(RuntimeError)
{
    guard object_isClass(target) == classMethod, let cls = object_getClass(target) else {
        throw .wrongReceiver(selector: selector)
    }
    // For class objects cls is the metaclass; checking its instance method checks the actual class method.
    try Invocation.verify(class: cls, selector: selector, classMethod: false, expected: expected)
}

/// A verified selector with a result. Hold it in a `static let`: resolution runs once.
public struct RuntimeMethod<each Argument: ObjCValue, Result: ObjCValue>: @unchecked Sendable {
    // `Selector` and the class are immutable runtime handles.
    public let className: String
    public let selectorName: String
    let selector: Selector
    let isClassMethod: Bool
    let classObject: AnyObject

    init(class runtimeClass: RuntimeClass, selector: String, isClassMethod: Bool) {
        className = runtimeClass.name
        selectorName = selector
        self.selector = NSSelectorFromString(selector)
        self.isClassMethod = isClassMethod
        classObject = runtimeClass.object
    }

    /// Calls an instance method on `target`.
    public func callAsFunction(on target: AnyObject, _ arguments: repeat each Argument) throws(RuntimeError)
        -> Result
    {
        var encodings: [String] = []
        repeat encodings.append((each Argument).objcEncoding)
        try verifyReceiver(
            target, selector: selectorName, classMethod: isClassMethod,
            expected: Invocation.signature(result: Result.objcEncoding, arguments: encodings))
        var buffer = ArgumentBuffer()
        repeat (each arguments).encode(into: &buffer)
        var result: Result?
        try unsafe Invocation.send(
            to: target, selector: selector, arguments: buffer, resultEncoding: Result.objcEncoding
        ) { (pointer) throws(RuntimeError) in
            result = try unsafe Result.decode(from: pointer)
        }
        guard let result else { throw .sizeMismatch(selector: selectorName) }
        return result
    }

    /// Calls a class method.
    public func callAsFunction(_ arguments: repeat each Argument) throws(RuntimeError) -> Result {
        guard isClassMethod else { throw .selectorNotFound(class: className, selector: "+" + selectorName) }
        return try self(on: classObject, repeat each arguments)
    }
}

/// A verified selector with no result.
public struct RuntimeAction<each Argument: ObjCValue>: @unchecked Sendable {
    public let className: String
    public let selectorName: String
    let selector: Selector
    let isClassMethod: Bool
    let classObject: AnyObject

    init(class runtimeClass: RuntimeClass, selector: String, isClassMethod: Bool) {
        className = runtimeClass.name
        selectorName = selector
        self.selector = NSSelectorFromString(selector)
        self.isClassMethod = isClassMethod
        classObject = runtimeClass.object
    }

    public func callAsFunction(on target: AnyObject, _ arguments: repeat each Argument) throws(RuntimeError) {
        var encodings: [String] = []
        repeat encodings.append((each Argument).objcEncoding)
        try verifyReceiver(
            target, selector: selectorName, classMethod: isClassMethod,
            expected: Invocation.signature(result: "v", arguments: encodings))
        var buffer = ArgumentBuffer()
        repeat (each arguments).encode(into: &buffer)
        try unsafe Invocation.send(to: target, selector: selector, arguments: buffer, resultEncoding: nil) { _ in }
    }

    public func callAsFunction(_ arguments: repeat each Argument) throws(RuntimeError) {
        guard isClassMethod else { throw .selectorNotFound(class: className, selector: "+" + selectorName) }
        try self(on: classObject, repeat each arguments)
    }
}
