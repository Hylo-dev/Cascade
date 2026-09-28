//
//  FileWorkspacePresentationRuntimeTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite
struct FileWorkspacePresentationRuntimeTests {
    @Test
    func actionAuthorizationUsesThePublishedWorkspaceDescriptor() throws {
        let fixture = try ActionFixture()
        let base = try fixture.context()
        let presentation = try workspace(
            thumbnail: nil,
            action: ActionDescriptor(
                id     : "pause",
                label  : "Pause",
                payload: Data([7])
            )
        )
        let document = try ContentDocument(
            schemaVersion     : 3,
            root              : .fileWorkspace(presentation),
            accessibilityLabel: "File shelf",
            privacy           : .sensitive,
            assets            : []
        )
        let content = try PresentationSet(
            widget         : document,
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
        let publication = try Publication(
            id         : fixture.publicationID,
            revision   : 1,
            kind       : .widget,
            content    : content,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(60),
            stalePolicy: .retainMarked
        )
        let context = ActionAuthorizer.Context(
            installed  : base.installed,
            resolution : base.resolution,
            featureID  : base.featureID,
            publication: publication,
            eligibility: .available
        )

        try ActionAuthorizer.validate(
            fixture.request(input: Data([7])),
            context: context,
            at     : fixture.wall
        )
        #expect(throws: ActionAuthorizer.Failure.payloadMismatch) {
            try ActionAuthorizer.validate(
                fixture.request(input: Data([8])),
                context: context,
                at     : fixture.wall
            )
        }
    }

    @Test
    func archiveRemappingRewritesWorkspaceThumbnailsAndPreservesActions() throws {
        let fixture = try ActionFixture()
        let descriptor = try ActionDescriptor(
            id     : "pause",
            label  : "Pause",
            payload: Data([7])
        )
        let presentation = try workspace(
            thumbnail: "old-thumbnail",
            action   : descriptor
        )
        let document = try ContentDocument(
            schemaVersion     : 3,
            root              : .fileWorkspace(presentation),
            accessibilityLabel: "File shelf",
            privacy           : .sensitive,
            assets            : ["old-thumbnail"]
        )
        let publication = try Publication(
            id         : fixture.publicationID,
            revision   : 1,
            kind       : .widget,
            content    : PresentationSet(
                widget         : document,
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            ),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(60),
            stalePolicy: .retainMarked
        )

        let remapped = try RuntimeArchiveRemapping.publication(
            publication,
            aliases: ["old-thumbnail": "restored-thumbnail"]
        )
        #expect(remapped.content?.widget?.assets == ["restored-thumbnail"])
        #expect(
            remapped.content?.widget?.root.fileWorkspace?.snapshot.entries.first?.thumbnailAssetID
                == "restored-thumbnail"
        )
        #expect(remapped.content?.widget?.root.fileWorkspace?.actions.first?.descriptor == descriptor)
        #expect(throws: AddonFailure.self) {
            try RuntimeArchiveRemapping.publication(
                publication,
                aliases: [:]
            )
        }
    }

    private func workspace(
        thumbnail: String?,
        action   : ActionDescriptor
    ) throws -> FileWorkspacePresentation {
        let entry = try FileWorkspaceEntry(
            id              : UUID(),
            name            : "Report.pdf",
            typeIdentifier  : "com.adobe.pdf",
            availability    : .available,
            ownership       : .externalReference,
            thumbnailAssetID: thumbnail
        )
        return try FileWorkspacePresentation(
            snapshot: FileWorkspaceSnapshot(
                revision  : 1,
                entries   : [entry],
                totalCount: 1,
                nextCursor: nil,
                jobs      : []
            ),
            mode            : .deck,
            selectedEntryIDs: [],
            formats         : [],
            selectedFormatID: nil,
            actions         : [
                FileWorkspaceActionBinding(
                    role      : .openList,
                    descriptor: action
                ),
            ]
        )
    }
}
