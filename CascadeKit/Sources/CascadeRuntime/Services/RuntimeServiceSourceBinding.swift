import CascadeContracts
import Foundation

/// Persistent provider incarnation authority, independent of the finite startup job.
struct RuntimeServiceSourceBinding: Sendable {
    let frame: ServiceSourceStartFrame
    let key: ServiceRegistry.SourceKey
    let incarnation: RuntimeIncarnation
    let connectionToken: UUID
    var ready = false
    var receipt: RuntimeServiceSubscriptionReceipt?
    static let bytes = max(4_096, MemoryLayout<Self>.stride * 4 + RuntimeServiceConnectionState.receiptBytes)
}
