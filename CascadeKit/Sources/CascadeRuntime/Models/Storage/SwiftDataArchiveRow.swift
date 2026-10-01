//
//  SwiftDataArchiveRow.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import SwiftData

/// SwiftDataArchiveRow stores one coherent generation with ordinary in-database Data.
/// No external-storage attribute, relationship or separately committed blob is used.
@Model
final class SwiftDataArchiveRow {

    @Attribute(.unique)
    var namespace     : String
    var publisher     : String
    var addonID       : String
    var formatVersion : Int
    var schemaVersion : Int
    var revision      : String
    var verifiedDigest: String
    var payload       : Data
    var checksum      : Data

    init(
        identity  : VerifiedAddonIdentity,
        generation: SwiftDataArchiveGeneration
    ) {
        namespace      = SwiftDataArchiveWorker.namespace(identity)
        publisher      = identity.publisher
        addonID        = identity.addonID.rawValue
        formatVersion  = 1
        schemaVersion  = generation.schemaVersion
        revision       = String(generation.revision)
        verifiedDigest = generation.verifiedDigest
        payload        = generation.payload
        checksum       = SwiftDataArchiveWorker.checksum(identity: identity, generation: generation)
    }
}
