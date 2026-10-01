//
//  ArchiveFacadeFixture.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// ArchiveFacadeFixture composes real storage and runtime while exposing no raw archive capability.
struct ArchiveFacadeFixture: Sendable {
    let installed  : InstalledAddon
    let governor   : ResourceGovernor
    let adapter    : RecordingRuntimeAdapter
    let clock      : MutableRuntimeClock
    let coordinator: AddonStorageCoordinator
    let root       : URL
    let archiveRoot: URL
    let wall       : Date
    var owner: AddonID { installed.manifest.id }
    var ownerRoot: URL {
        archiveRoot.appendingPathComponent(KeyedStorageRecord.hex(
            KeyedStorageRecord.namespaceDigest(installed.verifiedIdentity)
        ))
    }

    /// make establishes the real global storage barrier while leaving every archive unopened.
    static func make(
        observer     : any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver(),
        otherIdentity: VerifiedAddonIdentity? = nil
    ) async throws -> Self {
        let base = try ActionFixture()
        let installed = try base.context().installed
        let governor = ResourceGovernor()
        let root = URL(fileURLWithPath: "/private/tmp/cascade-archive-facade-\(UUID())")
        let checkpointRoot = root.appendingPathComponent("checkpoints")
        let keyedRoot = root.appendingPathComponent("keyed")
        let archiveRoot = root.appendingPathComponent("archives")
        for directory in [root, checkpointRoot, keyedRoot, archiveRoot] {
            try FileManager.default.createDirectory(
                at                         : directory,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
        }
        var registrations = [StateRegistration(
            identity            : installed.verifiedIdentity,
            maximumSchemaVersion: 1
        )]
        if let otherIdentity {
            registrations.append(StateRegistration(
                identity            : otherIdentity,
                maximumSchemaVersion: 1
            ))
        }
        let coordinator = try await AddonStorageCoordinator.make(
            checkpointRoot : checkpointRoot,
            keyedRoot      : keyedRoot,
            archiveRoot    : archiveRoot,
            registrations  : registrations,
            governor       : governor,
            archiveObserver: observer
        )
        try await coordinator.start()
        return Self(
            installed  : installed,
            governor   : governor,
            adapter    : RecordingRuntimeAdapter(),
            clock      : MutableRuntimeClock(instant: RuntimeInstant(
                wall     : base.wall,
                monotonic: .zero
            )),
            coordinator: coordinator,
            root       : root,
            archiveRoot: archiveRoot,
            wall       : base.wall
        )
    }

    /// runtime creates an independently fresh host lifecycle on the selected real governor.
    func runtime(
        governor : ResourceGovernor? = nil,
        access   : (any RuntimeResourceAccess)? = nil,
        installed: InstalledAddon? = nil
    ) async throws -> AddonRuntime {
        let selectedGovernor = governor ?? self.governor
        let selectedInstalled = installed ?? self.installed
        return try await AddonRuntime.make(
            catalog    : [selectedInstalled],
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [selectedInstalled.manifest.id: []],
                explicitBindings: []
            ),
            governor              : selectedGovernor,
            resourceAccess        : access ?? selectedGovernor,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock
        )
    }

    /// publish admits one real full-timeline publication and completes its simulated transport lifetime.
    func publish(_ runtime: AddonRuntime) async throws -> PublicationID {
        let id = try await runtime.assignPublication(
            owner     : owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        func presentation(_ text: String) throws -> PresentationSet {
            try PresentationSet(
                widget: ContentDocument(
                    root              : .text(text),
                    privacy           : .publicContent,
                    accessibilityLabel: text,
                    assetIDs          : []
                ),
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            )
        }
        let publication = try Publication(
            id         : id,
            revision   : 0,
            kind       : .widget,
            content    : nil,
            timeline   : [
                ScheduledEntry(
                    date   : wall,
                    content: presentation("Now")
                ),
                ScheduledEntry(
                    date   : wall.addingTimeInterval(20),
                    content: presentation("Future")
                )
            ],
            expiresAt  : wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : [publication],
                operations   : [],
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            sequence  : 1
        )
        await runtime.observeExit(connection.incarnation)
        return id
    }

    /// publishSharedImages uses actual decode/share admission and retains no native output in the fixture.
    func publishSharedImages(
        _ runtime: AddonRuntime,
        partition: AssetPrivacyPartition
    ) async throws -> (ids: [PublicationID], aliases: [String]) {
        var ids: [PublicationID] = []
        for feature in ["controls", "other"] {
            ids.append(try await runtime.assignPublication(
                owner                : owner,
                featureID            : feature,
                instanceID           : UUID(),
                assetPrivacyPartition: partition
            ))
        }
        let launch = try await runtime.requestLaunch(owner: owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let image = try await runtime.importAsset(
            encoded      : facadePNG(),
            publicationID: ids[0],
            connection   : connection
        )
        let shared = try await runtime.shareAsset(
            assetID   : image.assetID,
            from      : ids[0],
            to        : ids[1],
            connection: connection
        )
        let aliases = [image.assetID, shared.assetID]
        let publications = try ids.indices.map { index in
            func presentation(_ text: String) throws -> PresentationSet {
                let document = try ContentDocument(
                    root: .column([
                        .text(text),
                        ContentNode(
                            kind              : .image,
                            text              : nil,
                            assetID           : aliases[index],
                            value             : nil,
                            deadline          : nil,
                            actionID          : nil,
                            children          : nil,
                            accessibilityLabel: "Red pixel"
                        )
                    ]),
                    privacy           : .sensitive,
                    accessibilityLabel: "Shared image",
                    assetIDs          : [aliases[index]]
                )
                return try PresentationSet(
                    widget         : index == 0 ? nil : document,
                    compactLeading : document,
                    compactTrailing: document,
                    minimal        : document,
                    expanded       : document
                )
            }
            return try Publication(
                id         : ids[index],
                revision   : 0,
                kind       : index == 0 ? .activity : .widget,
                content    : nil,
                timeline   : [
                    ScheduledEntry(
                        date   : wall,
                        content: presentation("Now")
                    ),
                    ScheduledEntry(
                        date   : wall.addingTimeInterval(20),
                        content: presentation("Future")
                    )
                ],
                expiresAt  : wall.addingTimeInterval(8 * 3_600),
                stalePolicy: .retainMarked
            )
        }
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : [],
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            sequence  : 1
        )
        await runtime.observeExit(connection.incarnation)
        return (ids, aliases)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}
