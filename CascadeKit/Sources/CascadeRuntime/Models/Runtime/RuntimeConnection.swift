//
//  RuntimeConnection.swift
//  CascadeKit
//

import Foundation

/// RuntimeConnection binds both independently minted component sessions to one incarnation.
struct RuntimeConnection: Sendable {

    let token                : UUID
    let incarnation          : RuntimeIncarnation
    let identity             : VerifiedAddonIdentity
    let digest               : String
    let publicationConnection: PublicationConnection
    let serviceSession       : ServiceSession
    let authorityRevision    : UInt64

    init(
        token                : UUID,
        incarnation          : RuntimeIncarnation,
        identity             : VerifiedAddonIdentity,
        digest               : String,
        publicationConnection: PublicationConnection,
        serviceSession       : ServiceSession,
        authorityRevision    : UInt64
    ) {
        self.token                 = token
        self.incarnation           = incarnation
        self.identity              = identity
        self.digest                = digest
        self.publicationConnection = publicationConnection
        self.serviceSession        = serviceSession
        self.authorityRevision     = authorityRevision
    }
}
