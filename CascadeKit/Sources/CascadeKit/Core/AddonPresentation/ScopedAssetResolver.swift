//
//  ScopedAssetResolver.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

@MainActor
final class ScopedAssetResolver: ContentAssetResolving {

    private weak var base          : (any AddonPresentationAssetResolving)?
    private let publicationID      : PublicationID
    private let publicationRevision: UInt64

    init(
        base               : any AddonPresentationAssetResolving,
        publicationID      : PublicationID,
        publicationRevision: UInt64
    ) {
        self.base                = base
        self.publicationID       = publicationID
        self.publicationRevision = publicationRevision
    }

    /// image preserves this view's revision even when the host replaces the publication.
    func image(for assetID: String) -> Image? {
        base?.image(
            for                : assetID,
            publicationID      : publicationID,
            publicationRevision: publicationRevision
        )
    }
}
