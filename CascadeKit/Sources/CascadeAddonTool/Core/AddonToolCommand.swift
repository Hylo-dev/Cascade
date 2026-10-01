//
//  AddonToolCommand.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation

enum AddonToolCommand {

    private static let usage = "Usage: cascade-addon validate <Manifest.json>\n" +
        "Validates manifest v1 (addons) and v2 (plugins).\n" + ScaffoldCommand.usage

    static func run(arguments: [String]) -> AddonToolResult {
        if arguments.first == "init" {
            return ScaffoldCommand.run(arguments: Array(arguments.dropFirst()))
        }
        if arguments == ["--help"] || arguments == ["help"] {
            return AddonToolResult(exitCode: 0, output: usage)
        }
        guard arguments.count == 2, arguments[0] == "validate" else {
            return AddonToolResult(exitCode: 2, output: usage)
        }

        do {
            let data       = try readManifest(at: arguments[1])
            let disclaimer = "Only manifest syntax and contracts were checked; signature and runtime admission are not verified."

            if (try? JSONDecoder().decode(ManifestVersion.self, from: data))?.manifestVersion == 2 {
                let manifest = try PluginManifest.decode(data)

                return AddonToolResult(
                    exitCode: 0,
                    output  : "Plugin manifest valid: \(manifest.id.rawValue) \(manifest.version)\n" + disclaimer
                )
            }

            let manifest = try AddonManifest.decode(data)

            return AddonToolResult(
                exitCode: 0,
                output  : "Manifest valid: \(manifest.id.rawValue) \(manifest.version)\n" + disclaimer
            )
        } catch let failure as AddonFailure {
            return AddonToolResult(exitCode: 1, output: "Invalid manifest: \(failure.reason)")
        } catch {
            return AddonToolResult(
                exitCode: 1,
                output  : "Invalid manifest: unreadable file, invalid JSON or missing required fields."
            )
        }
    }

    /// readManifest opens nonblocking before checking the same descriptor's
    /// file type, so a FIFO/device cannot make validation wait for an unbounded
    /// input stream.
    private static func readManifest(at path: String) throws -> Data {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Cannot open the manifest file."
            )
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The manifest must be a regular file."
            )
        }

        let maximumBytes = 65_536
        guard info.st_size >= 0, info.st_size <= maximumBytes else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Manifest exceeds 64 KiB."
            )
        }

        // Read one extra byte to detect growth after fstat; never load the entire
        // file before the contracts' byte limit is enforced.
        var data = Data()
        while data.count <= maximumBytes {
            guard let chunk = try handle.read(upToCount: maximumBytes + 1 - data.count),
                  !chunk.isEmpty
            else { break }

            data.append(chunk)
        }

        guard data.count <= maximumBytes else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Manifest exceeds 64 KiB."
            )
        }

        return data
    }

    /// ManifestVersion reads only the version, to pick the decoder; it validates nothing.
    private struct ManifestVersion: Decodable {

        let manifestVersion: Int
    }
}
