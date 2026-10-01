//
//  RawProcessMetricTimebase.swift
//  CascadeKit
//

enum RawProcessMetricTimebase: Equatable, Sendable {

    case success(ProcessMetricTimebase)
    case failure(Int32)
}
