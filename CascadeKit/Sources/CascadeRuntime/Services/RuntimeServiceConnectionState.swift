import CascadeContracts
import Foundation

/// The shared admission domain uses ProcessRecord.lastServiceSequence for both
/// request families. Invocation rows remain in their original result owner.
struct RuntimeServiceConnectionState: Sendable {
    // Box, allocator bookkeeping and simultaneous exact-receipt comparisons.
    static let receiptBytes = max(256, 4 * MemoryLayout<RuntimeServiceSubscriptionReceipt>.stride)
    struct Parked: Sendable {
        let id: UUID
        let connection: RuntimeConnection
        let ingress: RuntimeServiceIngressHandle
        let deadline: Duration
    }
    var controls: [UUID: RuntimeServiceAcquisitionState] = [:]
    var parked: [RuntimeIncarnation: Parked] = [:]
    var count: Int { controls.count + parked.count }
    func contains(_ incarnation: RuntimeIncarnation) -> Bool {
        parked[incarnation] != nil || controls.values.contains { $0.connection.incarnation == incarnation }
    }
    func retainedBytes(owner: AddonID) -> Int {
        (controls.values.filter { $0.connection.identity.addonID == owner }.count
         + parked.values.filter { $0.connection.identity.addonID == owner }.count) * RuntimeServiceAcquisitionState.bytes
    }
}
