//
//  AddonOptions.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonOptions constructs the value envelope from the action delivered by Cascade.
/// A provider may reuse the lease ID to refresh an active detail; Back revokes it.
public enum AddonOptions {

    public static func present(
        for action: ActionRequest,
        document  : ContentDocument,
        leaseID   : UUID = UUID()
    ) throws -> OperationRequest {
        .presentOptions(
            try AddonOptionsRequest(
                publicationID   : action.publicationID,
                observedRevision: action.observedRevision,
                actionRequestID : action.requestID,
                leaseID         : leaseID,
                document        : document
            )
        )
    }
}
