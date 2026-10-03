//
//  AddonOptionsOrigin.swift
//  CascadeKit
//

import Foundation
import Synchronization

/// AddonOptionsOrigin carries a host-captured, revocable action origin across actors.
/// It is deliberately not Codable. Only the presenter holding the identical instance
/// can resolve it to a display and saved selection; constructing a copy grants nothing.
public final class AddonOptionsOrigin: Sendable {

    public let publicationID   : PublicationID
    public let observedRevision: UInt64
    private let validity = Mutex(true)

    public init(
        publicationID   : PublicationID,
        observedRevision: UInt64
    ) {
        self.publicationID    = publicationID
        self.observedRevision = observedRevision
    }

    public var isValid: Bool { validity.withLock { $0 } }

    /// revoke makes copied controls and delayed projections inert synchronously.
    public func revoke() { validity.withLock { $0 = false } }
}
