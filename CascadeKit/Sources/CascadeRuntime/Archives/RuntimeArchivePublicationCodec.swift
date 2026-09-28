//
//  RuntimeArchivePublicationCodec.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeArchivePublicationCodec keeps recursive contract graphs outside the shallow binary plist.
/// These synchronous helpers do not admit resources. The caller must protect the input leaves,
/// reserve inspectionReservationBytes before inspect, and retain each decoded graph under its Q
/// quote until all original/remapped graph references disappear. Encoding also needs caller-owned
/// output/parser workspace; Foundation's private parser allocations remain an estimate, not RSS proof.
enum RuntimeArchivePublicationCodec {
    /// Footprint retains only scalar shape counts and Q, never a decoded Publication graph.
    struct Footprint: Equatable, Sendable {
        let nodes          : Int
        let assets         : Int
        let documents      : Int
        let lights         : Int
        let timelineEntries: Int
        let jsonBytes      : Int
        let requiredBytes  : Int
    }

    static let maximumPublicationBytes = 266_240
    static let parserWorkspaceBytes    = 8 * 1_024 * 1_024

    /// inspectionReservationBytes protects one maximum contract graph and scalar/parser workspace.
    static func inspectionReservationBytes() throws -> Int {
        try RuntimeArchiveCost.add(
            charge(
                nodes          : 20_480,
                assets         : 10_240,
                documents      : 160,
                lights         : 1_280,
                timelineEntries: 32,
                jsonBytes      : maximumPublicationBytes
            ),
            parserWorkspaceBytes
        )
    }

    /// charge derives Q with checked arithmetic, including decoded/remapped graph overlap.
    static func charge(
        nodes          : Int,
        assets         : Int,
        documents      : Int,
        lights         : Int,
        timelineEntries: Int,
        jsonBytes      : Int
    ) throws -> Int {
        let nodeUnit = max(
            1_024,
            try RuntimeArchiveCost.multiply(
                4,
                MemoryLayout<ContentNode>.stride
            )
        )
        let documentUnit = max(
            2_048,
            try RuntimeArchiveCost.multiply(
                4,
                MemoryLayout<ContentDocument>.stride
            )
        )
        let lightUnit = max(
            256,
            try RuntimeArchiveCost.multiply(
                4,
                MemoryLayout<GlassLight>.stride
            )
        )
        let entryUnit = try RuntimeArchiveCost.multiply(
            4,
            MemoryLayout<ScheduledEntry>.stride
        )
        var result = 65_536
        for (count, unit) in [
            (nodes, nodeUnit), (assets, 256), (documents, documentUnit),
            (lights, lightUnit), (timelineEntries, entryUnit), (jsonBytes, 4),
        ] {
            result = try RuntimeArchiveCost.add(
                result,
                RuntimeArchiveCost.multiply(
                    count,
                    unit
                )
            )
        }
        return result
    }

    /// encode validates the contract and caps its independently admitted JSON leaf.
    static func encode(_ publication: Publication) throws -> Data {
        try publication.validate()
        let data = try JSONEncoder().encode(publication)
        try RuntimeArchiveCost.require(data.count <= maximumPublicationBytes)
        return data
    }

    /// decode checks raw JSON size before the existing hardened contract decoder runs.
    static func decode(_ data: Data) throws -> Publication {
        try RuntimeArchiveCost.require(data.count <= maximumPublicationBytes)
        return try JSONDecoder().decode(
            Publication.self,
            from: data
        )
    }

    /// inspect releases its sole decoded graph before returning the small scalar summary.
    static func inspect(_ data: Data) throws -> Footprint {
        let publication = try decode(data)
        var nodes       = 0
        var assets      = 0
        var documents   = 0
        var lights      = 0
        func countNode(_ node: ContentNode) throws {
            nodes = try RuntimeArchiveCost.add(
                nodes,
                1
            )
            for child in node.children ?? [] { try countNode(child) }
        }
        func countPresentations(_ presentations: PresentationSet) throws {
            for document in [
                presentations.widget, presentations.compactLeading, presentations.compactTrailing,
                presentations.minimal, presentations.expanded,
            ] {
                guard let document else { continue }
                documents = try RuntimeArchiveCost.add(
                    documents,
                    1
                )
                assets = try RuntimeArchiveCost.add(
                    assets,
                    document.assets.count
                )
                lights = try RuntimeArchiveCost.add(
                    lights,
                    document.glassLights?.count ?? 0
                )
                try countNode(document.root)
            }
        }
        if let content = publication.content { try countPresentations(content) }
        for entry in publication.timeline ?? [] { try countPresentations(entry.content) }
        let entries = publication.timeline?.count ?? 0
        return try Footprint(
            nodes          : nodes,
            assets         : assets,
            documents      : documents,
            lights         : lights,
            timelineEntries: entries,
            jsonBytes      : data.count,
            requiredBytes  : charge(
                nodes          : nodes,
                assets         : assets,
                documents      : documents,
                lights         : lights,
                timelineEntries: entries,
                jsonBytes      : data.count
            )
        )
    }

    /// validateBinding checks inert envelope provenance against a decoded graph, without granting assets.
    /// Call under the publication Q reservation; the bounded alias set is part of that graph workspace.
    static func validateBinding(
        _ publication: Publication,
        record       : RuntimeArchiveEnvelope.Record,
        owner        : AddonID
    ) throws {
        try RuntimeArchiveCost.require(
            publication.id.addonID == owner
                && RuntimeArchiveEnvelope.uuidBytes(publication.id.instanceID) == record.instance
                && RuntimeArchiveEnvelope.uuidBytes(publication.id.sessionID) == record.session
                && publication.revision == record.revision && publication.kind == record.kind
                && record.publication != nil && record.kind != .notice
        )
        var references = Set<Data>()
        try publication.forEachAssetReference { asset, _ in
            try RuntimeArchiveCost.require(
                references.count < RuntimeArchiveEnvelope.maximumAliases
                    || references.contains(Data(asset.utf8))
            )
            references.insert(Data(asset.utf8))
        }
        try RuntimeArchiveCost.require(references == Set(record.aliases.map(\.name)))
    }
}

/// RuntimeArchiveCost rejects overflow before callers form quota requests or retain controlled values.
enum RuntimeArchiveCost {
    static func require(_ condition: Bool) throws {
        guard condition else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Invalid or oversized runtime archive value"
            )
        }
    }

    static func add(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let (
            result,
            overflow
        ) = lhs.addingReportingOverflow(rhs)
        try require(lhs >= 0 && rhs >= 0 && !overflow)
        return result
    }

    static func multiply(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        let (
            result,
            overflow
        ) = lhs.multipliedReportingOverflow(by: rhs)
        try require(lhs >= 0 && rhs >= 0 && !overflow)
        return result
    }
}
