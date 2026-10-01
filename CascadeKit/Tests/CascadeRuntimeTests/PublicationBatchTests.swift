//
//  PublicationBatchTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct PublicationBatchTests {

    let now   = Date(timeIntervalSince1970: 2_000_000_000)
    let owner = AddonID(rawValue: "com.example.batch")!

    func publication(
        id      : PublicationID? = nil,
        revision: UInt64 = 1
    ) throws -> Publication {
        try Publication(
            id         : id ?? PublicationID(addonID: owner, instanceID: UUID(), sessionID: UUID()),
            revision   : revision,
            kind       : .widget,
            content    : PresentationSet(
                widget         : ContentDocument(
                    root              : .text("Ready"),
                    privacy           : .publicContent,
                    accessibilityLabel: "Ready"
                ),
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            ),
            timeline   : nil,
            expiresAt  : now.addingTimeInterval(60),
            stalePolicy: .remove
        )
    }

    @Test
    func invalidLaterRevisionDoesNotCommitEarlierUpdate() async throws {
        let store  = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let first  = try publication()
        let second = try publication()

        try await store.accept(first, owner: owner)
        try await store.accept(second, owner: owner)

        let before = await store.snapshot(at: now)
        let bytes  = await store.retainedBytes

        await #expect(throws: AddonFailure.self) {
            try await store.accept([publication(id: first.id, revision: 2), second], owner: owner)
        }

        #expect(await store.snapshot(at: now) == before)
        #expect(await store.retainedBytes == bytes)

        // A failed batch must not advance replay history either.
        try await store.accept(publication(id: first.id, revision: 2), owner: owner)
    }

    @Test
    func batchExceedingInstanceCapacityLeavesNoPartialAdmission() async throws {
        let store = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        for _ in 0..<15 { try await store.accept(publication(), owner: owner) }

        let before   = await store.snapshot(at: now)
        let bytes    = await store.retainedBytes
        let rejected = try publication()

        await #expect(throws: AddonFailure.self) {
            try await store.accept([rejected, publication()], owner: owner)
        }

        #expect(await store.snapshot(at: now) == before)
        #expect(await store.retainedBytes == bytes)

        // A rolled-back insertion must restore both its record charge and replay state.
        try await store.accept(rejected, owner: owner)
    }

    @Test
    func rejectsDuplicateIdentityWithoutAcceptingEitherRevision() async throws {
        let store = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let first = try publication()

        await #expect(throws: AddonFailure.self) {
            try await store.accept([first, publication(id: first.id, revision: 2)], owner: owner)
        }

        #expect(await store.snapshot(at: now).isEmpty)
        #expect(await store.retainedBytes == 0)
    }

    @Test
    func validBatchCommitsEveryPublicationAndEmptyBatchIsInert() async throws {
        let store  = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let first  = try publication()
        let second = try publication()

        try await store.accept([first, second], owner: owner)

        let values = await store.snapshot(at: now)

        #expect(values.count == 2)
        #expect(values.contains(first) && values.contains(second))

        try await store.accept([], owner: owner)
        #expect(await store.snapshot(at: now) == values)
    }
}
