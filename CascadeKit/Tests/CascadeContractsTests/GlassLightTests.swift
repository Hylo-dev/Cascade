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
    func rejectsAnUnknownWireField() throws {
        let valid = try GlassLight(
            x        : 0.25,
            y        : 0.6,
            radius   : 0.4,
            red      : 1,
            green    : 0.2,
            blue     : 0,
            intensity: 0.7
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
        )
        #expect(try JSONDecoder().decode(GlassLight.self, from: JSONSerialization.data(withJSONObject: object)) == valid)

        object["glow"] = 0.5
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(GlassLight.self, from: data) }
    }
}
