//
//  Publication.swift
//  CascadeKit
//

import Foundation

/// Publication is a validated value in the version 1 addon protocol.
public struct Publication: Codable, Equatable, Sendable {
    public let id: PublicationID
    public let revision: UInt64
    public let kind: Kind
    public let content: PresentationSet?
    public let timeline: [ScheduledEntry]?
    public let expiresAt: Date
    public let stalePolicy: StalePolicy

    public init(
        id: PublicationID,
        revision: UInt64,
        kind: Kind,
        content: PresentationSet?,
        timeline: [ScheduledEntry]?,
        expiresAt: Date,
        stalePolicy: StalePolicy
    ) throws {
        self.id = id
        self.revision = revision
        self.kind = kind
        self.content = content
        self.timeline = timeline
        self.expiresAt = expiresAt
        self.stalePolicy = stalePolicy
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasContent = container.contains(.content) ? try !container.decodeNil(forKey: .content) : false
        let hasTimeline = container.contains(.timeline) ? try !container.decodeNil(forKey: .timeline) : false
        try ContractValidation.require(
            hasContent != hasTimeline,
            "Publication requires content or timeline exclusively"
        )
        id = try container.decode(PublicationID.self, forKey: .id)
        revision = try container.decode(UInt64.self, forKey: .revision)
        kind = try container.decode(Kind.self, forKey: .kind)
        content = try container.decodeIfPresent(PresentationSet.self, forKey: .content)
        if container.contains(.timeline), try !container.decodeNil(forKey: .timeline) {
            timeline = try BoundedContractArray.decode(
                ScheduledEntry.self,
                from    : container.superDecoder(forKey: .timeline),
                maximum : 32
            )
        } else {
            timeline = nil
        }
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        stalePolicy = try container.decode(StalePolicy.self, forKey: .stalePolicy)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.finite(expiresAt)
        try ContractValidation.require(
            (content != nil) != (timeline != nil),
            "Publication requires content or timeline exclusively"
        )
        if let content { try content.validateFamily(kind) }
        if let timeline {
            try ContractValidation.require(
                !timeline.isEmpty && timeline.count <= 32,
                "Timeline requires 1...32 entries"
            )
            try ContractValidation.bytes(timeline, maximum: 262_144)
            var previous: Date?
            for entry in timeline {
                try entry.content.validateFamily(kind)
                try ContractValidation.require(
                    entry.date < expiresAt && (previous.map { $0 < entry.date } ?? true),
                    "Timeline dates must increase before expiry"
                )
                previous = entry.date
            }
        }
    }
    public enum Kind: String, Codable, Sendable { case widget, activity, notice }
    public enum StalePolicy: String, Codable, Sendable { case retainMarked, remove }
    /// validateRevision rejects replay against host-owned session history.
    public func validateRevision(after previous: UInt64?) throws {
        if let previous {
            try ContractValidation.require(revision > previous, "Publication revision is stale or reused")
        }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case revision
        case kind
        case content
        case timeline
        case expiresAt
        case stalePolicy
    }
}
