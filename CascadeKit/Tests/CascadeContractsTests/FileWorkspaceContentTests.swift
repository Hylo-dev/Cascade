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
    func schemaThreeIsRequiredAndPreservesWorkspaceAssetsAndActions() throws {
        let fixture = try WorkspaceContractFixture()
        let node = try ContentNode.fileWorkspace(fixture.presentation)

        for schema in [1, 2] {
            #expect(throws: (any Error).self) {
                try ContentDocument(
                    schemaVersion     : schema,
                    root              : node,
                    accessibilityLabel: "File shelf",
                    privacy           : .sensitive,
                    assets            : ["thumb-one"]
                )
            }
        }

        let document = try ContentDocument(
            schemaVersion     : 3,
            root              : node,
            accessibilityLabel: "File shelf",
            privacy           : .sensitive,
            assets            : ["thumb-one"],
            glassLights       : []
        )
        #expect(try ContentDocument.decode(document.encode()) == document)

        #expect(throws: (any Error).self) {
            try ContentDocument(
                schemaVersion     : 3,
                root              : node,
                accessibilityLabel: "File shelf",
                privacy           : .sensitive,
                assets            : []
            )
        }

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
        let data = try JSONEncoder().encode(fixture.presentation)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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

    @Test
    func contextRequiresExplicitlyNegotiatedSchemaThreeForFutureTimelineContent() throws {
        let fixture = try WorkspaceContractFixture()
        let owner = try #require(AddonID(rawValue: "com.example.files"))
        let id = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let document = try ContentDocument(
            schemaVersion     : 3,
            root              : .fileWorkspace(fixture.presentation),
            accessibilityLabel: "File shelf",
            privacy           : .sensitive,
            assets            : ["thumb-one"]
        )
        let presentation = try PresentationSet(
            widget         : document,
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
        let publication = try Publication(
            id         : id,
            revision   : 1,
            kind       : .widget,
            content    : nil,
            timeline   : [ScheduledEntry(date: Date().addingTimeInterval(30), content: presentation)],
            expiresAt  : Date().addingTimeInterval(60),
            stalePolicy: .remove
        )
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications : [publication],
            operations   : [],
            completion   : nil,
            checkpoint   : nil
        )

        #expect(throws: (any Error).self) {
            try output.validateContext(
                authenticatedAddonID: owner,
                expectedCompletion  : nil,
                previousRevisions   : [:]
            )
        }
        try output.validateContext(
            authenticatedAddonID: owner,
            expectedCompletion  : nil,
            previousRevisions   : [:],
            contentSchemas      : [1, 2, 3]
        )
    }
}
