//
//  AssetTransferResultKind.swift
//  CascadeKit
//

import Foundation

/// AssetTransferResultKind distinguishes host acceptance, progress and protected import.
/// `shared` reports a fresh canonical alias over an existing raster without new transfer state.
public enum AssetTransferResultKind: String, Codable, Sendable {

    case begun, acknowledged, imported, shared, failure
}
