//
//  AssetHandle.swift
//  CascadeKit
//

import Foundation

/// AssetHandle describes an immutable raster alias scoped to one publication.
/// Decoded metadata never grants access; the host rechecks its canonical alias and connection.
public struct AssetHandle: Codable, Equatable, Sendable {
    public let assetID       : String
    public let owner         : AddonID
    public let publicationID : PublicationID
    public let rasterRevision: UInt64
    public let width         : Int
    public let height        : Int
    public let byteCount     : Int

    public init(
        assetID       : String,
        owner         : AddonID,
        publicationID : PublicationID,
        rasterRevision: UInt64,
        width         : Int,
        height        : Int,
        byteCount     : Int
    ) throws {
        self.assetID        = assetID
        self.owner          = owner
        self.publicationID  = publicationID
        self.rasterRevision = rasterRevision
        self.width          = width
        self.height         = height
        self.byteCount      = byteCount
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)),
            "Asset handle requires exactly its defined fields"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetID        = try container.decode(
            String.self,
            forKey: .assetID
        )
        owner          = try container.decode(
            AddonID.self,
            forKey: .owner
        )
        publicationID  = try container.decode(
            PublicationID.self,
            forKey: .publicationID
        )
        rasterRevision = try container.decode(
            UInt64.self,
            forKey: .rasterRevision
        )
        width          = try container.decode(
            Int.self,
            forKey: .width
        )
        height         = try container.decode(
            Int.self,
            forKey: .height
        )
        byteCount      = try container.decode(
            Int.self,
            forKey: .byteCount
        )
        try validate()
    }

    /// validate checks metadata shape, not whether the host has issued this handle.
    /// The division bound precedes multiplication, including for hostile Int.max dimensions.
    public func validate() throws {
        try ContractValidation.require(
            ContractValidation.identifier(assetID) && owner == publicationID.addonID,
            "Invalid asset alias or publication owner"
        )
        try ContractValidation.require(
            rasterRevision > 0,
            "Invalid raster revision"
        )
        try ContractValidation.require(
            width > 0 && height > 0 && width <= 1_000_000 && height <= 1_000_000 / width,
            "Asset exceeds the supported pixel bounds"
        )
        try ContractValidation.require(
            byteCount == width * height * 4,
            "Asset byte count does not match RGBA8 dimensions"
        )
    }

    /// decode bounds raw metadata before Foundation parses the closed handle value.
    public static func decode(_ data: Data) throws -> Self {
        try ContractValidation.require(
            data.count <= 8_192,
            "Asset handle exceeds 8 KiB"
        )
        return try JSONDecoder().decode(
            Self.self,
            from: data
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case assetID, owner, publicationID, rasterRevision, width, height, byteCount
    }
}
