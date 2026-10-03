//
//  AddonOptionsPresentationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeKit

@MainActor
struct AddonOptionsPresentationTests {

    @Test
    func refreshUpdatesNativeContentAndRevokesCopiedControls() throws {
        let sink    = PresentationSinkFixture()
        var actions = 0
        let bridge  = AddonPresentationBridge(
            sink           : sink,
            onOptionsAction: { _, _, _, _ in actions += 1 }
        )
        let publication = try fixturePublication(kind: .widget, revision: 1, text: "Widget")
        bridge.apply([publication])
        let origin = AddonOptionsOrigin(publicationID: publication.id, observedRevision: 1)
        let first  = try optionsPresentation(publication, origin: origin, title: "First")
        #expect(bridge.presentOptions(first, onDismiss: {}))
        let firstPage = try #require(sink.optionsPage as? SnapshotOptionsPage)
        let copied    = firstPage.actions
        copied.dispatch(try ActionDescriptor(id: "detail", label: "Detail", payload: Data()))
        #expect(actions == 1)
        let second = try optionsPresentation(
            publication,
            origin    : origin,
            title     : "Second",
            leaseID   : first.request.leaseID,
            actionID  : first.request.actionRequestID,
            generation: first.generation
        )
        #expect(bridge.presentOptions(second, onDismiss: {}))
        let secondPage = try #require(sink.optionsPage as? SnapshotOptionsPage)
        #expect(secondPage.accessibilityLabel == "Second")
        #expect(secondPage.contentRevision > firstPage.contentRevision)
        copied.dispatch(try ActionDescriptor(id: "detail", label: "Detail", payload: Data()))
        #expect(actions == 1)
        bridge.dismissOptions(leaseID: first.request.leaseID)
    }

    @Test
    func obsoleteDismissCallbackCannotAffectALaterOriginWithTheSameUUID() throws {
        let sink   = PresentationSinkFixture()
        let bridge = AddonPresentationBridge(sink: sink)
        let source = try fixturePublication(kind: .widget, revision: 1, text: "Widget")
        bridge.apply([source])
        let firstOrigin = AddonOptionsOrigin(publicationID: source.id, observedRevision: 1)
        let first       = try optionsPresentation(source, origin: firstOrigin, title: "First")
        #expect(bridge.presentOptions(first, onDismiss: {}))
        let oldCallback = try #require(sink.optionsDismiss)
        bridge.dismissOptions(leaseID: first.request.leaseID)
        let nextOrigin = AddonOptionsOrigin(publicationID: source.id, observedRevision: 1)
        let next       = try optionsPresentation(
            source,
            origin : nextOrigin,
            title  : "Next",
            leaseID: first.request.leaseID
        )
        #expect(bridge.presentOptions(next, onDismiss: {}))
        oldCallback()
        #expect(nextOrigin.isValid)
        bridge.dismissOptions(leaseID: next.request.leaseID)
    }

    @Test
    func sensitiveDetailDoesNotExposeItsTitle() throws {
        let source = try fixturePublication(kind: .widget, revision: 1, text: "Widget")
        let page = try SnapshotOptionsPage(
            id      : "private",
            document: ContentDocument(root: .text("Secret"), privacy: .sensitive, accessibilityLabel: "Secret title"),
            assets  : ScopedAssetResolver(base: EmptyAddonAssetResolver(), publicationID: source.id, publicationRevision: 1),
            actions : ActionLease { _ in }
        )
        #expect(page.accessibilityLabel != "Secret title")
    }

    @Test
    func sourceRedactionDismissesDetailImmediately() throws {
        let sink   = PresentationSinkFixture()
        let bridge = AddonPresentationBridge(sink: sink)
        let source = try fixturePublication(kind: .widget, revision: 1, text: "Widget")
        bridge.apply([source])
        let origin = AddonOptionsOrigin(publicationID: source.id, observedRevision: 1)
        #expect(
            bridge.presentOptions(
                try optionsPresentation(source, origin: origin, title: "Detail"),
                onDismiss: {}
            )
        )
        let redacted = try Publication(
            id                        : source.id,
            revision                  : 2,
            kind                      : .widget,
            content                   : PresentationSet(
                widget                : ContentDocument(
                    root              : .text("Secret"),
                    privacy           : .sensitive,
                    accessibilityLabel: "Secret"
                ),
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            ),
            timeline   : nil,
            expiresAt  : source.expiresAt,
            stalePolicy: .remove
        )
        bridge.apply([redacted])
        #expect(sink.optionsPage == nil)
        #expect(!origin.isValid)
    }

    @Test
    func sourceRevisionDisablesControlsWithoutChangingSelectionAndWithdrawalDismisses() throws {
        let sink       = PresentationSinkFixture()
        var actions    = 0
        var dismissals = 0
        let bridge     = AddonPresentationBridge(
            sink           : sink,
            onOptionsAction: { _, _, _, _ in actions += 1 }
        )
        let publication = try fixturePublication(kind: .widget, revision: 1, text: "Widget")
        bridge.apply([publication])
        let origin       = AddonOptionsOrigin(publicationID: publication.id, observedRevision: 1)
        let presentation = try optionsPresentation(publication, origin: origin, title: "Detail")
        #expect(bridge.presentOptions(presentation, onDismiss: { dismissals += 1 }))
        let page     = try #require(sink.optionsPage as? SnapshotOptionsPage)
        let copied   = page.actions
        let revision = page.contentRevision
        bridge.apply([
            try Publication(
                id         : publication.id,
                revision   : 2,
                kind       : .widget,
                content    : publication.content,
                timeline   : nil,
                expiresAt  : publication.expiresAt,
                stalePolicy: publication.stalePolicy
            )
        ])
        copied.dispatch(try ActionDescriptor(id: "detail", label: "Detail", payload: Data()))
        #expect(actions == 0)
        #expect(sink.optionsPage === page)
        #expect(page.contentRevision > revision)
        #expect(origin.isValid)
        bridge.apply([])
        #expect(!origin.isValid)
        #expect(sink.optionsPage == nil)
        #expect(dismissals == 1)
        #expect(!bridge.presentOptions(presentation, onDismiss: {}))
    }

    private func fixturePublication(kind: Publication.Kind, revision: UInt64, text: String) throws
        -> Publication
    {
        let owner = try #require(AddonID(rawValue: "com.example.options"))
        return try Publication(
            id                        : PublicationID(addonID: owner, instanceID: UUID(), sessionID: UUID()),
            revision                  : revision,
            kind                      : kind,
            content                   : PresentationSet(
                widget                : ContentDocument(
                    root              : .text(text),
                    privacy           : .publicContent,
                    accessibilityLabel: text
                ),
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            ),
            timeline   : nil,
            expiresAt  : Date().addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
    }

    private func optionsPresentation(
        _ publication: Publication,
        origin       : AddonOptionsOrigin,
        title        : String,
        leaseID      : UUID = UUID(),
        actionID     : UUID = UUID(),
        generation   : ConnectionGeneration = ConnectionGeneration()
    ) throws -> AddonOptionsPresentation {
        try AddonOptionsPresentation(
            request                   : AddonOptionsRequest(
                publicationID         : publication.id,
                observedRevision      : publication.revision,
                actionRequestID       : actionID,
                leaseID               : leaseID,
                document              : ContentDocument(
                    root              : .text(title),
                    privacy           : .publicContent,
                    accessibilityLabel: title
                )
            ),
            origin    : origin,
            generation: generation,
            expiresAt : publication.expiresAt
        )
    }
}
