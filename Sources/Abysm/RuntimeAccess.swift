import OSLog
import Synchronization

/// Process-wide policy and bookkeeping for runtime access.
public enum RuntimeAccess {
    private static let enabled = Atomic<Bool>(true)

    /// Whether runtime symbols may be resolved and invoked.
    /// While `false`, resolution and invocation throw `RuntimeError.disabled`.
    public static var isEnabled: Bool {
        get { enabled.load(ordering: .relaxed) }
        set { enabled.store(newValue, ordering: .relaxed) }
    }

    /// What happened to one symbol the first time it was resolved.
    public struct Resolution: Sendable, Equatable {
        public var symbol: String
        public var error: RuntimeError?
        public var isAvailable: Bool { error == nil }
    }

    private static let log = Mutex<[String: Resolution]>([:])
    private static let logger = Logger(subsystem: "Abysm", category: "RuntimeAccess")

    /// Every symbol resolved so far and its outcome, by name. A test that touches every symbol a package uses
    /// and asserts `isAvailable` is the drift canary: an OS update that renames one fails the test, not a user.
    public static var resolutions: [Resolution] {
        log.withLock { $0.values.sorted { $0.symbol < $1.symbol } }
    }

    /// The resolutions that failed.
    public static var failures: [Resolution] { resolutions.filter { !$0.isAvailable } }

    /// Forgets recorded resolutions. For tests.
    public static func resetResolutions() { log.withLock { $0.removeAll() } }

    static func record(_ symbol: String, _ error: RuntimeError?) {
        let isNewFailure = log.withLock { entries -> Bool in
            let isNew = entries[symbol] == nil
            entries[symbol] = Resolution(symbol: symbol, error: error)
            return isNew && error != nil
        }
        // One `.fault` per symbol per process: visible in a crash-free field log, never per frame.
        if isNewFailure, let error {
            logger.fault(
                "Runtime access unavailable: \(symbol, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    static func checkEnabled() throws(RuntimeError) {
        guard isEnabled else { throw .disabled }
    }
}
