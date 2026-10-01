//
//  ActionAuthorizerTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct ActionAuthorizerTests {
    @Test
    func currentDeclaredNestedActionIsUsableWithoutResidentProvider() throws {
        let fixture = try ActionFixture()
        try ActionAuthorizer.validate(
            fixture.request(),
            context: fixture.context(blockedFeature: "other"),
            at     : fixture.wall
        )
    }

    @Test
    func authorizerRejectsEachDistinctAuthorityFailure() throws {
        let fixture = try ActionFixture()
        let request = try fixture.request()
        let cases: [(ActionAuthorizer.Context, ActionAuthorizer.Failure)] = try [
            (fixture.context(enabled: false), .unavailable),
            (fixture.context(eligibility: .privacyRedacted), .unavailable),
            (fixture.context(eligibility: .stale), .unavailable),
            (fixture.context(eligibility: .hidden), .unavailable),
            (fixture.context(eligibility: .unavailable), .unavailable),
            (fixture.context(blockedRoot: true), .unavailable),
            (fixture.context(blockedFeature: "controls"), .featureUnavailable),
            (fixture.context(feature: "missing"), .featureUnavailable),
            (fixture.context(declarations: nil), .undeclaredAction),
            (fixture.context(declarations: []), .undeclaredAction),
            (fixture.context(declarations: ["play"]), .undeclaredAction),
            (fixture.context(action: "play"), .unpublishedAction),
            (fixture.context(payload: Data([8])), .payloadMismatch),
            (fixture.context(revision: 2), .staleRevision),
            (fixture.context(otherPayload: Data([8])), .ambiguousPayload)
        ]
        for (context, failure) in cases {
            #expect(throws: failure) {
                try ActionAuthorizer.validate(
                    request,
                    context: context,
                    at     : fixture.wall
                )
            }
        }
        let foreign = try ActionFixture(ownerName: "com.example.foreign")
        #expect(throws: ActionAuthorizer.Failure.identityMismatch) {
            try ActionAuthorizer.validate(
                request,
                context: foreign.context(),
                at     : fixture.wall
            )
        }
    }

    @Test
    func timelineUsesOnlyLatestVisibleEntryAndExpires() throws {
        let fixture = try ActionFixture()
        let entries = try [
            ScheduledEntry(
                date   : fixture.wall.addingTimeInterval(2),
                content: fixture.presentation()
            ),
            ScheduledEntry(
                date   : fixture.wall.addingTimeInterval(5),
                content: fixture.presentation(payload: Data([8]))
            )
        ]
        let context = try fixture.context(timeline: entries)
        #expect(throws: ActionAuthorizer.Failure.unpublishedAction) {
            try ActionAuthorizer.validate(
                fixture.request(),
                context: context,
                at     : fixture.wall
            )
        }
        try ActionAuthorizer.validate(
            fixture.request(),
            context: context,
            at     : fixture.wall.addingTimeInterval(3)
        )
        #expect(throws: ActionAuthorizer.Failure.payloadMismatch) {
            try ActionAuthorizer.validate(
                fixture.request(),
                context: context,
                at     : fixture.wall.addingTimeInterval(5)
            )
        }
        #expect(throws: ActionAuthorizer.Failure.expired) {
            try ActionAuthorizer.validate(
                fixture.request(),
                context: context,
                at     : fixture.wall.addingTimeInterval(20)
            )
        }
        try ActionAuthorizer.validate(
            fixture.request(),
            context: fixture.context(otherPayload: Data([7])),
            at     : fixture.wall
        )
    }
    @Test
    func defaultEligibilityAndMissingPublicationFailClosed() throws {
        let fixture = try ActionFixture()
        let base = try fixture.context()
        let defaultContext = ActionAuthorizer.Context(
            installed  : base.installed,
            resolution : base.resolution,
            featureID  : base.featureID,
            publication: base.publication
        )
        #expect(throws: ActionAuthorizer.Failure.unavailable) {
            try ActionAuthorizer.validate(
                fixture.request(),
                context: defaultContext,
                at     : fixture.wall
            )
        }
        let missing = ActionAuthorizer.Context(
            installed  : base.installed,
            resolution : base.resolution,
            featureID  : base.featureID,
            publication: nil,
            eligibility: .available
        )
        #expect(throws: ActionAuthorizer.Failure.identityMismatch) {
            try ActionAuthorizer.validate(
                fixture.request(),
                context: missing,
                at     : fixture.wall
            )
        }
    }

    @Test
    func missingPayloadIsEmptyAndPublicationExpiryRemainsCivil() throws {
        let fixture = try ActionFixture()
        let base = try fixture.context()
        let node = try ContentNode(
            kind    : .action,
            text    : "Pause",
            assetID : nil,
            value   : nil,
            deadline: nil,
            actionID: "pause",
            children: nil
        )
        let document = try ContentDocument(
            root               : node,
            privacy            : .sensitive,
            accessibilityLabel : "Controls"
        )
        let content = try PresentationSet(
            widget         : document,
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
        let publication = try Publication(
            id         : fixture.publicationID,
            revision   : 1,
            kind       : .widget,
            content    : content,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(5),
            stalePolicy: .retainMarked
        )
        let context = ActionAuthorizer.Context(
            installed  : base.installed,
            resolution : base.resolution,
            featureID  : base.featureID,
            publication: publication,
            eligibility: .available
        )
        try ActionAuthorizer.validate(
            fixture.request(input: Data()),
            context: context,
            at     : fixture.wall
        )
        #expect(throws: ActionAuthorizer.Failure.expired) {
            try ActionAuthorizer.validate(
                fixture.request(input: Data()),
                context: context,
                at     : fixture.wall.addingTimeInterval(5)
            )
        }
    }

}
