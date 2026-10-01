//
//  AssetTransferBinding.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AssetTransferBinding carries immutable host-derived assignment identity, never authentication.
/// Integration must mint and revalidate the assignment against publisher/digest/feature/privacy.
struct AssetTransferBinding: Equatable, Sendable {

    let incarnation    : RuntimeIncarnation
    let connectionToken: UUID
    let publicationID  : PublicationID
    let assignmentToken: UUID
}
