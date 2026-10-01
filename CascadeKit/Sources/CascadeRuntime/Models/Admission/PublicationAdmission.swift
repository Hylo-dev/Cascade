//
//  PublicationAdmission.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PublicationAdmission returns structurally validated values after publication
/// state commits. It authorizes or executes no operations, including endPublication,
/// and neither persists checkpoints nor consumes the coordinator's command journal.
public struct PublicationAdmission: Equatable, Sendable {

    public let operations: [OperationRequest]
    public let completion: InvocationCompletion?
    public let checkpoint: Data?
}
