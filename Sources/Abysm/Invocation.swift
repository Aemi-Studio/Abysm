internal import CAbysm
import Foundation
import Synchronization

/// The single place a message is sent. Every size is checked in the shim against the runtime's own signature.
enum Invocation {
    static func send(
        to target: AnyObject,
        selector: Selector,
        arguments: ArgumentBuffer,
        resultEncoding: String?,
        decode: (UnsafeRawPointer) throws(PrivateAPIError) -> Void
    ) throws(PrivateAPIError) {
        try PrivateAPI.checkEnabled()
        let name = NSStringFromSelector(selector)

        var resultSize = 0
        if let resultEncoding { unsafe NSGetSizeAndAlignment(resultEncoding, &resultSize, nil) }
        var storage = [UInt8](repeating: 0, count: max(resultSize, 16))

        var exception: NSString?
        let argumentCount = arguments.offsets.count
        let status: AbysmStatus = arguments.bytes.withUnsafeBytes { bytes in
            // One pointer per argument, into the buffer that stays alive for the whole call.
            let pointers: [UnsafeRawPointer?] = unsafe arguments.offsets.map { offset in
                unsafe bytes.baseAddress.map { unsafe $0 + offset }
            }
            return pointers.withUnsafeBufferPointer { argumentPointers in
                arguments.sizes.withUnsafeBufferPointer { sizes in
                    storage.withUnsafeMutableBytes { result in
                        unsafe abysm_invoke(
                            target, selector, argumentCount, argumentPointers.baseAddress,
                            sizes.baseAddress, result.baseAddress, resultSize, &exception)
                    }
                }
            }
        }
        // The arguments' objects must outlive the call.
        withExtendedLifetime(arguments.retained) {}

        switch status {
            case .OK:
                // The shim transfers a +1 object result. Keep it alive through decoding (including a thrown
                // type mismatch), then balance it. The decoded Swift value holds its own reference.
                var decodeError: PrivateAPIError?
                storage.withUnsafeBytes { bytes in
                    let pointer = bytes.baseAddress!
                    let object: Unmanaged<AnyObject>? =
                        resultEncoding == "@"
                        ? unsafe pointer.loadUnaligned(as: UnsafeRawPointer?.self)
                            .map {
                                unsafe Unmanaged<AnyObject>.fromOpaque($0)
                            } : nil
                    defer { unsafe object?.release() }
                    do {
                        try unsafe decode(pointer)
                    } catch let error as PrivateAPIError {
                        decodeError = error
                    } catch {
                        preconditionFailure("decoder violated its typed-throws contract")
                    }
                }
                if let decodeError { throw decodeError }
            case .noSignature:
                throw .selectorNotFound(class: String(describing: type(of: target)), selector: name)
            case .argumentCount:
                throw .argumentCount(selector: name, expected: 0, actual: arguments.offsets.count)
            case .sizeMismatch:
                throw .sizeMismatch(selector: name)
            case .raised:
                throw .raised(selector: name, exception: (exception as String?) ?? "unknown")
            @unknown default:
                throw .sizeMismatch(selector: name)
        }
    }

    /// The expected signature for a declaration: result, receiver, selector, then each argument.
    static func signature(result: String, arguments: [String]) -> String {
        result + "@:" + arguments.joined()
    }

    private struct VerificationKey: Hashable {
        var cls: ObjectIdentifier
        var selector: String
        var classMethod: Bool
        var expected: String
    }

    /// Verdicts already reached. A signature does not change while a class stays loaded, so a verdict is computed
    /// once per (class, selector, declaration) and every later access costs a dictionary lookup instead of building
    /// an \`NSMethodSignature\`. Failures are cached too, so a symbol that is gone is not re-derived every frame.
    private static let verdicts = Mutex<[VerificationKey: PrivateAPIError?]>([:])

    /// Checks the runtime's signature for a selector against the declaration.
    static func verify(
        class cls: AnyClass,
        selector: String,
        classMethod: Bool,
        expected: String
    ) throws(PrivateAPIError) {
        let key = VerificationKey(
            cls: ObjectIdentifier(cls), selector: selector, classMethod: classMethod, expected: expected)
        if let cached = verdicts.withLock({ $0[key] }) {
            if let error = cached { throw error }
            return
        }
        let verdict = compute(class: cls, selector: selector, classMethod: classMethod, expected: expected)
        verdicts.withLock { $0[key] = .some(verdict) }
        if let verdict { throw verdict }
    }

    private static func compute(
        class cls: AnyClass,
        selector: String,
        classMethod: Bool,
        expected: String
    ) -> PrivateAPIError? {
        let sel = NSSelectorFromString(selector)
        guard let actual = abysm_signature(cls, sel, classMethod) else {
            return .selectorNotFound(class: NSStringFromClass(cls), selector: selector)
        }
        guard actual == expected else {
            return .signatureMismatch(selector: selector, expected: expected, actual: actual)
        }
        return nil
    }
}
