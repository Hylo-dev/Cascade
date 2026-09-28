//
//  MacPowerReading.swift
//  Cascade
//

import Foundation
import IOKit.ps

nonisolated protocol MacPowerReading: Sendable {
    func read() -> MacPowerSnapshot?
}
