//
//  PublicationRestorationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct PublicationRestorationTests {

    private let owner   : AddonID
    private let identity: VerifiedAddonIdentity
    private let instant  = Date(timeIntervalSince1970: 2_000_000_000)

    init() throws {
        owner    = try #require(AddonID(rawValue: "com.example.restoration"))
        identity = VerifiedAddonIdentity(publisher: "publisher", addonID: owner)
    }

    private func content(kind: Publication.Kind = .widget) throws -> PresentationSet {
        let document = try ContentDocument(
            root              : .text("Restored"),
            privacy           : .publicContent,
            accessibilityLabel: "Restored"
        )

        return try PresentationSet(
            widget         : kind == .widget ? document : nil,
            compactLeading : kind == .widget ? nil : document,
            compactTrailing: kind == .widget ? nil : document,
            minimal        : kind == .widget ? nil : document,
            expanded       : kind == .activity ? document : nil
        )
    }

    private func publication(
        id      : PublicationID? = nil,
        revision: UInt64 = 0,
        kind    : Publication.Kind = .widget,
        timeline: [ScheduledEntry]? = nil,
        expires : Date? = nil
    ) throws -> Publication {
        try Publication(
            id         : id ?? PublicationID(
                addonID   : owner,
                instanceID: UUID(),
                sessionID : UUID()
            ),
            revision   : revision,
            kind       : kind,
            content    : timeline == nil ? content(kind: kind) : nil,
            timeline   : timeline,
            expiresAt  : expires ?? instant.addingTimeInterval(100_000),
            stalePolicy: .retainMarked
        )
    }

    private func record(
        _ publication: Publication,
        deadline     : Date? = nil
    ) -> PublicationArchiveRecord {
        PublicationArchiveRecord(
            id             : publication.id,
            revision       : publication.revision,
            kind           : publication.kind,
            sessionDeadline: deadline ?? publication.expiresAt,
            publication    : publication
        )
    }

    private func captured(
        _ state: PublicationState,
        at date: Date? = nil
    ) throws -> [PublicationArchiveRecord] {
        var result: [PublicationArchiveRecord] = []
        try state.forEachArchivedRecord(owner: owner, at: date ?? instant) { result.append($0) }

        return result
    }

    @Test
    func originalActivityAnchorSurvivesRestoreAndLaterHigherRevision() throws {
        var original = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let activity = try publication(kind: .activity)
        try original.accept(activity, owner: owner)

        let records  = try captured(original)
        let archived = try #require(records.first)
        #expect(archived.sessionDeadline == instant.addingTimeInterval(8 * 3_600))
        #expect(archived.revision == 0)

        var restored = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000 + 7 * 3_600) })
        let prepared = try restored.prepareRestoration(
            records,
            identity: identity,
            at      : instant.addingTimeInterval(6 * 3_600)
        )
        #expect(prepared.namespaceBytes == 1_024)
        #expect(prepared.newFamilies[activity.id] == .activity)
        #expect(restored.retainedBytes == 0)

        try restored.validatePreparedRestoration(
            prepared,
            at: instant.addingTimeInterval(6 * 3_600)
        )
        restored.commitPreparedRestoration(prepared)
        try restored.accept(
            publication(
                id      : activity.id,
                revision: 1,
                kind    : .activity
            ),
            owner: owner
        )

        let updated = try #require(captured(restored).first)
        #expect(updated.sessionDeadline == archived.sessionDeadline)
        #expect(updated.publication?.expiresAt == archived.sessionDeadline)
        #expect(restored.sessionAccounting(owner: owner).connectionBytes == 0)
        #expect(restored.sessionAccounting(owner: owner).namespaceBytes == 1_024)
    }

    @Test
    func capturePreservesCompleteTimelineAndExcludesNoticesWithoutMutation() throws {
        let entries = try [1_000.0, 2_000.0].map { offset in
            try ScheduledEntry(date: instant.addingTimeInterval(offset), content: content())
        }
        let timeline = try publication(timeline: entries)
        var original = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        try original.accept(timeline, owner: owner)
        try original.accept(publication(kind: .notice), owner: owner)

        let before  = original.retainedBytes
        let records = try captured(original, at: instant.addingTimeInterval(1_500))
        #expect(records.count == 1)
        #expect(records.first?.publication?.timeline == entries)
        #expect(original.retainedBytes == before)

        var restored = PublicationState()
        let prepared = try restored.prepareRestoration(
            records,
            identity: identity,
            at      : instant.addingTimeInterval(1_500)
        )
        var proposedPublications: [Publication] = []
        prepared.forEachRestoredPublication { proposedPublications.append($0) }
        #expect(proposedPublications.first?.timeline == entries)

        try restored.validatePreparedRestoration(prepared, at: instant.addingTimeInterval(1_500))
        restored.commitPreparedRestoration(prepared)
        #expect(try captured(restored).first?.publication?.timeline == entries)
    }

    @Test
    func explicitEndAndElapsedContentRestoreAsTerminalHistory() throws {
        let ended    = try publication()
        let elapsed  = try publication(expires: instant.addingTimeInterval(5))
        var original = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        try original.accept([ended, elapsed], owner: owner)
        try original.remove(id: ended.id, owner: owner)

        let before              = original.retainedBytes
        let capturedAfterExpiry = try captured(original, at: instant.addingTimeInterval(10))
        #expect(capturedAfterExpiry.count == 2)
        #expect(capturedAfterExpiry.allSatisfy { $0.publication == nil })
        #expect(original.retainedBytes == before)

        let records  = try captured(original)
        var restored = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_010) })
        let prepared = try restored.prepareRestoration(
            records,
            identity: identity,
            at      : instant.addingTimeInterval(10)
        )
        #expect(prepared.newFamilies.isEmpty)

        var terminalIDs: [PublicationID] = []
        prepared.forEachTerminalPublicationID { terminalIDs.append($0) }
        #expect(Set(terminalIDs) == Set([ended.id, elapsed.id]))
        #expect(prepared.additionalBytes == 3 * 1_024)

        try restored.validatePreparedRestoration(prepared, at: instant.addingTimeInterval(10))
        restored.commitPreparedRestoration(prepared)

        for id in [ended.id, elapsed.id] {
            #expect(throws: AddonFailure.self) {
                try restored.accept(publication(id: id, revision: 1), owner: owner)
            }
            #expect(restored.recordAccounting(id: id)?.revision == 0)
        }

        #expect(restored.snapshot(at: instant.addingTimeInterval(10)).isEmpty)
    }

    @Test
    func malformedLaterRecordAndQuotaFailureLeaveNamespaceAndRecordsUnchanged() throws {
        let first      = try publication()
        let mismatched = PublicationArchiveRecord(
            id             : first.id,
            revision       : 99,
            kind           : first.kind,
            sessionDeadline: first.expiresAt,
            publication    : first
        )
        var state = PublicationState()
        #expect(throws: AddonFailure.self) {
            try state.prepareRestoration(
                [record(try publication()), mismatched],
                identity: identity,
                at      : instant
            )
        }
        #expect(state.retainedBytes == 0)
        #expect(state.sessionAccounting(owner: owner).namespaceBytes == 0)

        let small = PublicationState(maximumRetainedBytes: 2 * 1_024)
        #expect(throws: AddonFailure.self) {
            try small.prepareRestoration(
                [record(first)],
                identity: identity,
                at      : instant
            )
        }
        #expect(small.retainedBytes == 0)

        let prepared = try state.prepareRestoration(
            [record(first)],
            identity: identity,
            at      : instant
        )
        try state.validatePreparedRestoration(prepared, at: instant)
        state.commitPreparedRestoration(prepared)

        let before = state.retainedBytes
        #expect(throws: AddonFailure.self) {
            try state.prepareRestoration(
                [record(first)],
                identity: identity,
                at      : instant
            )
        }
        #expect(throws: AddonFailure.self) {
            try state.prepareRestoration(
                [],
                identity: VerifiedAddonIdentity(publisher: "foreign", addonID: owner),
                at      : instant
            )
        }
        #expect(state.retainedBytes == before)
    }

    @Test
    func foreignStaleAndExpiredPreparedValuesCannotCommit() throws {
        var state    = PublicationState()
        let value    = try publication(expires: instant.addingTimeInterval(5))
        let prepared = try state.prepareRestoration(
            [record(value)],
            identity: identity,
            at      : instant
        )
        let foreign = PublicationState()
        #expect(throws: AddonFailure.self) {
            try foreign.validatePreparedRestoration(prepared, at: instant)
        }

        for date in [instant.addingTimeInterval(-1), instant.addingTimeInterval(5), Date(timeIntervalSince1970: .nan)] {
            #expect(throws: AddonFailure.self) {
                try state.validatePreparedRestoration(prepared, at: date)
            }
        }

        try state.accept(publication(), owner: owner)
        #expect(throws: AddonFailure.self) {
            try state.validatePreparedRestoration(prepared, at: instant)
        }
        #expect(state.recordAccounting(id: value.id) == nil)
    }

    @Test
    func terminalRecordCountIsIndependentOfActivePublicationCapacity() throws {
        let records = try (0..<17).map { _ in
            let value = try publication()
            return PublicationArchiveRecord(
                id             : value.id,
                revision       : 0,
                kind           : .widget,
                sessionDeadline: value.expiresAt,
                publication    : nil
            )
        }
        var state    = PublicationState()
        let prepared = try state.prepareRestoration(
            records,
            identity: identity,
            at      : instant
        )
        #expect(prepared.additionalBytes == 18 * 1_024)
        #expect(prepared.newFamilies.isEmpty)

        try state.validatePreparedRestoration(prepared, at: instant)
        state.commitPreparedRestoration(prepared)
        #expect(try captured(state).count == 17)

        let live = try (0..<17).map { _ in record(try publication()) }
        #expect(throws: AddonFailure.self) {
            try state.prepareRestoration(
                live,
                identity: identity,
                at      : instant
            )
        }
        #expect(try captured(state).count == 17)
    }

    @Test
    func invalidOwnerNoticeDeadlineAndDuplicateNeverBindNamespace() throws {
        let value        = try publication()
        let foreignOwner = try #require(AddonID(rawValue: "com.example.foreign"))
        let invalid      = [
            record(try publication(kind: .notice)),
            record(value, deadline: instant),
            record(value, deadline: Date(timeIntervalSince1970: .infinity)),
            PublicationArchiveRecord(
                id             : PublicationID(
                    addonID   : foreignOwner,
                    instanceID: UUID(),
                    sessionID : UUID()
                ),
                revision       : 0,
                kind           : .widget,
                sessionDeadline: value.expiresAt,
                publication    : nil
            ),
        ]
        let state = PublicationState()

        for item in invalid {
            #expect(throws: AddonFailure.self) {
                try state.prepareRestoration(
                    [item],
                    identity: identity,
                    at      : instant
                )
            }
        }

        #expect(throws: AddonFailure.self) {
            try state.prepareRestoration(
                [record(value), record(value)],
                identity: identity,
                at      : instant
            )
        }
        #expect(state.retainedBytes == 0)
    }

    @Test
    func existingActivityFamiliesAndNamespaceCapacityRemainEnforced() throws {
        var state = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })

        for index in 0..<4 {
            let otherOwner = try #require(AddonID(rawValue: "com.example.activity\(index)"))

            for _ in 0..<4 {
                try state.accept(
                    publication(
                        id  : PublicationID(
                            addonID   : otherOwner,
                            instanceID: UUID(),
                            sessionID : UUID()
                        ),
                        kind: .activity
                    ),
                    owner: otherOwner
                )
            }
        }

        let before = state.retainedBytes
        #expect(throws: AddonFailure.self) {
            try state.prepareRestoration(
                [record(try publication(kind: .activity))],
                identity: identity,
                at      : instant
            )
        }
        #expect(state.retainedBytes == before)
        #expect(state.sessionAccounting(owner: owner).namespaceBytes == 0)

        let unavailable = PublicationState(maximumPublisherNamespaces: 0)
        #expect(throws: AddonFailure.self) {
            try unavailable.prepareRestoration(
                [record(try publication())],
                identity: identity,
                at      : instant
            )
        }
    }

    @Test
    func divergentStateCopiesCannotExchangeRestorationProposalsAtEqualRevisions() throws {
        let empty             = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        var firstState        = empty
        var secondState       = empty
        let firstPublication  = try publication()
        let secondPublication = try publication(timeline: [
            ScheduledEntry(date: instant.addingTimeInterval(1_000), content: content()),
            ScheduledEntry(date: instant.addingTimeInterval(2_000), content: content()),
        ])
        try firstState.accept(firstPublication, owner: owner)
        try secondState.accept(secondPublication, owner: owner)

        let firstBytes  = firstState.retainedBytes
        let secondBytes = secondState.retainedBytes
        #expect(firstBytes != secondBytes)

        let firstRecords        = try captured(firstState)
        let secondRecords       = try captured(secondState)
        let restoredPublication = try publication()
        let prepared            = try firstState.prepareRestoration(
            [record(restoredPublication)],
            identity: identity,
            at      : instant
        )
        #expect(throws: AddonFailure.self) {
            try secondState.validatePreparedRestoration(prepared, at: instant)
        }
        #expect(firstState.retainedBytes == firstBytes)
        #expect(secondState.retainedBytes == secondBytes)
        #expect(try captured(firstState) == firstRecords)
        #expect(try captured(secondState) == secondRecords)

        try firstState.validatePreparedRestoration(prepared, at: instant)
        firstState.commitPreparedRestoration(prepared)
        #expect(firstState.retainedBytes == firstBytes + prepared.additionalBytes)
        #expect(firstState.recordAccounting(id: restoredPublication.id) != nil)
        #expect(secondState.recordAccounting(id: restoredPublication.id) == nil)
        #expect(secondState.retainedBytes == secondBytes)
    }
}
