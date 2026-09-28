//
//  RawProcessMetricRead.swift
//  CascadeKit
//

import Foundation

enum RawProcessMetricRead: Equatable, Sendable {
    case success(ProcessMetricRecord)
    case failure(Int32)
}
