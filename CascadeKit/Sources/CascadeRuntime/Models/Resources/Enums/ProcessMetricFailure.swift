//
//  ProcessMetricFailure.swift
//  CascadeKit
//

enum ProcessMetricFailure: Equatable, Sendable {

    case invalidExpectation
    case identityUnavailable
    case identityMismatch
    case exited
    case readFailed    (Int32)
    case timebaseFailed(Int32)
    case invalidAcquisition
    case invalidTimebase
    case bindingInvalidated
    case bindingMismatch
    case timebaseChanged
    case nonIncreasingTime
    case counterRegression
    case counterOverflow
    case conversionOverflow
    case zeroElapsed
}
