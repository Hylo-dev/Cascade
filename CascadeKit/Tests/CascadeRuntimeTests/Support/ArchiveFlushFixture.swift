//
//  ArchiveFlushFixture.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

/// ArchiveFlushFixture reuses validated ActionFixture contracts and real runtime/governor/storage actors.
/// Only the existing recording adapter substitutes for provider transport; no native provider launches.
struct ArchiveFlushFixture: Sendable {
    let installed  : [InstalledAddon]
    let governor   : ResourceGovernor
    let adapter    : RecordingRuntimeAdapter
    let clock      : MutableRuntimeClock
    let runtime    : AddonRuntime
    let coordinator: AddonStorageCoordinator
    let root       : URL
    let archiveRoot: URL
    let wall       : Date
    let ids        : [PublicationID]
    let connections: [RuntimeConnection]
    var owners     : [AddonID] { installed.map(\.manifest.id) }

    /// make establishes the real storage barrier and attached test transport for each bounded owner.
    static func make(
        count        : Int = 1,
        observer     : any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver(),
        governor     : ResourceGovernor = ResourceGovernor(),
        access       : (any RuntimeResourceAccess)? = nil,
        storageAccess: (any RuntimeResourceAccess)? = nil
    ) async throws -> Self {
        let bases     = try (0..<count).map { try ActionFixture(ownerName: "com.example.flush.owner\($0)") }
        let installed = try bases.map { try $0.context().installed }
        let wall      = try #require(bases.first).wall
        let adapter   = RecordingRuntimeAdapter()
        let clock     = MutableRuntimeClock(
            instant: RuntimeInstant(
                wall     : wall,
                monotonic: .zero
            )
        )
        let root           = URL(fileURLWithPath: "/private/tmp/cascade-archive-flush-\(UUID())")
        let checkpointRoot = root.appendingPathComponent("checkpoints")
        let keyedRoot      = root.appendingPathComponent("keyed")
        let archiveRoot    = root.appendingPathComponent("archives")
        for directory in [root, checkpointRoot, keyedRoot, archiveRoot] {
            try FileManager.default.createDirectory(
                at                         : directory,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
        }
        let coordinator = try await AddonStorageCoordinator.make(
            checkpointRoot: checkpointRoot,
            keyedRoot     : keyedRoot,
            archiveRoot   : archiveRoot,
            registrations : installed.map {
                StateRegistration(
                    identity            : $0.verifiedIdentity,
                    maximumSchemaVersion: 1
                )
            },
            governor       : governor,
            resourceAccess : storageAccess,
            archiveObserver: observer
        )
        try await coordinator.start()
        let runtime = try await makeRuntime(
            installed: installed,
            governor : governor,
            adapter  : adapter,
            clock    : clock,
            access   : access
        )
        var ids        : [PublicationID] = []
        var connections: [RuntimeConnection] = []
        for addon in installed {
            ids.append(
                try await runtime.assignPublication(
                    owner     : addon.manifest.id,
                    featureID : "controls",
                    instanceID: UUID()
                )
            )
            let launch = try await runtime.requestLaunch(owner: addon.manifest.id)
            connections.append(
                try await runtime.attach(
                    launchID: launch,
                    offer   : ProtocolOffer(
                        major         : 1,
                        minimumMinor  : 0,
                        maximumMinor  : 0,
                        contentSchemas: [1]
                    )
                )
            )
        }
        return Self(
            installed  : installed,
            governor   : governor,
            adapter    : adapter,
            clock      : clock,
            runtime    : runtime,
            coordinator: coordinator,
            root       : root,
            archiveRoot: archiveRoot,
            wall       : wall,
            ids        : ids,
            connections: connections
        )
    }

    /// makeRuntime creates a fresh host lifecycle over the same real resources without an archive capability.
    private static func makeRuntime(
        installed: [InstalledAddon],
        governor : ResourceGovernor,
        adapter  : RecordingRuntimeAdapter,
        clock    : MutableRuntimeClock,
        access   : (any RuntimeResourceAccess)? = nil
    ) async throws -> AddonRuntime {
        try await AddonRuntime.make(
            catalog    : installed,
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : Dictionary(uniqueKeysWithValues: installed.map { ($0.manifest.id, []) }),
                explicitBindings: []
            ),
            governor              : governor,
            resourceAccess        : access ?? governor,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock
        )
    }

    func freshRuntime() async throws -> AddonRuntime {
        try await Self.makeRuntime(
            installed: installed,
            governor : governor,
            adapter  : adapter,
            clock    : clock
        )
    }

    /// isCommit checks the scalar outcome without constructing a backend status fixture.
    func isCommit(
        _ result  : AddonStorageCoordinator.ArchiveFlushResult,
        ownerIndex: Int,
        revision  : UInt64
    ) -> Bool {
        guard
            case .committed(
                let owner,
                let outcome
            ) = result
        else { return false }
        return owner == owners[ownerIndex] && outcome.revision == revision
    }

    func state(index: Int = 0) async -> AddonRuntime.ArchiveFlushState {
        await runtime.archiveFlushState(identity: installed[index].verifiedIdentity)
    }

    /// publication provides valid family content and an optional complete future timeline.
    func publication(
        index   : Int = 0,
        revision: UInt64 = 0,
        kind    : Publication.Kind = .widget,
        expires : TimeInterval = 100,
        timeline: Bool = false
    ) throws -> Publication {
        /// presentation keeps the fixture documents valid for the selected publication family.
        func presentation(_ text: String) throws -> PresentationSet {
            let document = try ContentDocument(
                root              : .text(text),
                privacy           : .publicContent,
                accessibilityLabel: text,
                assetIDs          : []
            )
            return try PresentationSet(
                widget         : document,
                compactLeading : document,
                compactTrailing: document,
                minimal        : document,
                expanded       : kind == .notice ? nil : document
            )
        }
        return try Publication(
            id      : ids[index],
            revision: revision,
            kind    : kind,
            content : timeline ? nil : presentation("Revision \(revision)"),
            timeline: timeline
                ? [
                    ScheduledEntry(
                        date   : wall,
                        content: presentation("Now")
                    ),
                    ScheduledEntry(
                        date   : wall.addingTimeInterval(20),
                        content: presentation("Future")
                    ),
                ] : nil,
            expiresAt  : wall.addingTimeInterval(expires),
            stalePolicy: .retainMarked
        )
    }

    /// send uses the real bounded provider-output admission path.
    func send(
        index       : Int = 0,
        publications: [Publication] = [],
        operations  : [OperationRequest] = [],
        sequence    : UInt64
    ) async throws {
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : operations,
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connections[index],
            sequence  : sequence
        )
    }

    func stop() async {
        for connection in connections { await runtime.observeExit(connection.incarnation) }
        await runtime.stop()
        _ = try? await coordinator.close()
    }
    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}
