//
//  PluginToolCommand.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation

/// PluginToolCommand is `cascade-plugin`, the manifest checker the development build runs on every
/// first-party manifest before Xcode compiles anything. It decodes each file with the same
/// `PluginManifest` rules Cascade applies when it registers a plugin, reports every file on its own
/// line prefixed by its path, and exits non-zero when any one fails, so a broken manifest stops the
/// build instead of shipping as a plugin that never registers.
enum PluginToolCommand {

    private static let usage      = "Usage: cascade-plugin validate <Manifest.json>...\n" +
        "Validates plugin manifests; only manifest version 2 is accepted."
    private static let disclaimer = "Only manifest syntax and contracts were checked; " +
        "signature and runtime admission are not verified."

    static func run(arguments: [String]) -> PluginToolResult {
        if arguments == ["--help"] || arguments == ["help"] {
            return PluginToolResult(exitCode: 0, output: usage)
        }
        guard arguments.count >= 2, arguments[0] == "validate" else {
            return PluginToolResult(exitCode: 2, output: usage)
        }

        var lines     : [String] = []
        var hasFailed = false
        for path in arguments.dropFirst() {
            do {
                let manifest = try manifest(at: path)
                lines.append("\(path): valid plugin manifest \(manifest.id.rawValue) \(manifest.version)")
            } catch let failure as AddonFailure {
                lines.append("\(path): invalid manifest: \(failure.reason)")
                hasFailed = true
            } catch {
                lines.append("\(path): invalid manifest: unreadable file, invalid JSON or missing required fields.")
                hasFailed = true
            }
        }
        if !hasFailed { lines.append(disclaimer) }

        return PluginToolResult(
            exitCode: hasFailed ? 1 : 0,
            output  : lines.joined(separator: "\n")
        )
    }

    /// manifest reads the version alone before decoding, so a version 1 addon manifest is refused
    /// by name instead of by whichever v1 field the strict v2 decoder happens to trip on first. A
    /// file whose version cannot be read goes on to the full decoder, which says what is wrong.
    private static func manifest(at path: String) throws -> PluginManifest {
        let data     = try readManifest(at: path)
        let declared = try? JSONDecoder().decode(ManifestVersion.self, from: data)

        if let version = declared?.manifestVersion, version != 2 {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Only manifest version 2 is accepted; this file declares version \(version)"
            )
        }

        return try PluginManifest.decode(data)
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

    /// ManifestVersion reads only the version, to refuse other versions by name; it validates nothing.
    private struct ManifestVersion: Decodable {

        let manifestVersion: Int
    }
}
