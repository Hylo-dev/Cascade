//
//  ItalianStrings.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadePlugins

/// ItalianStrings reads a translation straight from a bundled string catalog. The package build
/// copies catalogs without compiling them, so the bundle cannot be asked for Italian; reading the
/// catalog is what tells a test that a visible string has its translation.
enum ItalianStrings {

    static func value(
        of key  : String,
        in table: String = "Plugins"
    ) throws -> String? {
        let url     = try #require(Bundle.module.url(forResource: table, withExtension: "xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = catalog["strings"] as? [String: Any]
        let entry   = strings?[key] as? [String: Any]
        let italian = (entry?["localizations"] as? [String: Any])?["it"] as? [String: Any]

        return (italian?["stringUnit"] as? [String: Any])?["value"] as? String
    }
}
