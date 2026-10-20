internal import CAbysm
import Foundation

/// An object whose private properties and methods are read through `@dynamicMemberLookup`, each access checked
/// against the runtime's signature for the object's real class.
///
/// ```swift
/// let settings = PrivateObject(backdropSettings)
/// let radius: Double? = settings.blurRadius        // getter `blurRadius`, signature `d@:` checked
/// settings.blurRadius = 12                         // setter `setBlurRadius:`, signature `v@:d` checked
/// let enabled: Bool? = layer.isEnabled             // getter `isEnabled`; setter falls back to `setEnabled:`
/// ```
///
/// A property that is missing, or has a different type than the one inferred at the call site, reads as `nil` and
/// is recorded once in `PrivateAPI.resolutions`; it never raises. Use the throwing `read`/`write`/`call` forms to
/// handle the failure yourself.
@dynamicMemberLookup
public struct PrivateObject {
    public let base: AnyObject

    public init(_ base: AnyObject) { self.base = base }

    public subscript<Value: ObjCValue>(dynamicMember name: String) -> Value? {
        get { try? read(name) }
        nonmutating set {
            guard let newValue else { return }
            try? write(newValue, to: name)
        }
    }

    // MARK: - Properties

    /// Reads a property through its getter, after checking the getter returns a `Value`.
    public func read<Value: ObjCValue>(_ name: String, as _: Value.Type = Value.self) throws(PrivateAPIError) -> Value {
        try verified("-[\(className) \(name)]") { () throws(PrivateAPIError) -> Value in
            try Invocation.verify(
                class: type(of: base), selector: name, classMethod: false,
                expected: Invocation.signature(result: Value.objcEncoding, arguments: []))
            var result: Value?
            try unsafe Invocation.send(
                to: base, selector: NSSelectorFromString(name), arguments: ArgumentBuffer(),
                resultEncoding: Value.objcEncoding
            ) { (pointer) throws(PrivateAPIError) in result = try unsafe Value.decode(from: pointer) }
            guard let result else { throw .sizeMismatch(selector: name) }
            return result
        }
    }

    /// Writes a property through its setter (`setName:`, or `setX:` for a Boolean `isX`).
    public func write<Value: ObjCValue>(_ value: Value, to name: String) throws(PrivateAPIError) {
        let setter = Self.setterName(for: name)
        try verified("-[\(className) \(setter)]") { () throws(PrivateAPIError) -> Void in
            try Invocation.verify(
                class: type(of: base), selector: setter, classMethod: false,
                expected: Invocation.signature(result: "v", arguments: [Value.objcEncoding]))
            var buffer = ArgumentBuffer()
            value.encode(into: &buffer)
            try unsafe Invocation.send(
                to: base, selector: NSSelectorFromString(setter), arguments: buffer, resultEncoding: nil
            ) { _ in }
        }
    }

    // MARK: - Methods

    /// Calls a method that returns a value. The number of arguments must equal the number of colons.
    public func call<each Argument: ObjCValue, Result: ObjCValue>(
        _ selector: String,
        _ arguments: repeat each Argument
    ) throws(PrivateAPIError) -> Result {
        var encodings: [String] = []
        repeat encodings.append((each Argument).objcEncoding)
        try Self.checkArity(selector, encodings.count)
        return try verified("-[\(className) \(selector)]") { () throws(PrivateAPIError) -> Result in
            try Invocation.verify(
                class: type(of: base), selector: selector, classMethod: false,
                expected: Invocation.signature(result: Result.objcEncoding, arguments: encodings))
            var buffer = ArgumentBuffer()
            repeat (each arguments).encode(into: &buffer)
            var result: Result?
            try unsafe Invocation.send(
                to: base, selector: NSSelectorFromString(selector), arguments: buffer,
                resultEncoding: Result.objcEncoding
            ) { (pointer) throws(PrivateAPIError) in result = try unsafe Result.decode(from: pointer) }
            guard let result else { throw .sizeMismatch(selector: selector) }
            return result
        }
    }

    /// Calls a method that returns nothing.
    public func send<each Argument: ObjCValue>(_ selector: String, _ arguments: repeat each Argument)
        throws(PrivateAPIError)
    {
        var encodings: [String] = []
        repeat encodings.append((each Argument).objcEncoding)
        try Self.checkArity(selector, encodings.count)
        try verified("-[\(className) \(selector)]") { () throws(PrivateAPIError) -> Void in
            try Invocation.verify(
                class: type(of: base), selector: selector, classMethod: false,
                expected: Invocation.signature(result: "v", arguments: encodings))
            var buffer = ArgumentBuffer()
            repeat (each arguments).encode(into: &buffer)
            try unsafe Invocation.send(
                to: base, selector: NSSelectorFromString(selector), arguments: buffer, resultEncoding: nil
            ) { _ in }
        }
    }

    // MARK: - Key-value coding

    /// `valueForKey:` with the `NSUnknownKeyException` it raises for a missing key caught and reported.
    public func value(forKey key: String) throws(PrivateAPIError) -> Any? {
        try PrivateAPI.checkEnabled()
        var exception: NSString?
        let value = unsafe abysm_value_for_key(base, key, &exception)
        if let exception { throw .raised(selector: "valueForKey:" + key, exception: exception as String) }
        return value
    }

    /// `setValue:forKey:` with an exception caught and reported. Note that `CALayer` and `CAFilter` accept unknown
    /// keys silently; a renamed key is a no-op, so verify the key with the owner's own list where there is one.
    public func setValue(_ value: Any?, forKey key: String) throws(PrivateAPIError) {
        try PrivateAPI.checkEnabled()
        if let exception = abysm_set_value_for_key(base, value as AnyObject?, key) {
            throw .raised(selector: "setValue:forKey:" + key, exception: exception as String)
        }
    }

    // MARK: - Helpers

    private var className: String { NSStringFromClass(type(of: base)) }

    private func verified<Success>(
        _ symbol: String,
        _ body: () throws(PrivateAPIError) -> Success
    ) throws(PrivateAPIError) -> Success {
        do {
            try PrivateAPI.checkEnabled()
            let result = try body()
            PrivateAPI.record(symbol, nil)
            return result
        } catch {
            PrivateAPI.record(symbol, error)
            throw error
        }
    }

    static func setterName(for name: String) -> String {
        // A Boolean property `enabled` with getter `isEnabled` has the setter `setEnabled:`.
        let stem =
            name.hasPrefix("is") && name.count > 2 && name.dropFirst(2).first?.isUppercase == true
            ? String(name.dropFirst(2)) : name
        return "set" + stem.prefix(1).uppercased() + stem.dropFirst() + ":"
    }

    private static func checkArity(_ selector: String, _ count: Int) throws(PrivateAPIError) {
        let expected = selector.reduce(0) { $0 + ($1 == ":" ? 1 : 0) }
        guard expected == count else { throw .argumentCount(selector: selector, expected: expected, actual: count) }
    }
}
