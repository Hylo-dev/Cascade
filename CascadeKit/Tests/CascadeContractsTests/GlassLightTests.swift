//
//  GlassLightTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@Suite
struct GlassLightTests {

    private let light: [String: Any] = [
        "x": 0.25, "y": 0.6, "radius": 0.4,
        "red": 1.0, "green": 0.2, "blue": 0.0, "intensity": 0.7,
    ]

    private func documentData(
        schema: Int = 2,
        lights: Any? = nil
    ) throws -> Data {
        var object: [String: Any] = [
            "schemaVersion": schema,
            "root": ["kind": "text", "text": "Music"],
            "privacy": "publicContent", "accessibilityLabel": "Music", "assets": [],
        ]
        if let lights { object["glassLights"] = lights }

        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test
    func preservesLegacyDocumentEncoding() throws {
        let data     = try documentData(schema: 1)
        let document = try ContentDocument.decode(data)
        let encoded  = try document.encode()
        let object   = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(Set(object.keys) == ["schemaVersion", "root", "privacy", "accessibilityLabel", "assets"])
        #expect(try ContentDocument.decode(encoded) == document)
    }

    @Test
    func roundTripsSchemaTwoLights() throws {
        let document = try ContentDocument.decode(documentData(lights: [light]))
        let encoded  = try document.encode()
        let object   = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let lights   = try #require(object["glassLights"] as? [[String: Double]])

        #expect(lights == [["x": 0.25, "y": 0.6, "radius": 0.4, "red": 1, "green": 0.2, "blue": 0, "intensity": 0.7]])
        #expect(try ContentDocument.decode(encoded) == document)
    }

    @Test
    func acceptsAbsentAndEmptyLightsInSchemaTwo() throws {
        _ = try ContentDocument.decode(documentData())
        _ = try ContentDocument.decode(documentData(lights: []))
    }

    @Test
    func requiresSchemaTwoOrLaterForEverySuppliedLightingField() throws {
        for lights: Any in [[light], [], NSNull()] {
            let data = try documentData(schema: 1, lights: lights)
            #expect(throws: (any Error).self) { try ContentDocument.decode(data) }
        }

        _ = try ContentDocument.decode(documentData(schema: 3, lights: [light]))

        for schema in [0, 4, Int.max] {
            let data = try documentData(schema: schema)
            #expect(throws: (any Error).self) { try ContentDocument.decode(data) }
        }
    }

    @Test
    func boundsLightCount() throws {
        _ = try ContentDocument.decode(documentData(lights: Array(repeating: light, count: 8)))

        let oversized = try documentData(lights: Array(repeating: light, count: 9))
        #expect(throws: (any Error).self) { try ContentDocument.decode(oversized) }
    }

    @Test
    func rejectsMalformedLightFields() throws {
        for field in light.keys {
            for value: Any in [-0.01, 1.01, NSNull(), "0.5"] {
                var malformed = light
                malformed[field] = value
                let data = try documentData(lights: [malformed])
                #expect(throws: (any Error).self) { try ContentDocument.decode(data) }
            }

            var missing = light
            missing.removeValue(forKey: field)
            let data = try documentData(lights: [missing])
            #expect(throws: (any Error).self) { try ContentDocument.decode(data) }
        }

        var zeroRadius = light
        zeroRadius["radius"] = 0
        #expect(throws: (any Error).self) { try ContentDocument.decode(documentData(lights: [zeroRadius])) }

        var unknown = light
        unknown["unexpected"] = 1
        #expect(throws: (any Error).self) { try ContentDocument.decode(documentData(lights: [unknown])) }

        var document = try #require(JSONSerialization.jsonObject(with: documentData(lights: [light])) as? [String: Any])
        document["unexpected"] = true
        let data = try JSONSerialization.data(withJSONObject: document)

        #expect(throws: (any Error).self) { try ContentDocument.decode(data) }
    }

    @Test
    func validatesEveryNativeComponentAndRejectsNonfiniteWireValues() throws {
        for index in 0..<7 {
            for invalid in [-0.01, 1.01, Double.nan, .infinity, -.infinity] {
                var components = Array(repeating: 0.5, count: 7)
                components[index] = invalid
                #expect(throws: (any Error).self) {
                    try GlassLight(
                        x        : components[0],
                        y        : components[1],
                        radius   : components[2],
                        red      : components[3],
                        green    : components[4],
                        blue     : components[5],
                        intensity: components[6]
                    )
                }
            }
        }

        #expect(throws: (any Error).self) {
            try GlassLight(
                x        : 0.5,
                y        : 0.5,
                radius   : 0,
                red      : 1,
                green    : 1,
                blue     : 1,
                intensity: 1
            )
        }

        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan             : "NaN"
        )

        for field in light.keys {
            for nonfinite in ["Infinity", "-Infinity", "NaN"] {
                var object = light
                object[field] = nonfinite
                let data = try JSONSerialization.data(withJSONObject: object)
                #expect(throws: (any Error).self) { try decoder.decode(GlassLight.self, from: data) }
            }
        }
    }

    @Test
    func acceptsComponentEndpointsAndArchivesNativeValues() throws {
        for value in [0.0, 1.0] {
            let light = try GlassLight(
                x        : value,
                y        : value,
                radius   : 1,
                red      : value,
                green    : value,
                blue     : value,
                intensity: value
            )
            #expect(try JSONDecoder().decode(GlassLight.self, from: JSONEncoder().encode(light)) == light)
        }

        _ = try GlassLight(
            x        : 0,
            y        : 1,
            radius   : .leastNonzeroMagnitude,
            red      : 0,
            green    : 1,
            blue     : 0.5,
            intensity: 0
        )
    }

    @Test
    func nativeDocumentsRequireExplicitSchemaAndBoundLights() throws {
        let value = try JSONDecoder().decode(
            GlassLight.self,
            from: JSONSerialization.data(withJSONObject: light)
        )
        let document = try ContentDocument(
            schemaVersion     : 2,
            root              : .text("Music"),
            privacy           : .publicContent,
            accessibilityLabel: "Music",
            glassLights       : [value]
        )

        #expect(document.glassLights == [value])
        #expect(try ContentDocument.decode(document.encode()) == document)
        #expect(throws: (any Error).self) {
            try ContentDocument(
                root              : .text("Music"),
                privacy           : .publicContent,
                accessibilityLabel: "Music",
                glassLights       : []
            )
        }
        #expect(throws: (any Error).self) {
            try ContentDocument(
                schemaVersion     : 1,
                root              : .text("Music"),
                accessibilityLabel: "Music",
                privacy           : .publicContent,
                assets            : [],
                glassLights       : [value]
            )
        }
        #expect(throws: (any Error).self) {
            try ContentDocument(
                schemaVersion     : 2,
                root              : .text("Music"),
                accessibilityLabel: "Music",
                privacy           : .publicContent,
                assets            : [],
                glassLights       : Array(repeating: value, count: 9)
            )
        }
    }

    @Test
    func lightsShareTheExistingDocumentByteBudget() throws {
        let largeText = try ContentNode.text(String(repeating: "x", count: 4096))
        let baseNodes = Array(repeating: largeText, count: 15)
        let base      = try ContentDocument(
            schemaVersion     : 2,
            root              : .column(baseNodes + [.text("")]),
            privacy           : .publicContent,
            accessibilityLabel: "Large document"
        )
        let remaining = 65_536 - (try base.encode().count)
        let root      = try ContentNode.column(baseNodes + [.text(String(repeating: "x", count: remaining))])
        let full      = try ContentDocument(
            schemaVersion     : 2,
            root              : root,
            privacy           : .publicContent,
            accessibilityLabel: "Large document"
        )
        #expect(try full.encode().count == 65_536)

        let value = try JSONDecoder().decode(
            GlassLight.self,
            from: JSONSerialization.data(withJSONObject: light)
        )
        #expect(throws: (any Error).self) {
            try ContentDocument(
                schemaVersion     : 2,
                root              : root,
                privacy           : .publicContent,
                accessibilityLabel: "Large document",
                glassLights       : [value]
            )
        }

        var object = try #require(JSONSerialization.jsonObject(with: full.encode()) as? [String: Any])
        object["glassLights"] = [light]
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: (any Error).self) { try JSONDecoder().decode(ContentDocument.self, from: data) }
        #expect(throws: (any Error).self) { try ContentDocument.decode(data) }
    }
}
