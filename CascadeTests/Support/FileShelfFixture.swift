//
//  FileShelfFixture.swift
//  Cascade
//

import CascadeContracts
import CascadeRuntime
import Foundation
import AppKit
import SwiftUI
import Testing
@testable import Cascade

struct FileShelfFixture {

    let root  : URL
    let shelf : URL
    let input : URL
    let output: URL
    let host  : FileWorkspaceHost

    init() throws {
        root   = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        shelf  = root.appendingPathComponent("shelf")
        input  = root.appendingPathComponent("input")
        output = root.appendingPathComponent("output")

        try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shelf.path)

        host = try FileWorkspaceHost(directory: shelf, governor: ResourceGovernor())
    }

    func file(
        name    : String,
        contents: String
    ) throws -> URL {
        let url = input.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)

        return url
    }
}
