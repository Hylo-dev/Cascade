//
//  WorkspaceContractFixture.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

struct WorkspaceContractFixture {
    let entry       : FileWorkspaceEntry
    let snapshot    : FileWorkspaceSnapshot
    let openList    : FileWorkspaceActionBinding
    let presentation: FileWorkspacePresentation

    init() throws {
        entry = try FileWorkspaceEntry(
            id              : UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            name            : "Quarterly report.pdf",
            typeIdentifier  : "com.adobe.pdf",
            availability    : .available,
            ownership       : .externalReference,
            thumbnailAssetID: "thumb-one"
        )
        snapshot = try FileWorkspaceSnapshot(
            revision  : 7,
            entries   : [entry],
            totalCount: 1,
            nextCursor: nil,
            jobs      : []
        )
        openList = try FileWorkspaceActionBinding(
            role      : .openList,
            descriptor: ActionDescriptor(
                id     : "open-list",
                label  : "Open file list",
                payload: Data([7, 9])
            )
        )
        presentation = try FileWorkspacePresentation(
            snapshot        : snapshot,
            mode            : .deck,
            selectedEntryIDs: [],
            formats         : [],
            selectedFormatID: nil,
            actions         : [openList]
        )
    }
}
