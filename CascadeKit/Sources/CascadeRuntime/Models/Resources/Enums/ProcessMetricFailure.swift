//
//  ProcessMetricFailure.swift
//  CascadeKit
//

import Foundation

enum ProcessMetricFailure: Equatable, Sendable {
    case invalidExpectation, identityUnavailable, identityMismatch, exited
    case readFailed(Int32), timebaseFailed(Int32)
    case invalidAcquisition, invalidTimebase
    case bindingInvalidated, bindingMismatch, timebaseChanged, nonIncreasingTime
    case counterRegression, counterOverflow, conversionOverflow, zeroElapsed
}
