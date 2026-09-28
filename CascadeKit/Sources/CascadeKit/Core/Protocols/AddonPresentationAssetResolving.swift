//
//  AddonPresentationAssetResolving.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// AddonPresentationAssetResolving resolves the asset binding of one observed publication revision.
/// The host implementation validates current authority without calling the provider or waiting for IPC.
@MainActor
public protocol AddonPresentationAssetResolving: AnyObject {

    func image(
        for assetID        : String,
        publicationID      : PublicationID,
        publicationRevision: UInt64
    ) -> Image?
}
