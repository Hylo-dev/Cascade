//
//  Probe.swift
//  Cascade
//

import Darwin
import Foundation
import SwiftData

/// ArchiveRecord stores one generation and its two ordinary BLOBs in the same save.
/// This disposable schema deliberately avoids external storage and relationships.
@Model
final class ArchiveRecord {
    @Attribute(.unique)
    var identity: String

    var generation     : Int
    var publicationData: Data
    var rasterData     : Data

    init(
        identity       : String,
        generation     : Int,
        publicationData: Data,
        rasterData     : Data
    ) {
        self.identity        = identity
        self.generation      = generation
        self.publicationData = publicationData
        self.rasterData      = rasterData
    }
}

/// ProbeFailure reports a failed observation rather than manufacturing passing metrics.
private enum ProbeFailure: Error {
    case invalidArguments
    case unsafeFixture
    case mainThreadWork
    case unexpectedRecord
    case mismatchedGeneration
    case unavailableMetrics(Int32)
}

/// ProbeMode fixes the workload; callers cannot request an unbounded update count or payload.
private enum ProbeMode: String {
    case initialize
    case readInitial
    case rollback
    case replace
    case readReplacement
    case unsaved
    case repeatUpdates
    case readRepeated
}

/// GenerationFixture supplies deterministic bytes so every reopened byte is checked.
private struct GenerationFixture {
    let generation      : Int
    let publicationBytes: Int
    let rasterBytes     : Int
    let fill            : UInt8

    static let initial = GenerationFixture(
        generation      : 1,
        publicationBytes: 4_096,
        rasterBytes     : 1_048_576,
        fill            : 1
    )
    static let replacement = GenerationFixture(
        generation      : 3,
        publicationBytes: 262_144,
        rasterBytes     : 4_000_000,
        fill            : 3
    )
    static let unsaved = GenerationFixture(
        generation      : 4,
        publicationBytes: 16_384,
        rasterBytes     : 4_194_304,
        fill            : 4
    )
}

/// ProcessFootprint samples this process's current and lifetime peak physical footprint.
/// The pointer rebinding is confined to Darwin's fixed-size output ABI: the local value
/// owns the buffer for the synchronous call and cannot escape to SwiftData or another task.
private struct ProcessFootprint: Codable {
    let currentBytes     : UInt64
    let lifetimePeakBytes: UInt64

    static func read() throws -> ProcessFootprint {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
            usagePointer.withMemoryRebound(
                to      : rusage_info_t?.self,
                capacity: 1
            ) { reboundPointer in
                proc_pid_rusage(
                    getpid(),
                    RUSAGE_INFO_V4,
                    reboundPointer
                )
            }
        }
        guard result == 0 else { throw ProbeFailure.unavailableMetrics(errno) }
        return ProcessFootprint(
            currentBytes     : usage.ri_phys_footprint,
            lifetimePeakBytes: usage.ri_lifetime_max_phys_footprint
        )
    }
}

/// ManagedFile records logical file length and permission bits, not APFS allocation.
private struct ManagedFile: Codable {
    let name       : String
    let bytes      : UInt64
    let permissions: String
}

/// ProbeObservation contains one process's correctness and resource observations.
private struct ProbeObservation: Codable {
    let mode                  : String
    let generation            : Int
    let publicationBytes      : Int
    let rasterBytes           : Int
    let hasUnsavedChanges      : Bool
    let saves                 : Int
    let openedOffMainThread    : Bool
    let operatedOffMainThread  : Bool
    let wallTimeMilliseconds   : Double
    let processFootprint       : ProcessFootprint
    let files                 : [ManagedFile]
    let operatingSystem        : String
    let compiledDeploymentFloor: String
    let macOS14RuntimeQualified : Bool
}

