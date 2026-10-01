//
//  ArchiveRestoreFixture.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// ArchiveRestoreFixture uses real shared-governor archives and fresh runtimes with fake transport only.
struct ArchiveRestoreFixture: Sendable {

    let installed: InstalledAddon
    let governor : ResourceGovernor
    let adapter  : RecordingRuntimeAdapter
    let clock    : MutableRuntimeClock
    let archive  : SwiftDataArchive
    let root     : URL
    let wall     : Date

    var owner: AddonID { installed.manifest.id }

    static func make() async throws -> Self {
        let base      = try ActionFixture()
        let installed = try base.context().installed
        let governor  = ResourceGovernor()
        let root      = URL(fileURLWithPath: "/private/tmp/cascade-runtime-restore-\(UUID())")

        try FileManager.default.createDirectory(
            at                         : root,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )

        let archive = try await SwiftDataArchive.make(
            identity: installed.verifiedIdentity,
            root    : root,
            governor: governor
        )
        _ = try await archive.start()

        return Self(
            installed: installed,
            governor : governor,
            adapter  : RecordingRuntimeAdapter(),
            clock    : MutableRuntimeClock(instant: RuntimeInstant(wall: base.wall, monotonic: .zero)),
            archive  : archive,
            root     : root,
            wall     : base.wall
        )
    }

