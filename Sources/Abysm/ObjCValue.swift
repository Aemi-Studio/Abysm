import CoreGraphics
public import Foundation

/// A Swift type that can cross an Objective-C message boundary, declaring its own type encoding.
///
/// Custom conformances are an unsafe interop contract: the encoding, encoded bytes and decoder's read size must
/// agree. The decoder may read only the size specified by the encoding, and must not let pointers escape.
///
/// The encoding is what lets a call be checked: a declaration `(Int) -> NSObject?` is the signature `@@:q`, and the
/// runtime's signature for the real selector is compared to it before any call is made.
public protocol ObjCValue {
    /// The Objective-C type encoding, such as `q`, `d`, `@` or `{CGSize=dd}`.
    static var objcEncoding: String { get }
    /// Appends this value's bytes (and retains anything it points to) for the duration of a call.
    func encode(into buffer: inout ArgumentBuffer)
    /// Reads a value of this type from the bytes the runtime wrote.
    static func decode(from pointer: UnsafeRawPointer) throws(PrivateAPIError) -> Self
}

extension ObjCValue where Self: BitwiseCopyable {
    public func encode(into buffer: inout ArgumentBuffer) {
        withUnsafeBytes(of: self) { unsafe buffer.append($0) }
    }

    public static func decode(from pointer: UnsafeRawPointer) -> Self {
        unsafe pointer.loadUnaligned(as: Self.self)
    }
}

extension Bool: ObjCValue { public static var objcEncoding: String { "B" } }
extension Int: ObjCValue { public static var objcEncoding: String { "q" } }
extension UInt: ObjCValue { public static var objcEncoding: String { "Q" } }
extension Int32: ObjCValue { public static var objcEncoding: String { "i" } }
extension UInt32: ObjCValue { public static var objcEncoding: String { "I" } }
extension Double: ObjCValue { public static var objcEncoding: String { "d" } }
extension Float: ObjCValue { public static var objcEncoding: String { "f" } }
extension CGFloat: ObjCValue { public static var objcEncoding: String { "d" } }
extension CGPoint: ObjCValue { public static var objcEncoding: String { "{CGPoint=dd}" } }
extension CGSize: ObjCValue { public static var objcEncoding: String { "{CGSize=dd}" } }
extension CGRect: ObjCValue { public static var objcEncoding: String { "{CGRect={CGPoint=dd}{CGSize=dd}}" } }

extension Selector: ObjCValue { public static var objcEncoding: String { ":" } }

// Objects cross as `Optional`: a private method that returns nil is common, and a non-optional declaration would
// have to invent an object for it. A non-optional argument is promoted to `Optional` at the call site.
extension Optional: ObjCValue where Wrapped: NSObject {
    public static var objcEncoding: String { "@" }

    public func encode(into buffer: inout ArgumentBuffer) {
        switch self {
            case .some(let object): buffer.appendObject(object)
            case .none: buffer.appendObject(nil)
        }
    }

    public static func decode(from pointer: UnsafeRawPointer) throws(PrivateAPIError) -> Wrapped? {
        guard let raw = unsafe pointer.loadUnaligned(as: UnsafeRawPointer?.self) else { return nil }
        let object = unsafe Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
        guard let value = object as? Wrapped else {
            throw .objectTypeMismatch(
                expected: String(describing: Wrapped.self), actual: String(describing: type(of: object)))
        }
        return value
    }
}

/// A `String` crosses as an `NSString`.
extension String: ObjCValue {
    public static var objcEncoding: String { "@" }

    public func encode(into buffer: inout ArgumentBuffer) {
        buffer.appendObject(self as NSString)
    }

    public static func decode(from pointer: UnsafeRawPointer) throws(PrivateAPIError) -> String {
        guard let value = try unsafe Optional<NSString>.decode(from: pointer) else {
            throw .objectTypeMismatch(expected: "NSString", actual: "nil")
        }
        return value as String
    }
}

/// The bytes of one call's arguments, laid out so each can be handed to the runtime by address, plus the objects
/// that must stay alive until the call returns.
public struct ArgumentBuffer {
    var bytes: [UInt8] = []
    var offsets: [Int] = []
    var sizes: [Int] = []
    var retained: [AnyObject] = []

    public init() {}

    mutating func append(_ raw: UnsafeRawBufferPointer) {
        // 16-byte alignment covers every scalar and vector type the runtime passes by address.
        while bytes.count % 16 != 0 { bytes.append(0) }
        offsets.append(bytes.count)
        sizes.append(raw.count)
        unsafe bytes.append(contentsOf: raw)
    }

    mutating func appendObject(_ object: AnyObject?) {
        if let object { retained.append(object) }
        let pointer: UnsafeRawPointer? = unsafe object.map {
            unsafe UnsafeRawPointer(Unmanaged.passUnretained($0).toOpaque())
        }
        withUnsafeBytes(of: pointer) { unsafe append($0) }
    }
}
