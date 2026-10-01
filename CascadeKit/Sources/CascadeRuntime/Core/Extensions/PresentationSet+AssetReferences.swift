//
//  PresentationSet+AssetReferences.swift
//  CascadeKit
//

import CascadeContracts

extension PresentationSet {

    /// forEachAssetReference walks the fixed representation slots without building an array.
    func forEachAssetReference(_ visit: (String, ContentDocument.Privacy) throws -> Void) rethrows {
        try widget?.forEachAssetReference(visit)
        try compactLeading?.forEachAssetReference(visit)
        try compactTrailing?.forEachAssetReference(visit)
        try minimal?.forEachAssetReference(visit)
        try expanded?.forEachAssetReference(visit)
    }
}
