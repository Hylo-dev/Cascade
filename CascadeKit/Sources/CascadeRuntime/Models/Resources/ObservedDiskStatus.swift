//
//  ObservedDiskStatus.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// ObservedDiskStatus reports canonical charges and the largest exceeded disk ceiling.
/// Overage is not summed across overlapping data/combined dimensions. permitsWrites
/// excludes owner/global debt; it grants no capacity or operation authority across awaits.
struct ObservedDiskStatus: Sendable {
    let bytes            : Int
    let ownerOverageBytes : Int
    let globalOverageBytes: Int
    let permitsWrites    : Bool
}
