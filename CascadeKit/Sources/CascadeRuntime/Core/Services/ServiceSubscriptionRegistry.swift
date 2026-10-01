//
//  ServiceSubscriptionRegistry.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

struct ServiceSubscriptionRegistry: Sendable {

    struct Alias: Sendable {

        let id               : UUID
        let connection       : RuntimeConnection
        let interestID       : UUID
        let sourceID         : UUID
        let permissionID     : UUID
        let requirementID    : String
        var grantID          : UUID
        var deadline         : Duration
        var revision         : UInt64 = 1
        var pendingRevision  : UInt64 = 0
        var deliveredRevision: UInt64 = 0
        var receipt          : RuntimeServiceSubscriptionReceipt?

        static let bytes = max(2_048, MemoryLayout<Self>.stride * 4 + RuntimeServiceConnectionState.receiptBytes)
    }

    static let maximumAliases  = 256
    static let maximumPerOwner = 64

    var aliases: [UUID: Alias] = [:]
    // Cursor is scalar ordering state; UUID ordering is stable for a connection.
    var cursor : [RuntimeIncarnation: UUID] = [:]

    func retainedBytes(owner: AddonID) -> Int {
        aliases.values.filter { $0.connection.identity.addonID == owner }.count * Alias.bytes
    }

    func existing(
        interestID : UUID,
        incarnation: RuntimeIncarnation
    ) -> Alias? {
        aliases.values.first { $0.interestID == interestID && $0.connection.incarnation == incarnation }
    }

    func next(incarnation: RuntimeIncarnation) -> Alias? {
        let ready = aliases.values.filter {
            $0.connection.incarnation == incarnation && $0.receipt == nil && $0.pendingRevision > $0.deliveredRevision
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        guard let last = cursor[incarnation] else { return ready.first }

        return ready.first { $0.id.uuidString > last.uuidString } ?? ready.first
    }
}
