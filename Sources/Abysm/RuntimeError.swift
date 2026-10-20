/// Why a runtime symbol could not be used. Every case names what was expected and what was found, so a log line is
/// enough to know which OS release moved.
public enum RuntimeError: Error, Sendable, Equatable {
    /// The host switched runtime access off (`RuntimeAccess.isEnabled`).
    case disabled
    /// An object result has a different dynamic class than the requested Swift type (or is unexpectedly nil).
    case objectTypeMismatch(expected: String, actual: String)
    /// A class-method handle received an instance, or an instance-method handle received a class.
    case wrongReceiver(selector: String)
    /// No class with this name is registered with the runtime.
    case classNotFound(String)
    /// The class exists but is defined by a different image than the one expected.
    case wrongImage(class: String, expected: String, actual: String?)
    /// The class is not exported as a linker symbol (`OBJC_CLASS_$_…`) by any loaded image.
    case symbolNotExported(String)
    /// The class does not implement the selector.
    case selectorNotFound(class: String, selector: String)
    /// The selector exists with a different signature than the declared Swift function type.
    ///
    /// Both strings are the return type followed by every argument type, receiver and selector included:
    /// `@@:q` is `-(id)x:(NSInteger)`. This is the case that a bare `responds(to:)` guard cannot see.
    case signatureMismatch(selector: String, expected: String, actual: String)
    /// The number of arguments passed differs from the number of colons in the selector.
    case argumentCount(selector: String, expected: Int, actual: Int)
    /// The callee raised an Objective-C exception, which was caught.
    case raised(selector: String, exception: String)
    /// The runtime reported a different size for an argument or result than the declaration.
    case sizeMismatch(selector: String)
}
