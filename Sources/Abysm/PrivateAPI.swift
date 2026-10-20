import OSLog
import Synchronization

/// Process-wide policy and bookkeeping for private API.
public enum PrivateAPI {
    private static let enabled = Atomic<Bool>(true)

    /// Whether private symbols may be resolved and called. The host app's switch for App Review risk or a
    /// remote kill switch; while `false`, every resolution throws `PrivateAPIError.disabled`.
    public static var isEnabled: Bool {
        get { enabled.load(ordering: .relaxed) }
        set { enabled.store(newValue, ordering: .relaxed) }
    }

    /// What happened to one symbol the first time it was resolved.
    public struct Resolution: Sendable, Equatable {
        public var symbol: String
        public var error: PrivateAPIError?
        public var isAvailable: Bool { error == nil }
    }

    private static let log = Mutex<[String: Resolution]>([:])
    private static let logger = Logger(subsystem: "studio.aemi.Abysm", category: "PrivateAPI")

    /// Every symbol resolved so far and its outcome, by name. A test that touches every symbol a package uses
    /// and asserts `isAvailable` is the drift canary: an OS update that renames one fails the test, not a user.
    public static var resolutions: [Resolution] {
        log.withLock { $0.values.sorted { $0.symbol < $1.symbol } }
    }

    /// The resolutions that failed.
    public static var failures: [Resolution] { resolutions.filter { !$0.isAvailable } }

    /// Forgets recorded resolutions. For tests.
    public static func resetResolutions() { log.withLock { $0.removeAll() } }

    static func record(_ symbol: String, _ error: PrivateAPIError?) {
        let isNewFailure = log.withLock { entries -> Bool in
            let isNew = entries[symbol] == nil
            entries[symbol] = Resolution(symbol: symbol, error: error)
            return isNew && error != nil
        }
        // One `.fault` per symbol per process: visible in a crash-free field log, never per frame.
        if isNewFailure, let error {
            logger.fault(
                "Private API unavailable: \(symbol, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    static func checkEnabled() throws(PrivateAPIError) {
        guard isEnabled else { throw .disabled }
    }
}
