//
//  PublicationAssetReferences.swift
//  Cascade
//

import CascadeContracts

extension Publication {
    /// forEachAssetReference visits declared assets in every representation and retained timeline entry,
    /// including entries not yet due. Privacy describes the referencing document; it
    /// neither grants asset access nor chooses backing retention policy.
    func forEachAssetReference(
        _ visit: (String, ContentDocument.Privacy) throws -> Void
    ) rethrows {
        if let content { try content.forEachAssetReference(visit) }
        if let timeline {
            for entry in timeline { try entry.content.forEachAssetReference(visit) }
        }
    }
}

private extension PresentationSet {
    /// forEachAssetReference walks the fixed representation slots without building an array.
    func forEachAssetReference(
        _ visit: (String, ContentDocument.Privacy) throws -> Void
    ) rethrows {
        try widget?.forEachAssetReference(visit)
        try compactLeading?.forEachAssetReference(visit)
        try compactTrailing?.forEachAssetReference(visit)
        try minimal?.forEachAssetReference(visit)
        try expanded?.forEachAssetReference(visit)
    }
}

private extension ContentDocument {
    /// forEachAssetReference preserves declared but currently undrawn asset references.
    func forEachAssetReference(
        _ visit: (String, ContentDocument.Privacy) throws -> Void
    ) rethrows {
        for id in assetIDs { try visit(id, privacy) }
    }
}
