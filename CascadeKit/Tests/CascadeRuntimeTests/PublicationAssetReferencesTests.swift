//
//  PublicationAssetReferencesTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct PublicationAssetReferencesTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let identity: VerifiedAddonIdentity

    init() throws {
        identity = VerifiedAddonIdentity(
            publisher: "test.publisher",
            addonID  : try #require(AddonID(rawValue: "com.example.assets"))
        )
    }

    private struct Reference: Equatable {
        let id: String
        let privacy: ContentDocument.Privacy
    }

    private func document(
        _ id   : String,
        privacy: ContentDocument.Privacy = .publicContent
    ) throws -> ContentDocument {
        // Declared assets count even when the root does not currently draw them.
        try ContentDocument(
            root              : .text("Ready"),
            privacy           : privacy,
            accessibilityLabel: "Ready",
            assetIDs          : [id]
        )
    }

    private func representations(_ prefix: String) throws -> PresentationSet {
        try PresentationSet(
            widget: document(prefix + ".widget"),
            compactLeading: document(prefix + ".leading", privacy: .sensitive),
            compactTrailing: document(prefix + ".trailing"),
            minimal: document(prefix + ".minimal", privacy: .sensitive),
            expanded: document(prefix + ".expanded")
        )
    }

    private func publication(
        id      : PublicationID? = nil,
        revision: UInt64 = 1,
        content : PresentationSet? = nil,
        timeline: [ScheduledEntry]? = nil,
        kind    : Publication.Kind = .widget,
        duration: TimeInterval = 60
    ) throws -> Publication {
        try Publication(
            id: id ?? PublicationID(
                addonID   : identity.addonID,
                instanceID: UUID(),
                sessionID : UUID()
            ),
            revision   : revision,
            kind       : kind,
            content    : timeline == nil ? (content ?? representations("current")) : nil,
            timeline   : timeline,
            expiresAt  : now.addingTimeInterval(duration),
            stalePolicy: .retainMarked
        )
    }

    private func references(_ publication: Publication) -> [Reference] {
        var values: [Reference] = []
        publication.forEachAssetReference { values.append(Reference(id: $0, privacy: $1)) }
        return values
    }

    private func connect(
        _ state: inout PublicationState,
        ids    : [PublicationID]
    ) throws -> PublicationConnection {
        try state.openConnection(
            identity        : identity,
            verifiedDigest  : "test-digest",
            manifestProtocol: ProtocolVersion(
                major       : 1,
                minimumMinor: 0
            ),
            offer: ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            ),
            authorizedPublications: ids
        )
    }

    private func output(
        _ publications: [Publication],
        ends          : [PublicationID] = []
    ) throws -> ProviderOutput {
        try ProviderOutput(
            schemaVersion: 1,
            publications : publications,
            operations   : ends.map { .endPublication($0) },
            completion   : nil,
            checkpoint   : nil
        )
    }

    private func changes(_ prepared: PublicationState.PreparedOutput) -> [Publication] {
        var values: [Publication] = []
        prepared.forEachChangedPublication { values.append($0) }
        return values
    }

    private func endedIDs(_ prepared: PublicationState.PreparedOutput) -> Set<PublicationID> {
        var ids: Set<PublicationID> = []
        prepared.forEachEndedPublicationID { ids.insert($0) }
        return ids
    }

    @Test func visitsDeclaredAssetsInEveryRepresentationWithDocumentPrivacy() throws {
        let values = references(try publication())
        #expect(values == [
            Reference(id: "current.widget", privacy: .publicContent),
            Reference(id: "current.leading", privacy: .sensitive),
            Reference(id: "current.trailing", privacy: .publicContent),
            Reference(id: "current.minimal", privacy: .sensitive),
            Reference(id: "current.expanded", privacy: .publicContent),
        ])
    }

    @Test func sameAssetIDKeepsEachDocumentPrivacy() throws {
        let content = try PresentationSet(widget: document("shared"),
            compactLeading: document("shared", privacy: .sensitive), compactTrailing: nil,
            minimal: nil, expanded: nil)
        #expect(references(try publication(content: content)) == [
            Reference(id: "shared", privacy: .publicContent),
            Reference(id: "shared", privacy: .sensitive),
        ])
    }

    @Test func preparedProjectionPreservesFutureEntriesAndExcludesHostClippedEntries() throws {
        var state = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let value = try publication(timeline: [
            ScheduledEntry(date: now, content: representations("due")),
            ScheduledEntry(date: now.addingTimeInterval(7 * 3_600), content: representations("future")),
            ScheduledEntry(date: now.addingTimeInterval(8 * 3_600), content: representations("clipped")),
        ], kind: .activity, duration: 9 * 3_600)
        let connection = try connect(&state, ids: [value.id])
        let prepared = try state.prepareOutput(
            output([value]),
            connection: connection,
            generation: connection.generation,
            sequence  : 1
        )
        let admitted = try #require(changes(prepared).first)
        #expect(changes(prepared).count == 1)
        #expect(admitted.expiresAt == now.addingTimeInterval(8 * 3_600))
        #expect(admitted.timeline?.count == 2)
        #expect(Set(references(admitted).map(\.id)) == [
            "due.widget", "due.leading", "due.trailing", "due.minimal", "due.expanded",
            "future.widget", "future.leading", "future.trailing", "future.minimal", "future.expanded",
        ])
        #expect(state.publication(id: value.id, at: now) == nil)
        _ = try state.commitPreparedOutput(prepared, at: now)
        #expect(state.publication(id: value.id, at: now) == admitted)
        let visible = try #require(state.snapshot(at: now).first)
        #expect(visible.timeline == nil)
        #expect(references(visible).count == 5)
    }

    @Test func endedProjectionUsesCanonicalChangesInsteadOfRawOperations() throws {
        var state = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let existing          = try publication()
        let insertedThenEnded = try publication()
        let missing           = try publication()
        let surviving = try publication()
        let untouched = try publication()
        let connection = try connect(&state, ids: [existing.id, insertedThenEnded.id, missing.id, surviving.id, untouched.id])
        try state.accept([existing, untouched], owner: identity.addonID)
        let prepared = try state.prepareOutput(
            output([insertedThenEnded, surviving], ends: [existing.id, insertedThenEnded.id, missing.id]),
            connection: connection, generation: connection.generation, sequence: 1)
        #expect(changes(prepared) == [surviving])
        #expect(endedIDs(prepared) == [existing.id, insertedThenEnded.id])
        #expect(state.publication(id: existing.id, at: now) == existing)
        _ = try state.commitPreparedOutput(prepared, at: now)
        #expect(state.publication(id: existing.id, at: now) == nil)
        #expect(state.publication(id: insertedThenEnded.id, at: now) == nil)
        #expect(state.publication(id: surviving.id, at: now) == surviving)
        #expect(state.publication(id: untouched.id, at: now) == untouched)
    }

    @Test func failedAndStalePreparationsNeverChangeCanonicalReferences() throws {
        var state = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let original = try publication()
        let other    = try publication()
        let connection = try connect(&state, ids: [original.id, other.id])
        try state.accept([original, other], owner: identity.addonID)
        let updated = try publication(id: original.id, revision: 2, content: representations("replacement"))
        #expect(throws: AddonFailure.self) {
            try state.prepareOutput(
                output([updated, other]),
                connection: connection,
                generation: connection.generation,
                sequence  : 1
            )
        }
        #expect(state.publication(id: original.id, at: now) == original)
        let prepared = try state.prepareOutput(
            output([updated]),
            connection: connection,
            generation: connection.generation,
            sequence  : 1
        )
        #expect(changes(prepared) == [updated])
        #expect(state.publication(id: original.id, at: now) == original)
        try state.remove(id: other.id, owner: identity.addonID)
        #expect(throws: AddonFailure.self) { try state.commitPreparedOutput(prepared, at: now) }
        #expect(state.publication(id: original.id, at: now) == original)
        let retry = try state.prepareOutput(
            output([updated]),
            connection: connection,
            generation: connection.generation,
            sequence  : 1
        )
        _ = try state.commitPreparedOutput(retry, at: now)
        #expect(state.publication(id: original.id, at: now) == updated)
    }
}
