//
//  PublicationStoreTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct PublicationStoreTests {

    private let now   = Date(timeIntervalSince1970: 2_000_000_000)
    private let owner = AddonID(rawValue: "com.example.focus")!

    private func publication(
        id      : PublicationID? = nil,
        revision: UInt64 = 1,
        text    : String = "Focus",
        timeline: [ScheduledEntry]? = nil,
        duration: TimeInterval = 60
    ) throws -> Publication {
        try Publication(
            id         : id ?? PublicationID(addonID: owner, instanceID: UUID(), sessionID: UUID()),
            revision   : revision,
            kind       : .widget,
            content    : timeline == nil ? content(text) : nil,
            timeline   : timeline,
            expiresAt  : now.addingTimeInterval(duration),
            stalePolicy: .remove
        )
    }

    private func content(_ text: String) throws -> PresentationSet {
        try PresentationSet(
            widget         : ContentDocument(root: .text(text), privacy: .publicContent, accessibilityLabel: text),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
    }

    @Test
    func publicationOutlivesItsProducer() async throws {
        final class Producer {

            let value: Publication

            init(_ value: Publication) { self.value = value }
        }

        let store = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        var producer: Producer? = Producer(try publication())
        weak let weakProducer = producer
        let expected = producer!.value
        try await store.accept(expected, owner: owner)

        producer = nil
        #expect(weakProducer == nil)
        #expect(await store.snapshot(at: now) == [expected])
    }

    @Test
    func rejectsReplayAndWrongOwnerWithoutReplacingContent() async throws {
        let store = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let first = try publication(revision: 2)
        try await store.accept(first, owner: owner)
        await #expect(throws: AddonFailure.self) {
            try await store.accept(publication(id: first.id, revision: 1), owner: owner)
        }

        await #expect(throws: AddonFailure.self) {
            try await store.accept(
                publication(id: first.id, revision: 3),
                owner: AddonID(rawValue: "com.example.other")!
            )
        }

        #expect(await store.snapshot(at: now) == [first])
    }

    @Test
    func timelineUsesLastDueEntryAndDisableRemovesFutureEntries() async throws {
        let store  = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let first  = try content("First")
        let second = try content("Second")
        let plan   = try publication(
            timeline: [
                ScheduledEntry(date: now.addingTimeInterval(1), content: first),
                ScheduledEntry(date: now.addingTimeInterval(10), content: second)
            ]
        )

        try await store.accept(plan, owner: owner)
        // A pending session must remain identifiable; omission means revocation.
        #expect(await store.snapshot(at: now).first?.timeline == plan.timeline)
        #expect(await store.snapshot(at: now).first?.content == nil)
        #expect(await store.snapshot(at: now.addingTimeInterval(1)).first?.content == first)
        #expect(await store.snapshot(at: now.addingTimeInterval(11)).first?.content == second)

        await store.remove(owner: owner)
        #expect(await store.snapshot(at: now.addingTimeInterval(12)).isEmpty)
        #expect(await store.retainedBytes == 0)
    }

    @Test
    func expiryRemovesEvenRetainMarkedAndKeepsRevisionTombstone() async throws {
        let store = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let first = try publication(duration: 1)
        try await store.accept(first, owner: owner)
        await store.expire(at: now.addingTimeInterval(2))
        #expect(await store.snapshot(at: now.addingTimeInterval(2)).isEmpty)

        await #expect(throws: AddonFailure.self) { try await store.accept(first, owner: owner) }
    }

    @Test
    func boundsStateAndInstanceAdmissionTransactionally() async throws {
        let store = PublicationStore(
            maximumRetainedBytes: 2_048,
            now                 : { Date(timeIntervalSince1970: 2_000_000_000) }
        )

        let first = try publication()
        try await store.accept(first, owner: owner)
        let bytes = await store.retainedBytes
        await #expect(throws: AddonFailure.self) {
            try await store.accept(
                publication(text: String(repeating: "a", count: 2_000)),
                owner: owner
            )
        }

        #expect(await store.retainedBytes == bytes)
        #expect(await store.snapshot(at: now) == [first])

        let standard = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        for _ in 0..<16 { try await standard.accept(publication(), owner: owner) }
        await #expect(throws: AddonFailure.self) { try await standard.accept(publication(), owner: owner) }
        #expect(await standard.snapshot(at: now).count == 16)
    }

    @Test
    func rejectsExpiredInputAndNonfiniteSnapshotDate() async throws {
        let store = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        await #expect(throws: AddonFailure.self) { try await store.accept(publication(duration: -1), owner: owner) }
        #expect(await store.snapshot(at: Date(timeIntervalSince1970: .nan)).isEmpty)
    }

    @Test
    func explicitEndCannotBeResurrectedWithHigherRevision() async throws {
        let store = PublicationStore(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let first = try publication()
        try await store.accept(first, owner: owner)
        try await store.remove(id: first.id, owner: owner)
        await #expect(throws: AddonFailure.self) {
            try await store.accept(publication(id: first.id, revision: 2), owner: owner)
        }

        #expect(await store.snapshot(at: now).isEmpty)
    }
}
