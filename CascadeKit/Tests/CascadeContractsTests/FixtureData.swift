//
//  FixtureData.swift
//  Cascade
//

import Foundation
import Testing

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

func manifestData(changing mutate: (inout [String: Any]) -> Void) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: fixtureData("focus")) as? [String: Any])
    mutate(&object)
    return try JSONSerialization.data(withJSONObject: object)
}
