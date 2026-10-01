//
//  RawProcessMetricRead.swift
//  CascadeKit
//

enum RawProcessMetricRead: Equatable, Sendable {

    case success(ProcessMetricRecord)
    case failure(Int32)
}
