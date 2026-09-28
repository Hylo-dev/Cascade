//
//  EmptyAddonAssetResolver.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

@MainActor
final class EmptyAddonAssetResolver: AddonPresentationAssetResolving {
    func image(
        for assetID        : String,
        publicationID      : PublicationID,
        publicationRevision: UInt64
    ) -> Image? { nil }
}
