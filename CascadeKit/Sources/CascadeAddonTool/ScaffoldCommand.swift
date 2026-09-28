//
//  ScaffoldCommand.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation

enum ScaffoldCommand {
    static let usage = "Usage: cascade-addon init --name <Name> --identifier <reverse.dns.id> --destination <new-directory> --sdk-path <CascadeKit-package>\nCreates a source-only library package; no native bootstrap, signing or installation is performed."

    static func run(arguments: [String]) -> AddonToolResult {
        if arguments == ["--help"] { return AddonToolResult(exitCode: 0, output: usage) }
        let flags: Set<String> = ["--name", "--identifier", "--destination", "--sdk-path"]
        guard arguments.count == 8 else { return AddonToolResult(exitCode: 2, output: usage) }
        var values: [String: String] = [:]
        for offset in stride(from: 0, to: arguments.count, by: 2) {
            let flag = arguments[offset], value = arguments[offset + 1]
            guard flags.contains(flag), values[flag] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                return AddonToolResult(exitCode: 2, output: usage)
            }
            values[flag] = value
        }
        guard let name = values["--name"], let identifier = values["--identifier"],
              let destinationPath = values["--destination"], let sdkPath = values["--sdk-path"] else {
            return AddonToolResult(exitCode: 2, output: usage)
        }
        do {
            guard name.utf8.count <= 64,
                  name.range(of: "^[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil,
                  !name.contains("\0") else {
                throw ScaffoldError("Name must be an ASCII letter followed by alphanumerics, at most 64 bytes.")
            }
            guard !identifier.contains("\0"), let id = AddonID(rawValue: identifier) else {
                throw ScaffoldError("Identifier must be a valid reverse-DNS addon ID.")
            }
            guard !destinationPath.contains("\0"), !sdkPath.contains("\0") else {
                throw ScaffoldError("Paths must not contain NUL bytes.")
            }
            // Resolve neither symlinks nor shell syntax. The writer pins the parent
            // descriptor and exclusively renames into the final path component.
            let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
            let sdk = URL(fileURLWithPath: sdkPath).standardizedFileURL
            try validateSDK(sdk)
            let files = try ScaffoldTemplates.files(name: name, id: id, sdkPath: sdk.path)
            try ScaffoldWriter.publish(files: files, to: destination)
            return AddonToolResult(exitCode: 0, output: "Created source package for \(id.rawValue).\nNative bootstrap, signing and runtime admission are not provided by this scaffold.")
        } catch let failure as ScaffoldError {
            return AddonToolResult(exitCode: 1, output: "Cannot create source package: \(failure.message)")
        } catch {
            return AddonToolResult(exitCode: 1, output: "Cannot create source package: invalid contracts or filesystem failure.")
        }
    }

    private static func validateSDK(_ sdk: URL) throws {
        let directory = open(sdk.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NONBLOCK)
        guard directory >= 0 else { throw ScaffoldError("SDK path must name an existing package directory.") }
        defer { close(directory) }
        var info = stat()
        guard fstatat(directory, "Package.swift", &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw ScaffoldError("SDK directory must contain a regular, non-symlink Package.swift.")
        }
    }
}

struct ScaffoldError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
