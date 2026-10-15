//
//  ItalianStrings.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadePlugins

/// ItalianStrings reads a translation from the bundled string catalog. Depending on the
/// toolchain, the package build either copies a catalog as it is or compiles it into each
/// language's `.lproj`; the raw catalog is read when it was copied, and the Italian table of
/// the compiled bundle otherwise, so a test learns that a visible string has its translation
/// either way.
enum ItalianStrings {

    static func value(
        of key  : String,
        in table: String = "Plugins"
    ) throws -> String? {
        guard let url = Bundle.module.url(forResource: table, withExtension: "xcstrings") else {
            let path    = try #require(Bundle.module.path(forResource: "it", ofType: "lproj"))
            let italian = try #require(Bundle(path: path))
            let missing = "\u{0}"
            let value   = italian.localizedString(forKey: key, value: missing, table: table)

            return value == missing ? nil : value
        }

        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = catalog["strings"] as? [String: Any]
        let entry   = strings?[key] as? [String: Any]
        let italian = (entry?["localizations"] as? [String: Any])?["it"] as? [String: Any]

        return (italian?["stringUnit"] as? [String: Any])?["value"] as? String
    }
}
