//
//  AudioHostSnapshot.swift
//  CascadeKit
//

import Foundation

/// AudioHostSnapshot is the whole state AudioHost publishes: the apps producing audio and
/// whether the system lets it capture them. It is a full state, never a delta, so a snapshot
/// that arrives late or after a restart still leaves the mixer right.
///
/// `generation` is local to one AudioHost incarnation and grows with every change, so the
/// mixer can drop an out-of-order snapshot; across a restart it starts over, and the mixer
/// treats the new connection as a new epoch rather than comparing the numbers.
public struct AudioHostSnapshot: Codable, Equatable, Sendable {

    public static let maximumApps = 64

    public let generation    : UInt64
    public let apps          : [AudioAppSnapshot]
    public let captureAllowed: Bool?

    public init(
        generation    : UInt64,
        apps          : [AudioAppSnapshot],
        captureAllowed: Bool?
    ) throws {
        self.generation     = generation
        self.apps           = apps
        self.captureAllowed = captureAllowed

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container  = try decoder.container(keyedBy: CodingKeys.self)
        generation     = try container.decode(UInt64.self, forKey: .generation)
        apps           = try container.decode([AudioAppSnapshot].self, forKey: .apps)
        captureAllowed = try container.decodeIfPresent(Bool.self, forKey: .captureAllowed)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(apps.count <= Self.maximumApps, "Too many audio apps")
        try ContractValidation.require(
            Set(apps.map(\.identity)).count == apps.count,
            "Duplicate audio apps"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case generation
        case apps
        case captureAllowed
    }
}
