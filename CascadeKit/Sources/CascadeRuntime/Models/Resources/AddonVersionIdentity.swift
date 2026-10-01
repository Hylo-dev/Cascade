//
//  AddonVersionIdentity.swift
//  CascadeKit
//

import CascadeContracts

/// AddonVersionIdentity names the verified publisher, addon, and semantic version
/// whose health history the host retains. The publisher is verifier output rather
/// than addon payload authentication; build metadata cannot create a fresh health
/// identity because `SemanticVersion` intentionally compares version precedence.
public struct AddonVersionIdentity: Hashable, Sendable {

    public let verifiedIdentity: VerifiedAddonIdentity
    public let version         : SemanticVersion

    public init(
        verifiedIdentity: VerifiedAddonIdentity,
        version         : SemanticVersion
    ) throws {
        let publisherBytes  = verifiedIdentity.publisher.utf8.count
        let prereleaseBytes = version.prerelease?.utf8.count ?? 0
        let buildBytes      = version.buildMetadata?.utf8.count ?? 0
        let reparsedVersion = SemanticVersion(version.description)

        guard publisherBytes > 0,
              publisherBytes <= 512,
              !verifiedIdentity.publisher.allSatisfy(\.isWhitespace),
              version.major >= 0,
              version.minor >= 0,
              version.patch >= 0,
              prereleaseBytes <= 128,
              buildBytes <= 128,
              reparsedVersion?.major == version.major,
              reparsedVersion?.minor == version.minor,
              reparsedVersion?.patch == version.patch,
              reparsedVersion?.prerelease == version.prerelease,
              reparsedVersion?.buildMetadata == version.buildMetadata
        else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The verified addon version identity is invalid."
            )
        }

        self.verifiedIdentity = verifiedIdentity
        self.version          = version
    }
}
