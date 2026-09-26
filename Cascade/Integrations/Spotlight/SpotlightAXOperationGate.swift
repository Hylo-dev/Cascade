import Foundation

/// Cancellation is synchronous even while the AX worker is inside another
/// process. Each inspection also has one total budget, shared by every proxy.
nonisolated final class SpotlightAXOperationGate: @unchecked Sendable {
    struct Operation: Sendable {
        let revision: UInt64
        let deadline: TimeInterval
    }

    private let lock = NSLock()
    private var revision: UInt64 = 0

    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            revision &+= 1
            return revision
        }
    }

    func isCurrent(_ value: UInt64) -> Bool {
        lock.withLock { revision == value }
    }

    func operation(revision: UInt64, budget: TimeInterval = 0.12) -> Operation {
        Operation(revision: revision, deadline: ProcessInfo.processInfo.systemUptime + budget)
    }

    func remaining(_ operation: Operation) -> TimeInterval {
        guard isCurrent(operation.revision) else { return 0 }
        return max(0, operation.deadline - ProcessInfo.processInfo.systemUptime)
    }
}
