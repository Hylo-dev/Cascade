//
//  ManifestTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite struct ManifestTests {
    @Test func rejectsInvalidIdentityOnEveryDecodingPath() throws {
        #expect(AddonID(rawValue: "invalid") == nil)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AddonID.self, from: Data("\"invalid\"".utf8))
        }
    }

    @Test func rejectsOversizedManifestBeforeDecode() throws {
        let valid = try fixtureData("focus")
        let oversized = valid + Data(repeating: 32, count: 65_537)
        #expect(throws: (any Error).self) { try AddonManifest.decode(oversized) }
    }

    @Test func rejectsUnsupportedVersionEvenUsingJSONDecoder() throws {
        let data = try manifestData { $0["manifestVersion"] = 2 }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AddonManifest.self, from: data) }
    }

    @Test(arguments: ["id", "version", "REQUIRES", "features", "PROVIDES", "resources", "permissions"])
    func rejectsMalformedManifestFields(_ field: String) throws {
        let data = try manifestData { object in
            switch field {
            case "id": object[field] = "not an identity"
            case "version": object[field] = "01.0.0"
            case "REQUIRES":
                object[field] = [["kind": "hostCapability", "id": "cascade.unknown", "version": ">=1.0.0"]]
            case "features":
                object[field] = [["id": "duplicate", "REQUIRES": []], ["id": "duplicate", "REQUIRES": []]]
            case "PROVIDES":
                object[field] = [
                    ["kind": "service", "id": "com.example.s", "version": "1.0.0"],
                    ["kind": "service", "id": "com.example.s", "version": "1.0.0"],
                ]
            case "resources":
                object[field] = [
                    "profile": "eventDriven", "requestedMemoryMiB": -1, "maximumConcurrentWork": 1,
                    "background": "scheduledDeadline",
                ]
            default: object[field] = [["id": "storage.own", "scope": "allFiles"]]
            }
        }
        #expect(throws: (any Error).self) { try AddonManifest.decode(data) }
    }
    @Test func preservesFeatureRequirementsAndOptionalSourceApplication() throws {
        let manifest = try AddonManifest.decode(fixtureData("focus"))
        #expect(manifest.sourceApp?.required == false)
        #expect(manifest.features.first { $0.id == "localTimer" }?.requires.isEmpty == true)
        #expect(manifest.features.first { $0.id == "openInSourceApp" }?.requires.first?.state == .installed)
        #expect(try AddonManifest.decode(JSONEncoder().encode(manifest)) == manifest)
        for name in ["requires-cycle-a", "requires-cycle-b", "incompatible"] {
            #expect(try AddonManifest.decode(fixtureData(name)).sourceApp == manifest.sourceApp)
        }
    }

    @Test func rejectsMalformedRangesAndDuplicateActionDeclarations() throws {
        let range = try manifestData {
            $0["REQUIRES"] = [["kind": "service", "id": "com.example.timer", "version": "^banana"]]
        }
        #expect(throws: (any Error).self) { try AddonManifest.decode(range) }
        let actions = try manifestData {
            $0["features"] = [["id": "timer", "REQUIRES": [], "actions": ["pause", "pause"]]]
        }
        #expect(throws: (any Error).self) { try AddonManifest.decode(actions) }
        let resource = Data(
            "{\"profile\":\"eventDriven\",\"requestedMemoryMiB\":\"NaN\",\"maximumConcurrentWork\":1,\"background\":\"scheduledDeadline\"}"
                .utf8
        )
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        #expect(throws: (any Error).self) { try decoder.decode(AddonResourceRequest.self, from: resource) }
    }

    @Test(arguments: ["REQUIRES", "permissions", "resources", "sourceApp"])
    func rejectsUnknownSecurityFields(_ field: String) throws {
        let data = try manifestData { object in
            if field == "REQUIRES" || field == "permissions" {
                var entries = object[field] as? [[String: Any]] ?? []
                entries[0]["unknownPrivilege"] = true
                object[field] = entries
            } else {
                var value = object[field] as? [String: Any] ?? [:]
                value["unknownPrivilege"] = true
                object[field] = value
            }
        }
        #expect(throws: (any Error).self) { try AddonManifest.decode(data) }
    }

    @Test func cycleFixturesProvideTheirCrossRequiredServices() throws {
        let first = try AddonManifest.decode(fixtureData("requires-cycle-a"))
        let second = try AddonManifest.decode(fixtureData("requires-cycle-b"))
        #expect(first.provides.first?.id == second.requires.first?.id)
        #expect(second.provides.first?.id == first.requires.first?.id)
        #expect(first.provides.first?.id != second.provides.first?.id)
    }

}
