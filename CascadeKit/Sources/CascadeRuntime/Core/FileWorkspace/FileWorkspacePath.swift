//
//  FileWorkspacePath.swift
//  CascadeKit
//

import Darwin
import Foundation

/// FileWorkspacePath validates the final namespace component without accepting a link target.
enum FileWorkspacePath {

    static func validatePrivateDirectory(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0) else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(),
              info.st_mode & 0o7777 == 0o700
        else {
            throw CocoaError(.fileReadNoPermission)
        }
    }

    static func validateRegularFile(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid()
        else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }
}
