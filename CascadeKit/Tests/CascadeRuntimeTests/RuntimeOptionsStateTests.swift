//
//  RuntimeOptionsStateTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct RuntimeOptionsStateTests {

    @Test
    func openingRequiresCapabilityFeatureAndExactAcceptedAction() throws {
        let fixture = try ActionFixture()
        let context = try optionsContext(fixture)
        let action  = try fixture.request()
        let origin  = AddonOptionsOrigin(publicationID: fixture.publicationID, observedRevision: 1)
        let request = try optionsRequest(action)
        var state   = RuntimeOptionsState()
        #expect(throws: (any Error).self) {
            try state.prepare(
                request,
                context        : context,
                action         : action,
                origin         : origin,
                generation     : ConnectionGeneration(),
                supportsOptions: false,
                at             : fixture.wall
            )
        }
        #expect(throws: (any Error).self) {
            try state.prepare(
                request,
                context        : fixture.context(),
                action         : action,
                origin         : origin,
                generation     : ConnectionGeneration(),
                supportsOptions: true,
                at             : fixture.wall
            )
        }
        #expect(throws: (any Error).self) {
            try state.prepare(
                request,
                context        : context,
                action         : fixture.request(),
                origin         : origin,
                generation     : ConnectionGeneration(),
                supportsOptions: true,
                at             : fixture.wall
            )
        }
        let accepted = try state.prepare(
            request,
            context        : context,
            action         : action,
            origin         : origin,
            generation     : ConnectionGeneration(),
            supportsOptions: true,
            at             : fixture.wall
        )
        state.commit(accepted)
        #expect(state.retainedBytes > 0)
        #expect(state.active?.request.leaseID == request.leaseID)
    }

    @Test
    func refreshCannotExtendLifetimeOrReopenAfterBack() throws {
        let fixture    = try ActionFixture()
        let context    = try optionsContext(fixture)
        let action     = try fixture.request()
        let origin     = AddonOptionsOrigin(publicationID: fixture.publicationID, observedRevision: 1)
        let generation = ConnectionGeneration()
        let request    = try optionsRequest(action)
        var state      = RuntimeOptionsState()
        state.commit(
            try state.prepare(
                request,
                context        : context,
                action         : action,
                origin         : origin,
                generation     : generation,
                supportsOptions: true,
                at             : fixture.wall
            )
        )
        let refreshed = try state.prepare(
            request,
            context        : optionsContext(fixture, revision: 1, lifetime: 200),
            action         : nil,
            origin         : nil,
            generation     : generation,
            supportsOptions: true,
            at             : fixture.wall.addingTimeInterval(21)
        )
        #expect(refreshed.expiresAt == fixture.wall.addingTimeInterval(100))
        state.commit(refreshed)
        let staleDismissal = state.dismiss(UUID())
        let dismissal      = state.dismiss(request.leaseID)
        #expect(!staleDismissal)
        #expect(dismissal)
        #expect(!origin.isValid)
        #expect(state.retainedBytes == RuntimeOptionsState.bindingBytes)
        #expect(throws: (any Error).self) {
            try state.prepare(
                request,
                context        : context,
                action         : action,
                origin         : origin,
                generation     : generation,
                supportsOptions: true,
                at             : fixture.wall
            )
        }
        let freshAction = try fixture.request()
        let reused      = try AddonOptionsRequest(
            publicationID   : fixture.publicationID,
            observedRevision: 1,
            actionRequestID : freshAction.requestID,
            leaseID         : request.leaseID,
            document        : request.document
        )
        #expect(throws: (any Error).self) {
            try state.prepare(
                reused,
                context             : context,
                action              : freshAction,
                origin              : AddonOptionsOrigin(
                    publicationID   : fixture.publicationID,
                    observedRevision: 1
                ),
                generation     : generation,
                supportsOptions: true,
                at             : fixture.wall
            )
        }
    }

    @Test
    func retiredIDsAreBoundedPaidAndClearedOnlyWithTheirGeneration() throws {
        let fixture    = try ActionFixture()
        let context    = try optionsContext(fixture)
        let generation = ConnectionGeneration()
        var state      = RuntimeOptionsState()
        for _ in 0..<RuntimeOptionsState.maximumBindings {
            let action  = try fixture.request()
            let request = try optionsRequest(action)
            let origin  = AddonOptionsOrigin(
                publicationID   : fixture.publicationID,
                observedRevision: 1
            )
            state.commit(
                try state.prepare(
                    request,
                    context        : context,
                    action         : action,
                    origin         : origin,
                    generation     : generation,
                    supportsOptions: true,
                    at             : fixture.wall
                )
            )
            state.dismiss(request.leaseID)
        }
        #expect(
            state.retainedBytes == RuntimeOptionsState.maximumBindings
                * RuntimeOptionsState.bindingBytes
        )
        let nextAction = try fixture.request()
        let next       = try optionsRequest(nextAction)
        let origin     = AddonOptionsOrigin(publicationID: fixture.publicationID, observedRevision: 1)
        #expect(throws: (any Error).self) {
            try state.prepare(
                next,
                context        : context,
                action         : nextAction,
                origin         : origin,
                generation     : generation,
                supportsOptions: true,
                at             : fixture.wall
            )
        }
        state.invalidateGeneration(owner: fixture.owner, generation: ConnectionGeneration())
        #expect(state.retainedBytes > 0)
        state.invalidateGeneration(owner: fixture.owner, generation: generation)
        #expect(state.retainedBytes == 0)
        _ = try state.prepare(
            next,
            context        : context,
            action         : nextAction,
            origin         : origin,
            generation     : ConnectionGeneration(),
            supportsOptions: true,
            at             : fixture.wall
        )
    }

    @Test
    func undeclaredDetailActionAndForgedSourceAreRejected() throws {
        let fixture = try ActionFixture()
        let context = try optionsContext(fixture)
        let action  = try fixture.request()
        let origin  = AddonOptionsOrigin(publicationID: fixture.publicationID, observedRevision: 1)
        let state   = RuntimeOptionsState()
        #expect(throws: (any Error).self) {
            try state.prepare(
                optionsRequest(action, actionID: "delete"),
                context        : context,
                action         : action,
                origin         : origin,
                generation     : ConnectionGeneration(),
                supportsOptions: true,
                at             : fixture.wall
            )
        }
        let other = AddonOptionsOrigin(
            publicationID   : try ActionFixture().publicationID,
            observedRevision: 1
        )
        #expect(throws: (any Error).self) {
            try state.prepare(
                optionsRequest(action),
                context        : context,
                action         : action,
                origin         : other,
                generation     : ConnectionGeneration(),
                supportsOptions: true,
                at             : fixture.wall
            )
        }
    }

    @Test
    func detailSharesTheAggregatePresentationBudgetAndCannotReplayOpening() throws {
        let fixture    = try ActionFixture()
        let base       = try optionsContext(fixture)
        let action     = try fixture.request()
        let origin     = AddonOptionsOrigin(publicationID: fixture.publicationID, observedRevision: 1)
        let request    = try optionsRequest(action)
        let generation = ConnectionGeneration()
        var state      = RuntimeOptionsState()
        state.commit(
            try state.prepare(
                request,
                context        : base,
                action         : action,
                origin         : origin,
                generation     : generation,
                supportsOptions: true,
                at             : fixture.wall
            )
        )
        #expect(throws: (any Error).self) {
            try state.prepare(
                optionsRequest(action),
                context        : base,
                action         : action,
                origin         : origin,
                generation     : generation,
                supportsOptions: true,
                at             : fixture.wall
            )
        }
        let largeSource = try ContentDocument(
            root: .column(
                [.action(ActionDescriptor(id: "pause", label: "Pause", payload: Data([7])))]
                    + (0..<10).map { _ in try .text(String(repeating: "x", count: 3_000)) }
            ),
            privacy           : .publicContent,
            accessibilityLabel: "Large source"
        )
        let largeDetail = try ContentDocument(
            root              : .column((0..<12).map { _ in try .text(String(repeating: "y", count: 3_000)) }),
            privacy           : .publicContent,
            accessibilityLabel: "Large detail"
        )
        let publication = try Publication(
            id                 : fixture.publicationID,
            revision           : 1,
            kind               : .widget,
            content            : PresentationSet(
                widget         : largeSource,
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            ),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        let context = ActionAuthorizer.Context(
            installed  : base.installed,
            resolution : base.resolution,
            featureID  : base.featureID,
            publication: publication,
            eligibility: .available
        )
        let largeRequest = try AddonOptionsRequest(
            publicationID   : action.publicationID,
            observedRevision: 1,
            actionRequestID : action.requestID,
            leaseID         : request.leaseID,
            document        : largeDetail
        )
        #expect(throws: (any Error).self) {
            try state.prepare(
                largeRequest,
                context        : context,
                action         : nil,
                origin         : nil,
                generation     : generation,
                supportsOptions: true,
                at             : fixture.wall
            )
        }
    }

    @Test
    func sourceRevisionInvalidatesControlsButKeepsSelectedLease() throws {
        let fixture    = try ActionFixture()
        let action     = try fixture.request()
        let origin     = AddonOptionsOrigin(publicationID: fixture.publicationID, observedRevision: 1)
        let generation = ConnectionGeneration()
        let request    = try optionsRequest(action)
        var state      = RuntimeOptionsState()
        state.commit(
            try state.prepare(
                request,
                context        : optionsContext(fixture),
                action         : action,
                origin         : origin,
                generation     : generation,
                supportsOptions: true,
                at             : fixture.wall
            )
        )
        #expect(
            !state.controlsAvailable(
                context   : try optionsContext(fixture, revision: 2),
                generation: generation,
                at        : fixture.wall
            )
        )
        #expect(state.active?.request.leaseID == request.leaseID)
        let detailAction = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : fixture.publicationID,
            actionID        : "detail",
            input           : Data([9]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        let leasedContext = try state.actionContext(
            context   : optionsContext(fixture),
            leaseID   : request.leaseID,
            generation: generation,
            at        : fixture.wall
        )
        try ActionAuthorizer.validate(detailAction, context: leasedContext, at: fixture.wall)
        #expect(throws: (any Error).self) {
            try state.actionContext(
                context   : optionsContext(fixture, revision: 2),
                leaseID   : request.leaseID,
                generation: generation,
                at        : fixture.wall
            )
        }
        #expect(throws: (any Error).self) {
            try state.prepare(
                request,
                context        : optionsContext(fixture),
                action         : nil,
                origin         : nil,
                generation     : ConnectionGeneration(),
                supportsOptions: true,
                at             : fixture.wall
            )
        }
    }

    private func optionsRequest(_ action: ActionRequest, actionID: String = "detail") throws
        -> AddonOptionsRequest
    {
        try AddonOptionsRequest(
            publicationID         : action.publicationID,
            observedRevision      : action.observedRevision,
            actionRequestID       : action.requestID,
            leaseID               : UUID(),
            document              : ContentDocument(
                root              : .action(ActionDescriptor(id: actionID, label: "Detail", payload: Data([9]))),
                privacy           : .publicContent,
                accessibilityLabel: "Detail"
            )
        )
    }

    private func optionsContext(
        _ fixture: ActionFixture,
        revision : UInt64 = 1,
        lifetime : TimeInterval = 100
    ) throws -> ActionAuthorizer.Context {
        let base      = try fixture.context(revision: revision)
        let installed = try replacing(
            base.installed,
            features: [
                AddonFeature(
                    id                : "controls",
                    requires          : [],
                    actions           : ["pause", "detail"],
                    supportsFullscreen: true
                )
            ]
        )
        let publication = try #require(base.publication)
        return try ActionAuthorizer.Context(
            installed      : installed,
            resolution     : base.resolution,
            featureID      : base.featureID,
            publication    : Publication(
                id         : publication.id,
                revision   : publication.revision,
                kind       : publication.kind,
                content    : publication.content,
                timeline   : nil,
                expiresAt  : fixture.wall.addingTimeInterval(lifetime),
                stalePolicy: publication.stalePolicy
            ),
            eligibility: .available
        )
    }
}
