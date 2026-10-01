//
//  ControlledArchiveObserver.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import SwiftData
import Testing
@testable import CascadeRuntime

/// ControlledArchiveObserver forwards every real scan and can conservatively add measured debt.
/// Artificial bytes qualify accounting outcomes, not a physical SwiftData growth bound.
actor ControlledArchiveObserver: SwiftDataArchiveObserving {

    private var additionalBytes       = 0
    private var pendingBytes         : Int?
    private var remainingObservations = 0
    private var gate                 : ArchiveGate?
    private var gateDelay             = 0
    private var isIncomplete          = false

    func setIncomplete(_ value: Bool) { isIncomplete = value }

    func gateAfterNextObservation(_ gate: ArchiveGate) {
        self.gate = gate
        gateDelay = 1
    }

    func addAfterNextObservation(_ bytes: Int) {
        pendingBytes          = bytes
        remainingObservations = 1
    }

    func clearAdditionalBytes() {
        additionalBytes = 0
        pendingBytes    = nil
    }

    func gateNextObservation(_ gate: ArchiveGate) { self.gate = gate }

    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        if let gate {
            if gateDelay == 0 {
                self.gate = nil
                await gate.enter()
            } else {
                gateDelay -= 1
            }
        }

        let observed = await NativeSwiftDataArchiveObserver().inventory(
            root      : root,
            descriptor: descriptor
        )

        if let pendingBytes {
            if remainingObservations == 0 {
                additionalBytes   = pendingBytes
                self.pendingBytes = nil
            } else {
                remainingObservations -= 1
            }
        }

        return SwiftDataArchiveInventory(
            bytes            : observed.bytes + additionalBytes,
            isComplete       : observed.isComplete && !isIncomplete,
            hasUnsafeEntries : observed.hasUnsafeEntries,
            hasUnknownEntries: observed.hasUnknownEntries
        )
    }
}
