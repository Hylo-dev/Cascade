//
//  Publication+AssetReferences.swift
//  CascadeKit
//

import CascadeContracts

extension Publication {

    /// forEachAssetReference visits declared assets in every representation and retained timeline entry,
    /// including entries not yet due. Privacy describes the referencing document; it
    /// neither grants asset access nor chooses backing retention policy.
    func forEachAssetReference(_ visit: (String, ContentDocument.Privacy) throws -> Void) rethrows {
        if let content { try content.forEachAssetReference(visit) }
        if let timeline {
            for entry in timeline { try entry.content.forEachAssetReference(visit) }
        }
    }
}
