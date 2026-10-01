//
//  HostFixture.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

struct HostFixture {

    let base     : URL
    let workspace: URL
    let inputs   : URL
    let output   : URL
    let governor  = ResourceGovernor()

    init() throws {
        base      = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        workspace = base.appendingPathComponent("workspace")
        inputs    = base.appendingPathComponent("inputs")
        output    = base.appendingPathComponent("output")

        for directory in [workspace, inputs, output] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspace.path)
    }

    func host() throws -> FileWorkspaceHost {
        try FileWorkspaceHost(directory: workspace, governor: governor)
    }

    func file(
        name    : String,
        contents: String
    ) throws -> URL {
        let url = inputs.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)

        return url
    }
}
