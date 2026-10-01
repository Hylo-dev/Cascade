//
//  AssetResolverFixture.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import CascadeRuntime
import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class AssetResolverFixture: AddonPresentationAssetResolving {

    struct Request: Equatable {

        let assetID      : String
        let publicationID: PublicationID
        let revision     : UInt64
    }

    var requests: [Request] = []

    func image(
        for assetID        : String,
        publicationID      : PublicationID,
        publicationRevision: UInt64
    ) -> Image? {
        requests.append(Request(
            assetID      : assetID,
            publicationID: publicationID,
            revision     : publicationRevision
        ))
        return nil
    }
}
