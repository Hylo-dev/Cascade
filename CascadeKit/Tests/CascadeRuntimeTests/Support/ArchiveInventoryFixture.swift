//
//  ArchiveInventoryFixture.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

/// ArchiveInventoryFixture owns only private temporary roots and a complete fixed two-owner registry.
struct ArchiveInventoryFixture {

    let root          : URL
    let checkpointRoot: URL
    let keyedRoot     : URL
    let archiveRoot   : URL
    let identities    : [VerifiedAddonIdentity]

    var registrations: [StateRegistration] {
        identities.map {
            StateRegistration(identity: $0, maximumSchemaVersion: 1)
        }
    }

    init() throws {
        root           = URL(fileURLWithPath: "/private/tmp/cascade-archive-inventory-\(UUID())")
        checkpointRoot = root.appendingPathComponent("checkpoints")
        keyedRoot      = root.appendingPathComponent("keyed")
        archiveRoot    = root.appendingPathComponent("archives")
        identities     = try ["one", "two"].map {
            VerifiedAddonIdentity(
                publisher: "publisher.inventory",
                addonID  : try #require(AddonID(rawValue: "com.example.inventory.\($0)"))
            )
        }

        for directory in [root, checkpointRoot, keyedRoot, archiveRoot] {
            try FileManager.default.createDirectory(
                at                         : directory,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
        }
    }

    /// make composes the real coordinator with one optional native inventory forwarding seam.
    func make(
        governor: ResourceGovernor,
        observer: any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver()
    ) async throws -> AddonStorageCoordinator {
        try await AddonStorageCoordinator.make(
            checkpointRoot : checkpointRoot,
            keyedRoot      : keyedRoot,
            archiveRoot    : archiveRoot,
            registrations  : registrations,
            governor       : governor,
            archiveObserver: observer
        )
    }

    /// createDirectory makes only a private test-owned directory.
    func createDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at                         : directory,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
    }

    /// createOwner uses the production verified namespace naming without opening a framework store.
    func createOwner(index: Int) throws -> URL {
        let name      = KeyedStorageRecord.hex(KeyedStorageRecord.namespaceDigest(identities[index]))
        let directory = archiveRoot.appendingPathComponent(name)
        try createDirectory(directory)

        return directory
    }

    /// writePrivate creates real private bytes without using a backend or claiming a valid model.
    func writePrivate(
        _ data: Data,
        to url: URL
    ) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func names(in root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}