    func runtime(
        access   : (any RuntimeResourceAccess)? = nil,
        adapter  : RecordingRuntimeAdapter? = nil,
        installed: InstalledAddon? = nil
    ) async throws -> AddonRuntime {
        try await AddonRuntime.make(
            catalog               : [installed ?? self.installed],
            environment           : HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [owner: []],
                explicitBindings: []
            ),
            governor              : governor,
            resourceAccess        : access ?? governor,
            serviceDecisionFactory: { $0 },
            adapter               : adapter ?? self.adapter,
            clock                 : clock
        )
    }

    func connect(_ runtime: AddonRuntime) async throws -> RuntimeConnection {
        let launch = try await runtime.requestLaunch(owner: owner)

        return try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1, 2]
            )
        )
    }

    func publication(
        id    : PublicationID,
        future: Bool = false
    ) throws -> Publication {
        func presentation(_ text: String) throws -> PresentationSet {
            try PresentationSet(
                widget         : ContentDocument(
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

        return try Publication(
            id         : id,
            revision   : 0,
            kind       : .widget,
            content    : future ? nil : presentation("Current"),
            timeline   : future ? [
                ScheduledEntry(date: wall, content: presentation("First")),
                ScheduledEntry(date: wall.addingTimeInterval(20), content: presentation("Future")),
            ] : nil,
            expiresAt  : wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
    }

    func publish(
        _ runtime   : AddonRuntime,
        connection  : RuntimeConnection,
        publications: [Publication],
        sequence    : UInt64 = 1,
        ends        : [PublicationID] = []
    ) async throws {
        _ = try await receivePublicationOutput(
            runtime   : runtime,
            adapter   : adapter,
            output    : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : ends.map { .endPublication($0) },
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            sequence  : sequence
        )
    }

    func write(
        records: [RuntimeArchiveEnvelope.Record],
        blobs  : [RuntimeArchiveEnvelope.Blob] = []
    ) async throws {
        try await governor.withAssetDecodeReservation(
            bytes: RuntimeArchiveEnvelope.retentionReservationBytes() + 16 * 1_024 * 1_024,
            owner: owner
        ) {
            let envelope = RuntimeArchiveEnvelope(
                publisher: Data(installed.verifiedIdentity.publisher.utf8),
                addon    : Data(owner.rawValue.utf8),
                digest   : Data(installed.digest.utf8),
                records  : records,
                blobs    : blobs
            )
            _ = try await archive.save(
                SwiftDataArchiveGeneration(
                    schemaVersion : 1,
                    revision      : 1,
                    verifiedDigest: installed.digest,
                    payload       : envelope.encode()
                ),
                replacing: nil
            )
        }
    }

    func newID() -> PublicationID {
        PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
    }

    func record(
        _ publication: Publication,
        blob         : UUID? = nil,
        partition    : UUID? = nil,
        feature      : String = "controls",
        revision     : UInt64? = nil,
        deadline     : Date? = nil
    ) throws -> RuntimeArchiveEnvelope.Record {
        try RuntimeArchiveEnvelope.Record(
            instance       : RuntimeArchiveEnvelope.uuidBytes(publication.id.instanceID),
            session        : RuntimeArchiveEnvelope.uuidBytes(publication.id.sessionID),
            feature        : Data(feature.utf8),
            partition      : partition.map(RuntimeArchiveEnvelope.uuidBytes),
            revision       : revision ?? publication.revision,
            kind           : publication.kind,
            sessionDeadline: deadline ?? wall.addingTimeInterval(8 * 3_600),
            publication    : RuntimeArchivePublicationCodec.encode(publication),
            aliases        : blob.map {
                [RuntimeArchiveEnvelope.Alias(name: Data("old".utf8), blob: RuntimeArchiveEnvelope.uuidBytes($0))]
            } ?? []
        )
    }

    func blob(
        _ id     : UUID,
        partition: UUID? = nil
    ) -> RuntimeArchiveEnvelope.Blob {
        RuntimeArchiveEnvelope.Blob(
            id       : RuntimeArchiveEnvelope.uuidBytes(id),
            partition: partition.map(RuntimeArchiveEnvelope.uuidBytes),
            width    : 1,
            height   : 1,
            pixels   : Data([255, 0, 0, 255])
        )
    }

    func imagePublication(
        id  : PublicationID,
        rich: Bool = false
    ) throws -> Publication {
        let image = try ContentNode(
            kind              : .image,
            text              : nil,
            assetID           : "old",
            value             : nil,
            deadline          : nil,
            actionID          : nil,
            children          : nil,
            accessibilityLabel: "Red pixel"
        )
        let action = try ContentNode(
            kind         : .action,
            text         : "Pause",
            assetID      : nil,
            value        : nil,
            deadline     : nil,
            actionID     : "pause",
            children     : nil,
            actionPayload: Data([7, 9])
        )
        let clock = try ContentNode(
            kind       : .clock,
            text       : nil,
            assetID    : nil,
            value      : nil,
            deadline   : nil,
            actionID   : nil,
            children   : nil,
            clockFormat: .hourMinuteSecond
        )
        let document = try ContentDocument(
            schemaVersion     : rich ? 2 : 1,
            root              : rich ? .column([image, action, clock]) : image,
            accessibilityLabel: "Archive image",
            privacy           : .sensitive,
            assets            : ["old"],
            glassLights       : rich ? [GlassLight(
                x        : 0.2,
                y        : 0.3,
                radius   : 0.5,
                red      : 1,
                green    : 0,
                blue     : 0,
                intensity: 0.8
            )] : nil
        )
        let presentation = try PresentationSet(
            widget         : document,
            compactLeading : document,
            compactTrailing: document,
            minimal        : document,
            expanded       : document
        )

        return try Publication(
            id         : id,
            revision   : 0,
            kind       : rich ? .activity : .widget,
            content    : rich ? nil : presentation,
            timeline   : rich ? [
                ScheduledEntry(date: wall, content: presentation),
                ScheduledEntry(date: wall.addingTimeInterval(30), content: presentation),
            ] : nil,
            expiresAt  : wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
    }

    /// matches confines all decoded archive leaves and comparison graphs to protected test scopes.
    func matches(_ check: @Sendable (RuntimeArchiveEnvelope) throws -> Bool) async throws -> Bool {
        try await archive.withGeneration { generation in
            guard let generation else { return false }

            return try await governor.withAssetDecodeReservation(
                bytes: RuntimeArchiveEnvelope.retentionReservationBytes() + generation.payload.count,
                owner: owner
            ) {
                let envelope = try RuntimeArchiveEnvelope.decode(generation.payload)

                return try await governor.withAssetDecodeReservation(
                    bytes: RuntimeArchivePublicationCodec.inspectionReservationBytes(),
                    owner: owner
                ) { try check(envelope) }
            }
        }
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}
