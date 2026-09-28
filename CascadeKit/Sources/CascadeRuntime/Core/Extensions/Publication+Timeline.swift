//
//  Publication+Timeline.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

extension Publication {
    func validateOwnerAndStructure(_ owner: AddonID) throws {
        try id.validateOwner(owner)
        try validate()
    }

    func capped(at deadline: Date) throws -> Publication {
        let expiry = min(expiresAt, deadline)
        let entries = timeline?.filter { $0.date < expiry }
        guard entries == nil || entries?.isEmpty == false else {
            throw AddonFailure(code: .deadlineExceeded, reason: "No timeline entry precedes the host session deadline.")
        }
        return try Publication(id: id, revision: revision, kind: kind, content: content, timeline: entries, expiresAt: expiry, stalePolicy: stalePolicy)
    }

    func presentation(at date: Date) -> Publication? {
        guard let timeline else { return self }
        // Preserve pending identity. The bridge distinguishes waiting from an
        // absent (revoked/expired) publication, without mounting a view yet.
        guard let due = timeline.last(where: { $0.date <= date }) else { return self }
        return try? Publication(id: id, revision: revision, kind: kind, content: due.content, timeline: nil, expiresAt: expiresAt, stalePolicy: stalePolicy)
    }
}
