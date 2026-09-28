//
//  AddonResourceRequest.swift
//  Cascade
//

import Foundation

/// AddonResourceRequest is a validated value in the version 1 addon protocol.
public struct AddonResourceRequest: Codable, Equatable, Sendable {
    public let profile: Profile
    public let requestedMemoryMiB: Double
    public let maximumConcurrentWork: Int
    public let background: Background

    public init(
        profile: Profile,
        requestedMemoryMiB: Double,
        maximumConcurrentWork: Int,
        background: Background
    ) throws {
        self.profile = profile
        self.requestedMemoryMiB = requestedMemoryMiB
        self.maximumConcurrentWork = maximumConcurrentWork
        self.background = background
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decode(Profile.self, forKey: .profile)
        requestedMemoryMiB = try container.decode(Double.self, forKey: .requestedMemoryMiB)
        maximumConcurrentWork = try container.decode(Int.self, forKey: .maximumConcurrentWork)
        background = try container.decode(Background.self, forKey: .background)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            requestedMemoryMiB.isFinite && requestedMemoryMiB >= 0 && requestedMemoryMiB <= 64,
            "Memory request outside event-driven profile"
        )
        try ContractValidation.require((0...1).contains(maximumConcurrentWork), "Concurrency request outside profile")
    }
    public enum Profile: String, Codable, Sendable { case eventDriven }
    public enum Background: String, Codable, Sendable { case scheduledDeadline, none }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case profile
        case requestedMemoryMiB
        case maximumConcurrentWork
        case background
    }
}
