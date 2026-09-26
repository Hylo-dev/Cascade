import CascadeContracts
import Foundation

/// One two-phase control route. No payload, task or continuation is retained here.
struct RuntimeServiceAcquisitionState: Sendable {
    let id: UUID
    let connection: RuntimeConnection
    let sequence: UInt64
    let request: ServiceControlRequest
    var deadline: Duration
    var committed = false
    var acquisition: ServiceAcquisition?
    var needsStart = false
    var admissionReceived = false
    // A physically settled row remains paid until its canonical start disposition
    // is drained. This closes the commit/connection-close suspension window.
    var transportSettled = false
    var terminal: ServiceControlResult?
    var receipt: RuntimeServiceSubscriptionReceipt?
    static let bytes = max(4_096, MemoryLayout<Self>.stride * 4 + RuntimeServiceConnectionState.receiptBytes)
}
