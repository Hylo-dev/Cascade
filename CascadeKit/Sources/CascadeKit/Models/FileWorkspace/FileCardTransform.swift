//
//  FileCardTransform.swift
//  CascadeKit
//

import CoreGraphics

/// FileCardTransform describes one stable card slot in the four-card fan.
public nonisolated struct FileCardTransform: Equatable, Sendable {

    public let index          : Int
    public let rotationDegrees: Double
    public let xOffset        : Double
    public let yOffset        : Double
    public let scale          : Double
}
