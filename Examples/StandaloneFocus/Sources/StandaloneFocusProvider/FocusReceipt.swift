//
//  FocusReceipt.swift
//  StandaloneFocus
//

import CascadeContracts
import Foundation

struct FocusReceipt: Codable, Sendable {

    let request : ActionRequest
    let outcome : ActionOutcome
    let revision: UInt64
}
