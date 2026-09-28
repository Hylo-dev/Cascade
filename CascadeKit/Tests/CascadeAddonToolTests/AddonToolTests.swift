//
//  AddonToolTests.swift
//  CascadeKit
//

import Darwin
import Foundation
import Testing
@testable import CascadeAddonTool

@Suite struct AddonToolTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test func validManifestReturnsIdentityWithoutClaimingPackageAdmission() throws {
        let url = try #require(Bundle.module.url(forResource: "focus", withExtension: "json"))
        let result = AddonToolCommand.run(arguments: ["validate", url.path])
        #expect(result.exitCode == 0)
        #expect(result.output.contains("com.example.focus.cascade"))
        #expect(result.output.contains("1.0.0"))
        #expect(result.output.contains("signature"))
    }

    @Test func invalidManifestProducesFailureWithoutExecutingItsContents() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Manifest.json")
        let marker = dir.appendingPathComponent("must-not-exist")
        let object = ["install": "touch \(marker.path)", "manifestVersion": "unknown"]
        try JSONEncoder().encode(object).write(to: file)
        let result = AddonToolCommand.run(arguments: ["validate", file.path])
        #expect(result.exitCode == 1)
        #expect(!result.output.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func rejectsOversizedInputAndNonregularFiles() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Manifest.json")
        try Data(repeating: 32, count: 65_537).write(to: file)
        #expect(AddonToolCommand.run(arguments: ["validate", file.path]).exitCode == 1)
        #expect(AddonToolCommand.run(arguments: ["validate", dir.path]).exitCode == 1)
        let fifo = dir.appendingPathComponent("fifo")
        try #require(mkfifo(fifo.path, 0o600) == 0)
        #expect(AddonToolCommand.run(arguments: ["validate", fifo.path]).exitCode == 1)
    }

    @Test func badArgumentsAndMissingFileReturnDistinctFailures() {
        #expect(AddonToolCommand.run(arguments: []).exitCode == 2)
        #expect(AddonToolCommand.run(arguments: ["validate"]).exitCode == 2)
        #expect(AddonToolCommand.run(arguments: ["validate", "a", "b"]).exitCode == 2)
        #expect(AddonToolCommand.run(arguments: ["--help"]).exitCode == 0)
        #expect(AddonToolCommand.run(arguments: ["validate", "/path-that-does-not-exist/Manifest.json"]).exitCode == 1)
    }
}
