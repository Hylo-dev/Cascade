//
//  Fixture.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

struct Fixture {

    let root       : URL
    let inputs     : URL
    let persistence: FoundationFileWorkspacePersistence
    let owner      : AddonID
    let governor   : ResourceGovernor
    let lifetime   : FileWorkspaceNamespaceLifetime

    var manifestURL: URL { root.appendingPathComponent("manifest.json") }

    init(
        owner   : AddonID,
        governor: ResourceGovernor = ResourceGovernor()
    ) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        root          = base.appendingPathComponent("workspace")
        inputs        = base.appendingPathComponent("inputs")
        self.owner    = owner
        self.governor = governor

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)

        persistence = FoundationFileWorkspacePersistence(directory: root)
        lifetime    = FileWorkspaceNamespaceLifetime(
            directory: root,
            owner    : owner,
            resources: governor
        )
    }

    func folder(name: String) throws -> URL {
        let url = inputs.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(
        in directory: URL? = nil,
        name        : String,
        contents    : String
    ) throws -> URL {
        try file(
            in  : directory,
            name: name,
            data: Data(contents.utf8)
        )
    }

    func file(
        in directory: URL? = nil,
        name        : String,
        data        : Data
    ) throws -> URL {
        let url = (directory ?? inputs).appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func store(
        persistence: (any FileWorkspacePersisting)? = nil,
        lifetime   : FileWorkspaceNamespaceLifetime? = nil,
        restore    : Bool = true
    ) async throws -> FileWorkspaceStore {
        let store = FileWorkspaceStore(
            directory  : root,
            owner      : owner,
            resources  : governor,
            persistence: persistence ?? self.persistence,
            references : FoundationFileReferenceResolver(),
            lifetime   : lifetime ?? self.lifetime
        )
        if lifetime == nil, restore { try await store.restore() }

        return store
    }
}
