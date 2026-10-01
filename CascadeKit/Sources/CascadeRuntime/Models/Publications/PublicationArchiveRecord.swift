//
//  PublicationArchiveRecord.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PublicationArchiveRecord carries canonical content and terminal history without connection authority.
/// Construction grants nothing; the receiving state validates the complete restoration proposal.
struct PublicationArchiveRecord: Equatable, Sendable {

    let id             : PublicationID
    let revision       : UInt64
    let kind           : Publication.Kind
    let sessionDeadline: Date
    let publication    : Publication?
}
