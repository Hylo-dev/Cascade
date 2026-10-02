//
//  PluginHostSigning.swift
//  CascadeKit
//

import Foundation
import Security

/// PluginHostSigning builds the code signing requirement each side of PluginHost demands of the
/// other: the peer's bundle identifier, signed by an Apple certificate of this process's team. An
/// ad hoc build, a fresh clone's default, has no team and gets no requirement; it relies on the
/// system rule that an XPC service bundled in an app answers only that app.
public enum PluginHostSigning {

    /// currentTeam is the team that signed this process, or nil when it is signed ad hoc.
    public static var currentTeam: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any]
        else { return nil }

        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// requirement is what a peer must satisfy: `identifier`, signed by `team`; nil without a team.
    public static func requirement(
        identifier: String,
        team      : String?
    ) -> String? {
        guard let team, !team.isEmpty else { return nil }

        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
