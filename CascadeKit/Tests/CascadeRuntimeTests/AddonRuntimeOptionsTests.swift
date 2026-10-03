//
//  AddonRuntimeOptionsTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite(.serialized)
struct AddonRuntimeOptionsTests {

    @Test
    func cumulativeNegotiationRequiresTheCompleteHost() throws {
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 5,
            contentSchemas: [1]
        )
        let manifest   = try ProtocolVersion(major: 1, minimumMinor: 0)
        let incomplete = try ProtocolNegotiator.negotiate(
            offer                     : offer,
            manifestProtocol          : manifest,
            supportsKeyedStorageFrames: true,
            supportsAssetFrames       : true,
            serviceHost               : true,
            subscriptionHost          : false,
            optionsHost               : true
        )
        let disconnected = try ProtocolNegotiator.negotiate(
            offer                     : offer,
            manifestProtocol          : manifest,
            supportsKeyedStorageFrames: true,
            supportsAssetFrames       : true,
            serviceHost               : true,
            subscriptionHost          : true,
            optionsHost               : false
        )
        let connected = try ProtocolNegotiator.negotiate(
            offer                     : offer,
            manifestProtocol          : manifest,
            supportsKeyedStorageFrames: true,
            supportsAssetFrames       : true,
            serviceHost               : true,
            subscriptionHost          : true,
            optionsHost               : true
        )
        #expect(incomplete.minor == 3)
        #expect(disconnected.minor == 4)
        #expect(!disconnected.supportsOptions)
        #expect(connected.supportsOptions)
    }

    @Test
    func realAcceptedActionOpensDetailAndBackRefundsThenRejectsReplay() async throws {
        let fixture = try await RuntimeOptionsFixture.make()
        do {
            #expect(fixture.connection.publicationConnection.negotiatedProtocol.minor == 5)
            try await fixture.publish()
            let origin = AddonOptionsOrigin(
                publicationID   : fixture.publicationID,
                observedRevision: 1
            )
            let delivery = try await fixture.action(origin: origin)
            let request  = try fixture.optionsRequest(delivery)
            let before   = await fixture.governor.usage(.retainedStateBytes)
            try await fixture.output(operations: [.presentOptions(request)], sequence: 2)
            #expect(fixture.options.presentation?.request == request)
            #expect(
                await fixture.governor.usage(.retainedStateBytes) >= before
                    + RuntimeOptionsState.bytes(request)
            )
            await fixture.runtime.dismissOptions(
                leaseID: request.leaseID,
                owner  : fixture.publicationID.addonID,
                origin : origin
            )
            #expect(fixture.options.presentation == nil)
            #expect(!origin.isValid)
            #expect(
                await fixture.governor.usage(.retainedStateBytes) == before
                    + RuntimeOptionsState.bindingBytes
            )
            await #expect(throws: (any Error).self) {
                try await fixture.output(operations: [.presentOptions(request)], sequence: 3)
            }
        } catch {
            await fixture.tearDown()
            throw error
        }
        await fixture.tearDown()
    }

    @Test
    func aClaimedCapabilityWithoutTheCompleteAssemblyCannotEnableTheFeature() async throws {
        let fixture   = try ActionFixture()
        let installed = try replacing(
            fixture.context().installed,
            features: [
                AddonFeature(
                    id                : "controls",
                    requires          : [],
                    actions           : ["pause"],
                    supportsFullscreen: true
                )
            ]
        )
        let runtime = try await AddonRuntime.make(
            catalog             : [installed],
            environment         : HostEnvironment(
                osVersion       : SemanticVersion(15, 0, 0),
                hostCapabilities: [AddonOptionsRequest.capability: SemanticVersion(1, 0, 0)],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: [],
                protocolVersion : (1, 5)
            ),
            governor: ResourceGovernor(),
            adapter : InvocationMessageAdapter()
        )
        await #expect(throws: (any Error).self) {
            try await runtime.assignPublication(
                owner     : fixture.owner,
                featureID : "controls",
                instanceID: UUID()
            )
        }
        await runtime.stop()
    }

    @Test
    func detailUsesTheExistingDeliveryPathAndStopRevokesItsOrigin() async throws {
        let fixture = try await RuntimeOptionsFixture.make()
        do {
            try await fixture.publish()
            let origin = AddonOptionsOrigin(
                publicationID   : fixture.publicationID,
                observedRevision: 1
            )
            let opening = try await fixture.action(origin: origin)
            let request = try fixture.optionsRequest(opening)
            try await fixture.output(operations: [.presentOptions(request)], sequence: 2)
            #expect(
                try await fixture.runtime.receiveActionCompletion(
                    opening,
                    connection: fixture.connection,
                    outcome   : .completed(payload: Data())
                )
            )
            #expect(fixture.options.presentation != nil)
            let detail = try ActionRequest(
                schemaVersion   : 1,
                requestID       : UUID(),
                publicationID   : fixture.publicationID,
                actionID        : "detail",
                input           : Data([9]),
                deadline        : fixture.clock.now().wall.addingTimeInterval(20),
                observedRevision: 1
            )
            _ = try await fixture.runtime.submitAction(detail, optionsLeaseID: request.leaseID)
            #expect(try await fixture.runtime.pumpReady())
            guard
                case .action(let delivery) = fixture.adapter.payload(fixture.connection.incarnation)
            else {
                Issue.record("Missing detail delivery through the existing action adapter.")
                await fixture.tearDown()
                return
            }
            #expect(delivery.ticket.request == detail)
            await fixture.runtime.stop()
            #expect(fixture.options.presentation == nil)
            #expect(!origin.isValid)
        } catch {
            await fixture.tearDown()
            throw error
        }
        await fixture.tearDown()
    }

    @Test
    func sourceRefreshCannotExceedTheSharedDetailBudget() async throws {
        let fixture = try await RuntimeOptionsFixture.make()
        do {
            try await fixture.publish()
            let origin = AddonOptionsOrigin(
                publicationID   : fixture.publicationID,
                observedRevision: 1
            )
            let delivery = try await fixture.action(origin: origin)
            let initial  = try fixture.optionsRequest(delivery)
            let document = try ContentDocument(
                root: .column(
                    (0..<12).map { _ in try .text(String(repeating: "x", count: 3_000)) }
                ),
                privacy           : .publicContent,
                accessibilityLabel: "Large detail"
            )
            let request = try AddonOptionsRequest(
                publicationID   : fixture.publicationID,
                observedRevision: 1,
                actionRequestID : initial.actionRequestID,
                leaseID         : initial.leaseID,
                document        : document
            )
            try await fixture.output(operations: [.presentOptions(request)], sequence: 2)
            let publication = try Publication(
                id                 : fixture.publicationID,
                revision           : 3,
                kind               : .widget,
                content            : PresentationSet(
                    widget         : document,
                    compactLeading : nil,
                    compactTrailing: nil,
                    minimal        : nil,
                    expanded       : nil
                ),
                timeline   : nil,
                expiresAt  : fixture.clock.now().wall.addingTimeInterval(100),
                stalePolicy: .remove
            )
            await #expect(throws: (any Error).self) {
                try await fixture.output(publications: [publication], operations: [], sequence: 3)
            }
            #expect(
                await fixture.runtime.snapshot(at: fixture.clock.now().wall).publications.first?
                    .revision == 1
            )
        } catch {
            await fixture.tearDown()
            throw error
        }
        await fixture.tearDown()
    }

    @Test
    func revisionDisablesDetailActionsAndOriginalExpiryRevokesLease() async throws {
        let fixture = try await RuntimeOptionsFixture.make()
        do {
            try await fixture.publish()
            let origin = AddonOptionsOrigin(
                publicationID   : fixture.publicationID,
                observedRevision: 1
            )
            let delivery = try await fixture.action(origin: origin)
            let request  = try fixture.optionsRequest(delivery)
            try await fixture.output(operations: [.presentOptions(request)], sequence: 2)
            fixture.clock.advance(10)
            try await fixture.publish(revision: 3, lifetime: 200)
            #expect(fixture.options.invalidatedLeases.contains(request.leaseID))
            let action = try ActionRequest(
                schemaVersion   : 1,
                requestID       : UUID(),
                publicationID   : fixture.publicationID,
                actionID        : "detail",
                input           : Data([9]),
                deadline        : fixture.clock.now().wall.addingTimeInterval(20),
                observedRevision: 1
            )
            await #expect(throws: (any Error).self) {
                try await fixture.runtime.submitAction(action, optionsLeaseID: request.leaseID)
            }
            let refresh = try AddonOptionsRequest(
                publicationID   : fixture.publicationID,
                observedRevision: 3,
                actionRequestID : request.actionRequestID,
                leaseID         : request.leaseID,
                document        : request.document
            )
            try await fixture.output(operations: [.presentOptions(refresh)], sequence: 4)
            #expect(fixture.options.presentation?.expiresAt == Date(timeIntervalSince1970: 1_100))
            fixture.clock.advance(90)
            _ = try await fixture.runtime.serviceDeadlines()
            #expect(fixture.options.presentation == nil)
            #expect(!origin.isValid)
        } catch {
            await fixture.tearDown()
            throw error
        }
        await fixture.tearDown()
    }
}
