//
//  BrokerObservationGate.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing
@testable import CascadeRuntime

final class BrokerObservationGate: @unchecked Sendable {
    private let observationStarted = DispatchSemaphore(value: 0)
    private let observationRelease = DispatchSemaphore(value: 0)
    private let observationFinished = DispatchSemaphore(value: 0)
    private let acquisitionStarted = DispatchSemaphore(value: 0)
    private let acquisitionFinished = DispatchSemaphore(value: 0)

    func enterObservation() {
        observationStarted.signal()
    }

    func releaseObservation() {
        observationRelease.signal()
    }

    func finishObservation() {
        observationFinished.signal()
    }

    func startAcquisition() {
        acquisitionStarted.signal()
    }

    func finishAcquisition() {
        acquisitionFinished.signal()
    }

    func waitForRelease() -> Bool {
        observationRelease.wait(timeout: .now() + 2) == .success
    }

    func waitForObservation() -> Bool {
        observationStarted.wait(timeout: .now() + 2) == .success
    }

    func waitForObservationFinish() -> Bool {
        observationFinished.wait(timeout: .now() + 2) == .success
    }

    func waitForAcquisitionStart() -> Bool {
        acquisitionStarted.wait(timeout: .now() + 2) == .success
    }

    func waitForAcquisitionFinish(within duration: DispatchTimeInterval) -> Bool {
        acquisitionFinished.wait(timeout: .now() + duration) == .success
    }
}
