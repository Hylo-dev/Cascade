//
//  RawProcessMetricTimebase.swift
//  CascadeKit
//

import Foundation

enum RawProcessMetricTimebase: Equatable, Sendable {
    case success(ProcessMetricTimebase)
    case failure(Int32)
}
