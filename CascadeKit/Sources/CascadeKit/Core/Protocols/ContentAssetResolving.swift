//
//  ContentAssetResolving.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import SwiftUI

/// ContentAssetResolving supplies host-admitted images, without filesystem or network URLs.
@MainActor
public protocol ContentAssetResolving {

    func image(for assetID: String) -> Image?
}
