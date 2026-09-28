//
//  ContentDocument+AssetReferences.swift
//  CascadeKit
//

import CascadeContracts

extension ContentDocument {
    /// forEachAssetReference preserves declared but currently undrawn asset references.
    func forEachAssetReference(
        _ visit: (String, ContentDocument.Privacy) throws -> Void
    ) rethrows {
        for id in assetIDs { try visit(id, privacy) }
    }
}