/// ArchiveWorker owns its independent context on SwiftData's serial executor.
/// Creation runs in a detached task, and model objects never cross the actor boundary.
private actor ArchiveWorker: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor : any ModelExecutor
    private let root             : URL

    init(root: URL) throws {
        guard !Thread.isMainThread else { throw ProbeFailure.mainThreadWork }
        self.root = root
        let schema = Schema([ArchiveRecord.self])
        let configuration = ModelConfiguration(
            "ArchiveProbe",
            schema          : schema,
            url             : root.appendingPathComponent("archive.store"),
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for           : schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.undoManager = nil
        modelContainer = container
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    /// operate checks complete deterministic payloads before and after each bounded mutation.
    /// There is one explicit save for each generation, with no await between its fields.
    func operate(
        mode       : ProbeMode,
        startedAt  : UInt64
    ) throws -> ProbeObservation {
        guard !Thread.isMainThread else { throw ProbeFailure.mainThreadWork }
        let context = modelContext
        let rows = try context.fetch(FetchDescriptor<ArchiveRecord>())
        let row: ArchiveRecord
        var saves = 0
        var expected = GenerationFixture.initial
        var expectsChanges = false

        if mode == .initialize {
            guard rows.isEmpty else { throw ProbeFailure.unexpectedRecord }
            row = ArchiveRecord(
                identity       : "fixture-owner",
                generation     : expected.generation,
                publicationData: Data(
                    repeating: expected.fill,
                    count    : expected.publicationBytes
                ),
                rasterData     : Data(
                    repeating: expected.fill,
                    count    : expected.rasterBytes
                )
            )
            context.insert(row)
            try context.save()
            saves = 1
        } else {
            guard rows.count == 1, let existingRow = rows.first else {
                throw ProbeFailure.unexpectedRecord
            }
            row = existingRow
            switch mode {
            case .readInitial:
                break
            case .rollback:
                try validate(
                    row     : row,
                    expected: .initial
                )
                assign(
                    fixture: .replacement,
                    to     : row
                )
                guard context.hasChanges else { throw ProbeFailure.mismatchedGeneration }
                context.rollback()
            case .replace:
                try validate(
                    row     : row,
                    expected: .initial
                )
                expected = .replacement
                assign(
                    fixture: expected,
                    to     : row
                )
                try context.save()
                saves = 1
            case .readReplacement:
                expected = .replacement
            case .unsaved:
                try validate(
                    row     : row,
                    expected: .replacement
                )
                expected = .unsaved
                assign(
                    fixture: expected,
                    to     : row
                )
                expectsChanges = true
            case .repeatUpdates:
                try validate(
                    row     : row,
                    expected: .initial
                )
                for generation in 10..<110 {
                    expected = repeatedFixture(generation)
                    assign(
                        fixture: expected,
                        to     : row
                    )
                    try context.save()
                    saves += 1
                }
            case .readRepeated:
                expected = repeatedFixture(109)
            case .initialize:
                throw ProbeFailure.invalidArguments
            }
        }

        try validate(
            row     : row,
            expected: expected
        )
        guard context.hasChanges == expectsChanges else { throw ProbeFailure.mismatchedGeneration }
        let files = try inventory()
        let footprint = try ProcessFootprint.read()
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        return ProbeObservation(
            mode                   : mode.rawValue,
            generation             : row.generation,
            publicationBytes       : row.publicationData.count,
            rasterBytes            : row.rasterData.count,
            hasUnsavedChanges      : context.hasChanges,
            saves                  : saves,
            openedOffMainThread    : true,
            operatedOffMainThread  : true,
            wallTimeMilliseconds   : Double(elapsed) / 1_000_000,
            processFootprint       : footprint,
            files                  : files,
            operatingSystem        : ProcessInfo.processInfo.operatingSystemVersionString,
            compiledDeploymentFloor: "macOS 14.0",
            macOS14RuntimeQualified : false
        )
    }

    /// repeatedFixture keeps each of the 100 updates at the same payload size.
    private func repeatedFixture(_ generation: Int) -> GenerationFixture {
        GenerationFixture(
            generation      : generation,
            publicationBytes: 4_096,
            rasterBytes     : 1_048_576,
            fill            : UInt8(generation)
        )
    }

    /// assign changes the complete generation pair without saving an intermediate field.
    private func assign(
        fixture: GenerationFixture,
        to row : ArchiveRecord
    ) {
        row.generation = fixture.generation
        row.publicationData = Data(
            repeating: fixture.fill,
            count    : fixture.publicationBytes
        )
        row.rasterData = Data(
            repeating: fixture.fill,
            count    : fixture.rasterBytes
        )
    }

    /// validate checks the whole pair; matching lengths alone would miss torn or stale payloads.
    private func validate(
        row     : ArchiveRecord,
        expected: GenerationFixture
    ) throws {
        guard row.identity == "fixture-owner",
              row.generation == expected.generation,
              row.publicationData.count == expected.publicationBytes,
              row.rasterData.count == expected.rasterBytes,
              row.publicationData.allSatisfy({ $0 == expected.fill }),
              row.rasterData.allSatisfy({ $0 == expected.fill }) else {
            throw ProbeFailure.mismatchedGeneration
        }
    }

    /// inventory checks each actual member without following symlinks before reporting its size.
    /// No framework files are removed or truncated by this probe.
    private func inventory() throws -> [ManagedFile] {
        let entries = try FileManager.default.contentsOfDirectory(
            at                       : root,
            includingPropertiesForKeys: nil
        )
        guard entries.count <= 3 else { throw ProbeFailure.unsafeFixture }
        return try entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { entry in
            guard ["archive.store", "archive.store-wal", "archive.store-shm"].contains(entry.lastPathComponent) else {
                throw ProbeFailure.unsafeFixture
            }
            var information = stat()
            guard lstat(
                entry.path,
                &information
            ) == 0,
                  information.st_mode & S_IFMT == S_IFREG,
                  information.st_mode & 0o777 == 0o600,
                  information.st_uid == getuid(),
                  information.st_nlink == 1,
                  information.st_size >= 0 else {
                throw ProbeFailure.unsafeFixture
            }
            return ManagedFile(
                name       : entry.lastPathComponent,
                bytes      : UInt64(information.st_size),
                permissions: "0600"
            )
        }
    }
}

/// Probe runs exactly one fixture stage in one process and emits one compact JSON object.
/// The shell harness supplies a fresh private directory and owns the stage ordering.
@main
private struct Probe {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count == 3,
                  let mode = ProbeMode(rawValue: arguments[1]) else {
                throw ProbeFailure.invalidArguments
            }
            let root = URL(fileURLWithPath: arguments[2])
            try validateFixtureRoot(root)
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let observation = try await Task.detached {
                let worker = try ArchiveWorker(root: root)
                return try await worker.operate(
                    mode     : mode,
                    startedAt: startedAt
                )
            }.value
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(observation)
            FileHandle.standardOutput.write(encoded)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Probe failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// validateFixtureRoot confines the executable to harness-created private temporary stores.
    /// It is fixture hygiene, not the production storage service's descriptor-relative sandbox.
    private static func validateFixtureRoot(_ root: URL) throws {
        guard root.path.hasPrefix("/private/tmp/cascade-swiftdata-archive-"),
              ["consistency", "retention"].contains(root.lastPathComponent),
              root.pathComponents.count == 5 else {
            throw ProbeFailure.unsafeFixture
        }
        for entry in [root, root.appendingPathComponent("archive.store")] {
            var information = stat()
            let isRoot = entry == root
            guard lstat(
                entry.path,
                &information
            ) == 0,
                  information.st_uid == getuid(),
                  information.st_mode & S_IFMT == (isRoot ? S_IFDIR : S_IFREG),
                  information.st_mode & 0o777 == (isRoot ? 0o700 : 0o600),
                  isRoot || information.st_nlink == 1 else {
                throw ProbeFailure.unsafeFixture
            }
        }
    }
}
