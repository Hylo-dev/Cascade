import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeAddonTool

@Suite struct ScaffoldCommandTests {
    private func withWorkspace(_ body: (URL, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sdk = root.appendingPathComponent("SDK")
        try FileManager.default.createDirectory(at: sdk, withIntermediateDirectories: false)
        // Init must only inspect the file type, never evaluate a package manifest.
        try Data("fatalError(\"must not evaluate\")".utf8).write(to: sdk.appendingPathComponent("Package.swift"))
        try body(root, sdk, root.appendingPathComponent("Example"))
    }

    private func arguments(_ destination: URL, _ sdk: URL, name: String = "Focus", id: String = "com.example.focus") -> [String] {
        ["init", "--name", name, "--identifier", id, "--destination", destination.path, "--sdk-path", sdk.path]
    }

    private func entries(_ root: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
    }

    @Test func createsCompleteSourcePackageWithValidatedManifest() throws {
        try withWorkspace { root, sdk, destination in
            let before = try entries(root)
            let result = AddonToolCommand.run(arguments: arguments(destination, sdk))
            try #require(result.exitCode == 0)
            #expect(result.output.contains("source"))
            let expected = ["Package.swift", "Manifest.json", "README.md", ".gitignore",
                            "Sources/FocusAddon/FocusProvider.swift", "Tests/FocusAddonTests/FocusProviderTests.swift"]
            for file in expected {
                #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent(file).path))
            }
            #expect(try entries(root) == before.union(["Example"]))
            let manifestURL = destination.appendingPathComponent("Manifest.json")
            let manifest = try AddonManifest.decode(Data(contentsOf: manifestURL))
            #expect(manifest.id.rawValue == "com.example.focus")
            #expect(manifest.requires.isEmpty && manifest.provides.isEmpty && manifest.permissions.isEmpty)
            #expect(manifest.execution.entryPoint == "provider")
            #expect(AddonToolCommand.run(arguments: ["validate", manifestURL.path]).exitCode == 0)
            let package = try String(contentsOf: destination.appendingPathComponent("Package.swift"), encoding: .utf8)
            #expect(package.contains(".library(") && !package.contains(".executable"))
            #expect(package.contains("CascadeAddonSDK") && package.contains("CascadeContracts"))
            #expect(!package.contains("CascadeRuntime") && !package.contains("CascadeKit\""))
            let source = try String(contentsOf: destination.appendingPathComponent(expected[4]), encoding: .utf8)
            #expect(source.contains("actor FocusProvider: AddonProvider"))
            #expect(source.contains("validateOwner") && source.contains("case .refresh"))
            #expect(source.contains("addingTimeInterval") && source.contains("UInt64.max"))
            #expect(source.contains("case .stop") && source.contains("throw AddonFailure"))
            let tests = try String(contentsOf: destination.appendingPathComponent(expected[5]), encoding: .utf8)
            #expect(tests.contains("refresh") && tests.contains("stop") && tests.contains("Owner"))
            #expect(!tests.contains("@testable") && !tests.contains("CascadeRuntime"))
            let readme = try String(contentsOf: destination.appendingPathComponent("README.md"), encoding: .utf8)
            #expect(readme.contains("source") && readme.contains("signing") && readme.contains("bootstrap"))
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(".build").path))
        }
    }

    @Test func acceptsReorderedFlagsAndKeywordName() throws {
        try withWorkspace { _, sdk, destination in
            let result = AddonToolCommand.run(arguments: ["init", "--sdk-path", sdk.path, "--destination", destination.path,
                                                         "--identifier", "org.example.keyword", "--name", "class"])
            try #require(result.exitCode == 0)
            #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Sources/classAddon/classProvider.swift").path))
        }
    }

    @Test(arguments: ["file", "empty", "nonempty", "symlink", "dangling"])
    func refusesEveryExistingDestinationAndCleansOnlyStaging(kind: String) throws {
        try withWorkspace { root, sdk, destination in
            let sentinel = root.appendingPathComponent("sentinel")
            try Data("keep me".utf8).write(to: sentinel)
            switch kind {
            case "file": try Data("developer file".utf8).write(to: destination)
            case "empty", "nonempty":
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                if kind == "nonempty" { try Data("keep me".utf8).write(to: destination.appendingPathComponent("sentinel")) }
            case "symlink": try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: sdk)
            default: try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: root.appendingPathComponent("missing"))
            }
            let before = try entries(root)
            let result = AddonToolCommand.run(arguments: arguments(destination, sdk))
            #expect(result.exitCode == 1)
            #expect(try entries(root) == before)
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep me")
            if kind == "file" { #expect(try String(contentsOf: destination, encoding: .utf8) == "developer file") }
            if kind == "nonempty" { #expect(try String(contentsOf: destination.appendingPathComponent("sentinel"), encoding: .utf8) == "keep me") }
            if kind == "symlink" || kind == "dangling" {
                #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path).hasSuffix(kind == "symlink" ? "SDK" : "missing"))
            }
        }
    }

    @Test func rejectsMalformedArgumentsWithoutFilesystemChanges() throws {
        try withWorkspace { root, sdk, destination in
            let good = arguments(destination, sdk)
            let cases: [[String]] = [["init"], Array(good.dropLast()), good + ["extra"], good + ["--name", "Other"],
                                     good + ["--unknown", "x"], ["init", "--help", "x"],
                                     arguments(destination, sdk, name: ""),
                                     ["init", "--name", "--identifier", "com.example.focus", "--destination", destination.path, "--sdk-path", sdk.path]]
            let before = try entries(root)
            for malformed in cases {
                #expect(AddonToolCommand.run(arguments: malformed).exitCode == 2)
                #expect(try entries(root) == before)
            }
        }
    }

    @Test(arguments: ["../escape", "1Name", "Bad-Name", "Naïve", String(repeating: "N", count: 65), "name\u{0}suffix", "Name\n"])
    func rejectsInvalidNameWithoutWriting(name: String) throws {
        try withWorkspace { root, sdk, destination in
            let before = try entries(root)
            #expect(AddonToolCommand.run(arguments: arguments(destination, sdk, name: name)).exitCode == 1)
            #expect(try entries(root) == before)
        }
    }

    @Test(arguments: ["invalid", "com..example", "com.example/escape", "com.example\u{0}suffix", "com.example\n"])
    func rejectsInvalidIdentityWithoutWriting(id: String) throws {
        try withWorkspace { root, sdk, destination in
            let before = try entries(root)
            #expect(AddonToolCommand.run(arguments: arguments(destination, sdk, id: id)).exitCode == 1)
            #expect(try entries(root) == before)
        }
    }

    @Test func rejectsMissingParentAndUnsafePathsWithoutWriting() throws {
        try withWorkspace { root, sdk, destination in
            let before = try entries(root)
            let cases = [arguments(root.appendingPathComponent("missing/new"), sdk),
                         arguments(destination, root.appendingPathComponent("missing-sdk")),
                         arguments(destination, sdk.appendingPathComponent("Package.swift"))]
            for invalid in cases { #expect(AddonToolCommand.run(arguments: invalid).exitCode == 1) }
            var nulDestination = arguments(destination, sdk)
            nulDestination[6] += "\u{0}suffix"
            #expect(AddonToolCommand.run(arguments: nulDestination).exitCode == 1)
            var nulSDK = arguments(destination, sdk)
            nulSDK[8] += "\u{0}suffix"
            #expect(AddonToolCommand.run(arguments: nulSDK).exitCode == 1)
            #expect(try entries(root) == before)
        }
    }

    @Test(arguments: ["directory", "symlink", "fifo"])
    func requiresRegularSDKManifestWithoutFollowingLinks(kind: String) throws {
        try withWorkspace { root, sdk, destination in
            let manifest = sdk.appendingPathComponent("Package.swift")
            try FileManager.default.removeItem(at: manifest)
            if kind == "directory" { try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false) }
            else if kind == "symlink" {
                let file = root.appendingPathComponent("real.swift")
                try Data("unused".utf8).write(to: file)
                try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: file)
            } else { try #require(mkfifo(manifest.path, 0o600) == 0) }
            let before = try entries(root)
            #expect(AddonToolCommand.run(arguments: arguments(destination, sdk)).exitCode == 1)
            #expect(try entries(root) == before)
        }
    }

    @Test func escapesSDKPathAndDoesNotExecuteShellOrManifest() throws {
        try withWorkspace { root, sdk, destination in
            let strange = root.appendingPathComponent("SDK è \"quote\" \\slash \\(fatalError()) $HOME `touch marker`\nnext")
            try FileManager.default.moveItem(at: sdk, to: strange)
            try #require(AddonToolCommand.run(arguments: arguments(destination, strange)).exitCode == 0)
            let package = try String(contentsOf: destination.appendingPathComponent("Package.swift"), encoding: .utf8)
            #expect(package.contains("\\\"quote\\\""))
            #expect(package.contains("\\\\slash") && package.contains("\\\\(fatalError())"))
            #expect(package.contains("\\nnext") && package.contains("$HOME"))
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("marker").path))
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(".build").path))
        }
    }

    @Test func initHelpDescribesExplicitInputsAndDoesNotWrite() throws {
        let result = AddonToolCommand.run(arguments: ["init", "--help"])
        #expect(result.exitCode == 0)
        for flag in ["--name", "--identifier", "--destination", "--sdk-path"] { #expect(result.output.contains(flag)) }
    }

    @Test func trailingSlashCannotBypassExistingSymlinkRefusal() throws {
        try withWorkspace { root, sdk, destination in
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: sdk)
            let before = try entries(root)
            var input = arguments(destination, sdk)
            input[6] += "/"
            #expect(AddonToolCommand.run(arguments: input).exitCode == 1)
            #expect(try entries(root) == before)
            #expect(try entries(sdk) == ["Package.swift"])
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == sdk.path)
        }
    }

    @Test func writeFailureCleansPreparedFilesAndPreservesSiblingSentinel() throws {
        try withWorkspace { root, _, destination in
            let sentinel = root.appendingPathComponent("sentinel")
            try Data("developer data".utf8).write(to: sentinel)
            let before = try entries(root)
            let file = ScaffoldFile(path: "Sources/Example/Example.swift", data: Data("prepared".utf8))
            #expect(throws: ScaffoldError.self) { try ScaffoldWriter.publish(files: [file, file], to: destination) }
            #expect(try entries(root) == before)
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "developer data")
        }
    }

    @Test(arguments: ["../escape", "/escape", "Sources/../escape", "Sources//escape", "bad\u{0}suffix"])
    func writerRejectsOutputPathTraversalWithoutLeakingPartialTree(path: String) throws {
        try withWorkspace { root, _, destination in
            let before = try entries(root)
            let good = ScaffoldFile(path: "Sources/Example/Example.swift", data: Data("prepared".utf8))
            let bad = ScaffoldFile(path: path, data: Data("escape".utf8))
            #expect(throws: ScaffoldError.self) { try ScaffoldWriter.publish(files: [good, bad], to: destination) }
            #expect(try entries(root) == before)
        }
    }
}
