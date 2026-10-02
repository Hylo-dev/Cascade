//
//  FixtureData.swift
//  CascadeKit
//

import Foundation
import Testing

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))

    return try Data(contentsOf: url)
}

func pluginManifestData(changing mutate: (inout [String: Any]) -> Void) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: fixtureData("plugin-music")) as? [String: Any])
    mutate(&object)

    return try JSONSerialization.data(withJSONObject: object)
}

func changingFirstFeature(
    _ object: inout [String: Any],
    _ mutate: (inout [String: Any]) -> Void
) {
    guard var features = object["features"] as? [[String: Any]], !features.isEmpty else { return }

    mutate(&features[0])
    object["features"] = features
}
