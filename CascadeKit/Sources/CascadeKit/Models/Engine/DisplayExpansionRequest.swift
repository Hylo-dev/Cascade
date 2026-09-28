//
//  DisplayExpansionRequest.swift
//  CascadeKit
//

import AppKit
import OSLog

/// DisplayExpansionRequest carries the local generation that makes delayed
/// arbitration safe. A later generation from the same surface supersedes it.
struct DisplayExpansionRequest: Equatable {
    let displayID : CGDirectDisplayID
    let activityID: String?
    let trigger   : DisplayExpansionTrigger
    let generation: UInt64
}
