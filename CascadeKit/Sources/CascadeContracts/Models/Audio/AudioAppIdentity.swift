//
//  AudioAppIdentity.swift
//  CascadeKit
//

import Foundation

/// AudioAppIdentity names an app whose volume the mixer can steer: the bundle identifier of its
/// outermost `.app`, so a browser and its helper processes are one entry. It is never a PID or a
/// display name, because both change under the user's feet (a relaunch, a localisation) while
/// the intent the user set must outlive them.
public struct AudioAppIdentity: Codable, Hashable, Sendable {

    public static let maximumBundleIDBytes = 255

    public let bundleID: String

    public init(bundleID: String) throws {
        self.bundleID = bundleID

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID      = try container.decode(String.self, forKey: .bundleID)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            !bundleID.isEmpty && bundleID.utf8.count <= Self.maximumBundleIDBytes,
            "Invalid audio app identity"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case bundleID
    }
}
