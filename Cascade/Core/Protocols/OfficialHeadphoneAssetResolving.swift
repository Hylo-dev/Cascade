//
//  OfficialHeadphoneAssetResolving.swift
//  Cascade
//

nonisolated protocol OfficialHeadphoneAssetResolving: Sendable {

    func resolve(
        productID: UInt16,
        colorID  : UInt8?
    ) throws -> OfficialHeadphoneAsset?
}
