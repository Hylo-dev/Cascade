//
//  PluginManifestTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginManifestTests {

    @Test
    func decodesTheMusicManifest() throws {
        let manifest = try PluginManifest.decode(fixtureData("plugin-music"))
        let feature  = try #require(manifest.features.first)
        let sizes    = [try PluginWidgetSize(columns: 2, rows: 1), try PluginWidgetSize(columns: 2, rows: 2)]
        let spectrum = try PluginComponentReference(id: "audio.spectrum", version: 1)
        let scrubber = try PluginComponentReference(id: "media.scrubber", version: 1)

        #expect(manifest.id.rawValue == "com.cascade.music")
        #expect(manifest.sourceApp == "com.apple.Music")
        #expect(feature.surfaces.activity != nil)
        #expect(feature.surfaces.notice == nil)
        #expect(feature.surfaces.widget?.sizes == sizes)
        #expect(feature.components == [spectrum, scrubber])
        #expect(feature.actions.count == 5)
    }

    @Test
    func leavesUndeclaredListsEmpty() throws {
        let manifest = try PluginManifest.decode(fixtureData("plugin-clock"))
        let feature  = try #require(manifest.features.first)

        #expect(manifest.requires.isEmpty)
        #expect(manifest.sourceApp == nil)
        #expect(feature.sources.isEmpty && feature.components.isEmpty && feature.actions.isEmpty)
    }

    @Test
    func roundTripsThroughJSON() throws {
        let manifest = try PluginManifest.decode(fixtureData("plugin-music"))
        let decoded  = try PluginManifest.decode(JSONEncoder().encode(manifest))

        #expect(decoded == manifest)
    }

    @Test
    func rejectsOversizedDataBeforeDecoding() throws {
        let data = try fixtureData("plugin-clock") + Data(repeating: 32, count: 65_537)

        #expect(throws: AddonFailure.self) { try PluginManifest.decode(data) }
    }

    @Test(arguments: [
        "manifestVersion", "version", "macOS", "protocolMajor", "executionMode", "unknownField", "noFeatures",
        "sourceApp",
    ])
    func rejectsInvalidTopLevelValues(_ change: String) throws {
        let data = try pluginManifestData { object in
            switch change {
                case "manifestVersion":
                    object["manifestVersion"] = 1

                case "version":
                    object["version"] = "01.0.0"

                case "macOS":
                    object["compatibility"] = ["macOS": "14.0", "cascadeProtocol": ["major": 2, "minimumMinor": 0]]

                case "protocolMajor":
                    object["compatibility"] = ["macOS": "15.0", "cascadeProtocol": ["major": 1, "minimumMinor": 0]]

                case "executionMode":
                    object["execution"] = ["entryPoint": "MusicPlugin", "mode": "inProcess"]

                case "unknownField":
                    object["PROVIDES"] = []

                case "noFeatures":
                    object["features"] = []

                default:
                    object["sourceApp"] = "Music"
            }
        }

        #expect(throws: (any Error).self) { try PluginManifest.decode(data) }
    }

    @Test
    func acceptsOnlySemVerVersionsWithinTheByteBound() throws {
        for version in ["1.2.3", "1.2.3-0+build.9", "1.2.3+" + String(repeating: "a", count: 122)] {
            let data = try pluginManifestData { $0["version"] = version }

            #expect(try PluginManifest.decode(data).version == version)
        }

        for version in ["", "01.2.3", "1.2.3-01", "1.2", "1.2.3+" + String(repeating: "a", count: 123)] {
            let data = try pluginManifestData { $0["version"] = version }

            #expect(throws: AddonFailure.self) { try PluginManifest.decode(data) }
        }
    }

    @Test(arguments: [
        "unknownSource", "newerComponent", "unknownComponent", "noSurface", "plainSurfaceField",
        "widgetTooLarge", "widgetMalformed", "duplicateAction", "invalidAction",
    ])
    func rejectsInvalidFeatures(_ change: String) throws {
        let data = try pluginManifestData { object in
            changingFirstFeature(&object) { feature in
                switch change {
                    case "unknownSource":
                        feature["sources"] = ["media.lyrics"]

                    case "newerComponent":
                        feature["components"] = [["id": "audio.spectrum", "version": 2]]

                    case "unknownComponent":
                        feature["components"] = [["id": "audio.equalizer", "version": 1]]

                    case "noSurface":
                        feature["surfaces"] = [String: Any]()

                    case "plainSurfaceField":
                        feature["surfaces"] = ["activity": ["lifetime": 8]]

                    case "widgetTooLarge":
                        feature["surfaces"] = ["widget": ["sizes": ["5x1"]]]

                    case "widgetMalformed":
                        feature["surfaces"] = ["widget": ["sizes": ["2by1"]]]

                    case "duplicateAction":
                        feature["actions"] = ["next", "next"]

                    default:
                        feature["actions"] = ["skip forward"]
                }
            }
        }

        #expect(throws: (any Error).self) { try PluginManifest.decode(data) }
    }

    @Test
    func rejectsNestedAlternatives() throws {
        let nested: [String: Any] = [
            "kind"        : "anyOf",
            "alternatives": [
                ["kind": "appRunning", "bundleID": "com.apple.Music"],
                ["kind": "anyOf", "alternatives": [
                    ["kind": "appRunning", "bundleID": "com.spotify.client"],
                    ["kind": "appRunning", "bundleID": "com.apple.TV"],
                ]],
            ],
        ]
        let data = try pluginManifestData { $0["REQUIRES"] = [nested] }

        #expect(throws: (any Error).self) { try PluginManifest.decode(data) }
    }

    @Test
    func validatesRequirementsBuiltInCode() throws {
        let manifest = try PluginManifest.decode(fixtureData("plugin-clock"))

        #expect(throws: AddonFailure.self) {
            try PluginManifest(
                manifestVersion: 2,
                id             : manifest.id,
                version        : manifest.version,
                compatibility  : manifest.compatibility,
                execution      : manifest.execution,
                sourceApp      : nil,
                requires       : [.appInstalled(bundleID: "Music")],
                features       : manifest.features,
                resources      : manifest.resources
            )
        }
    }

    @Test
    func rejectsDeeplyNestedAlternativesWhileDecodingWithoutExhaustingTheStack() throws {
        var requirement: [String: Any] = ["kind": "appRunning", "bundleID": "com.apple.Music"]
        for _ in 0..<200 {
            requirement = ["kind": "anyOf", "alternatives": [requirement, ["kind": "appRunning", "bundleID": "com.apple.TV"]]]
        }

        let data     = try pluginManifestData { $0["REQUIRES"] = [requirement] }
        let rejected = onSmallStack {
            do {
                _ = try PluginManifest.decode(data)
                return false
            } catch {
                return error is AddonFailure
            }
        }

        #expect(rejected)
    }
}
