//
//  FileWorkspaceContentTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct FileWorkspaceContentTests {

    @Test
    func duplicateDescriptorsAreRejected() throws {
        let fixture = try WorkspaceContractFixture()

        #expect(throws: (any Error).self) {
            try FileWorkspacePresentation(
                snapshot        : fixture.snapshot,
                mode            : .deck,
                selectedEntryIDs: [],
                formats         : [],
                selectedFormatID: nil,
                actions         : [
                    fixture.openList,
                    FileWorkspaceActionBinding(
                        role      : .closeList,
                        descriptor: fixture.openList.descriptor
                    ),
                ]
            )
        }
    }

    @Test
    func hostileFieldsTargetsAndBindingBudgetsAreRejected() throws {
        let fixture = try WorkspaceContractFixture()
        let data    = try JSONEncoder().encode(fixture.presentation)
        var object  = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["filesystemPath"] = "/private/file"

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                FileWorkspacePresentation.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        #expect(throws: (any Error).self) {
            try FileWorkspaceActionBinding(
                role      : .select,
                descriptor: ActionDescriptor(id: "select-missing", label: "Select")
            )
        }
        #expect(throws: (any Error).self) {
            try FileWorkspaceActionBinding(
                role      : .openList,
                entryID   : fixture.entry.id,
                descriptor: ActionDescriptor(id: "open-targeted", label: "Open")
            )
        }

        let tooMany = try (0...64).map { index in
            try FileWorkspaceActionBinding(
                role      : .openList,
                descriptor: ActionDescriptor(id: "open-\(index)", label: "Open")
            )
        }
        #expect(throws: (any Error).self) {
            try FileWorkspacePresentation(
                snapshot        : fixture.snapshot,
                mode            : .deck,
                selectedEntryIDs: [],
                formats         : [],
                selectedFormatID: nil,
                actions         : tooMany
            )
        }
    }

    @Test
    func targetsMustResolveInsideThePresentedBoundedValues() throws {
        let fixture = try WorkspaceContractFixture()

        #expect(throws: (any Error).self) {
            try FileWorkspacePresentation(
                snapshot        : fixture.snapshot,
                mode            : .list,
                selectedEntryIDs: [UUID()],
                formats         : [],
                selectedFormatID: nil,
                actions         : []
            )
        }
        #expect(throws: (any Error).self) {
            try FileWorkspacePresentation(
                snapshot        : fixture.snapshot,
                mode            : .conversion,
                selectedEntryIDs: [fixture.entry.id],
                formats         : [],
                selectedFormatID: "pdf",
                actions         : []
            )
        }
        #expect(throws: (any Error).self) {
            try FileWorkspacePresentation(
                snapshot        : fixture.snapshot,
                mode            : .list,
                selectedEntryIDs: [],
                formats         : [],
                selectedFormatID: nil,
                actions         : [
                    FileWorkspaceActionBinding(
                        role      : .remove,
                        entryID   : UUID(),
                        descriptor: try ActionDescriptor(id: "remove-other", label: "Remove")
                    ),
                ]
            )
        }
    }
}
