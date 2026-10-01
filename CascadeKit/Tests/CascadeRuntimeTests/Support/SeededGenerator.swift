//
//  SeededGenerator.swift
//  CascadeKit
//

import Foundation
import Testing
import CascadeContracts
import CascadeRuntime

struct SeededGenerator: RandomNumberGenerator {

    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
