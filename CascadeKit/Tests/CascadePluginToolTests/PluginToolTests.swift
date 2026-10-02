//
//  PluginToolTests.swift
//  CascadeKit
//

import Darwin
import Foundation
import Testing
@testable import CascadePluginTool

@Suite
struct PluginToolTests {

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        return url
    }

    /// writeManifest copies the clock fixture into directory, edited, so a test can build a second
    /// valid manifest or a broken one without a fixture file per case.
    func writeManifest(
        in directory: URL,
        named name  : String,
        editing edit: (inout [String: Any]) -> Void
    ) throws -> URL {
        let source = try #require(Bundle.module.url(forResource: "plugin-clock", withExtension: "json"))
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
        edit(&object)

        let file = directory.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: object).write(to: file)

        return file
    }

    @Test
    func validatesAPluginManifestWithoutClaimingRuntimeAdmission() throws {
        let url    = try #require(Bundle.module.url(forResource: "plugin-clock", withExtension: "json"))
        let result = PluginToolCommand.run(arguments: ["validate", url.path])

        #expect(result.exitCode == 0)
        #expect(result.output.hasPrefix("\(url.path): valid plugin manifest com.cascade.clock 1.0.0"))
        #expect(result.output.contains("signature"))
    }

    @Test
    func rejectsAVersionOneManifestBecauseOnlyVersionTwoIsAccepted() throws {
        let url    = try #require(Bundle.module.url(forResource: "focus", withExtension: "json"))
        let result = PluginToolCommand.run(arguments: ["validate", url.path])

        #expect(result.exitCode == 1)
        #expect(result.output.contains(url.path))
        #expect(result.output.contains("Only manifest version 2 is accepted"))
    }

    @Test
    func validatesEveryManifestItIsGiven() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock  = try #require(Bundle.module.url(forResource: "plugin-clock", withExtension: "json"))
        let other  = try writeManifest(in: directory, named: "other.json") { $0["id"] = "com.cascade.other" }
        let result = PluginToolCommand.run(arguments: ["validate", clock.path, other.path])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("com.cascade.clock"))
        #expect(result.output.contains("com.cascade.other"))
    }

    @Test
    func failsWhenOneManifestAmongSeveralIsBadAndNamesIt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock  = try #require(Bundle.module.url(forResource: "plugin-clock", withExtension: "json"))
        let broken = try writeManifest(in: directory, named: "broken.json") { $0["PROVIDES"] = [] }
        let result = PluginToolCommand.run(arguments: ["validate", clock.path, broken.path])
        let lines  = result.output.split(separator: "\n")

        #expect(result.exitCode == 1)
        #expect(lines.contains { $0.contains(broken.path) && $0.contains("Unknown wire field") })
        #expect(!lines.contains { $0.contains(clock.path) && $0.contains("invalid") })
    }

    @Test
    func invalidManifestProducesFailureWithoutExecutingItsContents() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file   = directory.appendingPathComponent("Manifest.json")
        let marker = directory.appendingPathComponent("must-not-exist")
        let object = ["install": "touch \(marker.path)", "manifestVersion": "unknown"]
        try JSONEncoder().encode(object).write(to: file)

        let result = PluginToolCommand.run(arguments: ["validate", file.path])

        #expect(result.exitCode == 1)
        #expect(result.output.contains(file.path))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test
    func rejectsOversizedInputAndNonregularFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("Manifest.json")
        try Data(repeating: 32, count: 65_537).write(to: file)

        #expect(PluginToolCommand.run(arguments: ["validate", file.path]).exitCode == 1)
        #expect(PluginToolCommand.run(arguments: ["validate", directory.path]).exitCode == 1)

        let fifo = directory.appendingPathComponent("fifo")
        try #require(mkfifo(fifo.path, 0o600) == 0)

        #expect(PluginToolCommand.run(arguments: ["validate", fifo.path]).exitCode == 1)
    }

    @Test
    func badArgumentsAndMissingFilesReturnDistinctFailures() {
        #expect(PluginToolCommand.run(arguments: []).exitCode == 2)
        #expect(PluginToolCommand.run(arguments: ["validate"]).exitCode == 2)
        #expect(PluginToolCommand.run(arguments: ["init"]).exitCode == 2)
        #expect(PluginToolCommand.run(arguments: ["--help"]).exitCode == 0)
        #expect(PluginToolCommand.run(arguments: ["help"]).exitCode == 0)
        #expect(PluginToolCommand.run(arguments: ["validate", "/missing-a.json", "/missing-b.json"]).exitCode == 1)
    }
}
