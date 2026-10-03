//
//  RuntimeOptionsFixture.swift
//  CascadeKit
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// RuntimeOptionsFixture drives the real cumulative host assembly and raw
/// publication slot. Temporary storage and the deterministic adapter are test owned.
struct RuntimeOptionsFixture: Sendable {

    let root         : URL
    let runtime      : AddonRuntime
    let governor     : ResourceGovernor
    let storage      : AddonStorageCoordinator
    let adapter      : InvocationMessageAdapter
    let options      : RecordingOptionsAdapter
    let connection   : RuntimeConnection
    let clock        : InvocationMessageClock
    let publicationID: PublicationID

    static func make() async throws -> Self {
        let root       = URL(fileURLWithPath: "/private/tmp/cascade-runtime-options-\(UUID())")
        let checkpoint = root.appendingPathComponent("checkpoint")
        let keyed      = root.appendingPathComponent("keyed")
        let archive    = root.appendingPathComponent("archive")
        for directory in [root, checkpoint, keyed, archive] {
            try FileManager.default.createDirectory(
                at                         : directory,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
        }
        let action    = try ActionFixture()
        let installed = try replacing(
            action.context().installed,
            features: [
                AddonFeature(
                    id                : "controls",
                    requires          : [],
                    actions           : ["pause", "detail"],
                    supportsFullscreen: true
                )
            ]
        )
        let governor = ResourceGovernor()
        let adapter  = InvocationMessageAdapter()
        let options  = RecordingOptionsAdapter()
        let clock    = InvocationMessageClock()
        let storage  = try await AddonStorageCoordinator.make(
            checkpointRoot: checkpoint,
            keyedRoot     : keyed,
            archiveRoot   : archive,
            registrations : [
                StateRegistration(identity: installed.verifiedIdentity, maximumSchemaVersion: 1)
            ],
            governor: governor
        )
        try await storage.start()
        let runtime = try await AddonRuntime.make(
            catalog             : [installed],
            environment         : HostEnvironment(
                osVersion       : SemanticVersion(15, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [action.owner: []],
                explicitBindings: [],
                protocolVersion : (1, 5)
            ),
            governor          : governor,
            adapter           : adapter,
            clock             : clock,
            storageCoordinator: storage,
            optionsAdapter    : options
        )
        let publicationID = try await runtime.assignPublication(
            owner     : action.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch     = try await runtime.requestLaunch(owner: action.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: 5, contentSchemas: [1])
        )
        return Self(
            root         : root,
            runtime      : runtime,
            governor     : governor,
            storage      : storage,
            adapter      : adapter,
            options      : options,
            connection   : connection,
            clock        : clock,
            publicationID: publicationID
        )
    }

    func publish(revision: UInt64 = 1, lifetime: TimeInterval = 100) async throws {
        let document = try ContentDocument(
            root              : .action(ActionDescriptor(id: "pause", label: "Open", payload: Data([7]))),
            privacy           : .publicContent,
            accessibilityLabel: "Controls"
        )
        let publication = try Publication(
            id                 : publicationID,
            revision           : revision,
            kind               : .widget,
            content            : PresentationSet(
                widget         : document,
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            ),
            timeline   : nil,
            expiresAt  : clock.now().wall.addingTimeInterval(lifetime),
            stalePolicy: .remove
        )
        try await output(publications: [publication], operations: [], sequence: revision)
    }

    func action(origin: AddonOptionsOrigin) async throws -> ActionDispatcher.Delivery {
        options.capture(origin)
        let request = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : clock.now().wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await runtime.submitAction(request, origin: origin)
        #expect(try await runtime.pumpReady())
        guard case .action(let delivery) = adapter.payload(connection.incarnation) else {
            throw AddonFailure(code: .outcomeUnknown, reason: "Missing real action delivery.")
        }
        #expect(try await runtime.receiveAcknowledgment(delivery, connection: connection))
        return delivery
    }

    func optionsRequest(_ delivery: ActionDispatcher.Delivery, leaseID: UUID = UUID()) throws
        -> AddonOptionsRequest
    {
        let document = try ContentDocument(
            root              : .action(ActionDescriptor(id: "detail", label: "Apply", payload: Data([9]))),
            privacy           : .publicContent,
            accessibilityLabel: "Options"
        )
        guard
            case .presentOptions(let request) = try AddonOptions.present(
                for     : delivery.ticket.request,
                document: document,
                leaseID : leaseID
            )
        else {
            throw AddonFailure(code: .invalidPayload, reason: "SDK did not produce options.")
        }
        return request
    }

    func output(publications: [Publication] = [], operations: [OperationRequest], sequence: UInt64)
        async throws
    {
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications : publications,
            operations   : operations,
            completion   : nil,
            checkpoint   : nil
        )
        let staged = try adapter.stagePublication(output, connection: connection)
        let handle = try #require(staged)
        _          = try await runtime.receivePublicationOutput(
            handle,
            connection: connection,
            sequence  : sequence
        )
    }

    func tearDown() async {
        await runtime.stop()
        await runtime.observeExit(connection.incarnation)
        _ = try? await storage.close()
        try? FileManager.default.removeItem(at: root)
    }
}
