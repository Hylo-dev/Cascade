//
//  FileWorkspaceContractTests.swift
//  Cascade
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite struct FileWorkspaceContractTests {
    private func entry(id: UUID = UUID()) throws -> FileWorkspaceEntry {
        try FileWorkspaceEntry(
            id              : id,
            name            : "Photo.jpg",
            typeIdentifier  : "public.jpeg",
            availability    : .available,
            ownership       : .externalReference,
            thumbnailAssetID: "thumb-1"
        )
    }

    private func job(id: UUID = UUID(), results: [UUID] = []) throws -> FileConversionJobSnapshot {
        try FileConversionJobSnapshot(
            id       : id,
            state    : .completed,
            progress : nil,
            resultIDs: results
        )
    }

    private func snapshot(
        entries: [FileWorkspaceEntry] = [],
        jobs   : [FileConversionJobSnapshot] = [],
        total  : Int = 0,
        cursor : String? = nil
    ) throws -> FileWorkspaceSnapshot {
        try FileWorkspaceSnapshot(
            revision  : UInt64.max,
            entries   : entries,
            totalCount: total,
            nextCursor: cursor,
            jobs      : jobs
        )
    }

    @Test func roundTripsMaximumPageWithLargeTotalAndCursor() throws {
        let entries = try (0..<32).map { _ in try entry() }
        let value = try snapshot(entries: entries, total: Int.max, cursor: "page-2")
        #expect(try FileWorkspaceSnapshot.decode(value.encode()) == value)
        #expect(value.totalCount == Int.max)
        #expect(value.nextCursor == "page-2")
    }

    @Test func rejectsCollectionOverflowAndDuplicateIDsBeforeElements() throws {
        let entries = try (0..<33).map { _ in try entry() }
        #expect(throws: AddonFailure.self) { try snapshot(entries: entries, total: 33) }
        let repeated = try entry()
        #expect(throws: AddonFailure.self) { try snapshot(entries: [repeated, repeated], total: 2) }
        let repeatedJob = try job()
        #expect(throws: AddonFailure.self) { try snapshot(jobs: [repeatedJob, repeatedJob]) }
        #expect(throws: AddonFailure.self) { try job(results: [repeated.id, repeated.id]) }
        let raw = try JSONSerialization.data(withJSONObject: [
            "revision": 0,
            "entries": Array(repeating: [:], count: 33),
            "totalCount": 33,
            "jobs": [],
        ])
        do {
            _ = try FileWorkspaceSnapshot.decode(raw)
            Issue.record("Expected entry budget failure")
        } catch let error as AddonFailure {
            #expect(error.code == .invalidPayload)
        }
        let tooManyJobs = try JSONSerialization.data(withJSONObject: [
            "revision": 0,
            "entries": [],
            "totalCount": 0,
            "jobs": Array(repeating: [:], count: 33),
        ])
        do {
            _ = try FileWorkspaceSnapshot.decode(tooManyJobs)
            Issue.record("Expected job budget failure")
        } catch let error as AddonFailure {
            #expect(error.code == .invalidPayload)
        }
    }

    @Test func rejectsInvalidStringsTotalsAndProgress() throws {
        for invalid in ["", "  ", String(repeating: "é", count: 2049)] {
            #expect(throws: AddonFailure.self) {
                try FileWorkspaceEntry(
                    id              : UUID(), name: invalid, typeIdentifier: "public.jpeg",
                    availability    : .available, ownership: .managed, thumbnailAssetID: nil
                )
            }
            #expect(throws: AddonFailure.self) {
                try FileConversionFormat(id: "jpeg", label: invalid, outputTypeIdentifier: "public.jpeg")
            }
        }
        for invalid in ["", "é", String(repeating: "a", count: 129)] {
            #expect(throws: AddonFailure.self) {
                try FileConversionFormat(id: "jpeg", label: "JPEG", outputTypeIdentifier: invalid)
            }
        }
        #expect(throws: AddonFailure.self) {
            try FileConversionFormat(id: "../jpeg", label: "JPEG", outputTypeIdentifier: "public.jpeg")
        }
        #expect(throws: AddonFailure.self) {
            try FileWorkspaceEntry(
                id              : UUID(), name: "Photo", typeIdentifier: "public.jpeg",
                availability    : .available, ownership: .managed,
                thumbnailAssetID: "file:///Users/example/photo.jpg"
            )
        }
        #expect(throws: AddonFailure.self) { try snapshot(total: -1) }
        for invalid in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            #expect(throws: AddonFailure.self) {
                try FileConversionJobSnapshot(id: UUID(), state: .running, progress: invalid, resultIDs: [])
            }
        }
    }

    @Test func rejectsUnknownFieldsAtEveryLevelAndInvalidRawProgress() throws {
        let original = try snapshot(entries: [entry()], jobs: [job()], total: 1)
        let data = try original.encode()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for field in ["root", "entry", "job"] {
            var changed = object
            switch field {
            case "entry":
                var entries = try #require(changed["entries"] as? [[String: Any]])
                entries[0]["path"] = "/private/file"
                changed["entries"] = entries
            case "job":
                var jobs = try #require(changed["jobs"] as? [[String: Any]])
                jobs[0]["error"] = "private"
                changed["jobs"] = jobs
            default: changed["future"] = true
            }
            #expect(throws: AddonFailure.self) {
                try FileWorkspaceSnapshot.decode(JSONSerialization.data(withJSONObject: changed))
            }
        }
        var jobs = try #require(object["jobs"] as? [[String: Any]])
        jobs[0]["progress"] = 2.0
        object["jobs"] = jobs
        #expect(throws: AddonFailure.self) {
            try FileWorkspaceSnapshot.decode(JSONSerialization.data(withJSONObject: object))
        }
        jobs[0]["progress"] = "NaN"
        object["jobs"] = jobs
        #expect(throws: (any Error).self) {
            try FileWorkspaceSnapshot.decode(JSONSerialization.data(withJSONObject: object))
        }
        jobs[0]["progress"] = "Infinity"
        object["jobs"] = jobs
        #expect(throws: (any Error).self) {
            try FileWorkspaceSnapshot.decode(JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func rejectsOversizedBodyBeforeJSONParsing() throws {
        #expect(throws: AddonFailure.self) {
            try FileWorkspaceSnapshot.decode(Data(repeating: 32, count: 65_537))
        }
    }

    @Test func validatesCursorAndCommandIDs() throws {
        for cursor in ["", String(repeating: "é", count: 65)] {
            #expect(throws: AddonFailure.self) { try snapshot(cursor: cursor) }
            #expect(throws: AddonFailure.self) { try FileWorkspaceCommand.list(cursor: cursor).validate() }
        }
        let id = UUID()
        for command in [
            FileWorkspaceCommand.remove(ids: [], revision: 0),
            .remove(ids: [id, id], revision: 0),
            .remove(ids: Array(repeating: id, count: 33), revision: 0),
            .convert(ids: [id, id], formatID: "jpeg", revision: 0),
            .convert(ids: [id], formatID: "../jpeg", revision: 0),
        ] {
            #expect(throws: AddonFailure.self) { try command.validate() }
            #expect(throws: AddonFailure.self) { try JSONEncoder().encode(command) }
        }
    }

    @Test func taggedCommandsRoundTripAndRejectWrongKindFields() throws {
        let id = UUID()
        for command in [
            FileWorkspaceCommand.list(cursor: nil),
            .remove(ids: [id], revision: 1),
            .relink(id: id),
            .convert(ids: [id], formatID: "jpeg", revision: 2),
            .cancel(jobID: id),
        ] {
            let data = try JSONEncoder().encode(command)
            #expect(try JSONDecoder().decode(FileWorkspaceCommand.self, from: data) == command)
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["unexpected"] = true
            #expect(throws: AddonFailure.self) {
                try JSONDecoder().decode(
                    FileWorkspaceCommand.self,
                    from: JSONSerialization.data(withJSONObject: object)
                )
            }
        }
        let wrong = Data("{\"kind\":\"cancel\",\"jobID\":\"\(id.uuidString)\",\"ids\":[]}".utf8)
        #expect(throws: AddonFailure.self) {
            try JSONDecoder().decode(FileWorkspaceCommand.self, from: wrong)
        }
        let duplicateIDs = Data("{\"kind\":\"remove\",\"ids\":[\"\(id.uuidString)\",\"\(id.uuidString)\"],\"revision\":0}".utf8)
        #expect(throws: AddonFailure.self) {
            try JSONDecoder().decode(FileWorkspaceCommand.self, from: duplicateIDs)
        }
    }
}
