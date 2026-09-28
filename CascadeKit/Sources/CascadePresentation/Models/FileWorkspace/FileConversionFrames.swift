//
//  FileConversionFrames.swift
//  CascadeKit
//

import CoreGraphics

/// FileConversionFrames keeps the conversion arrow centered between nonoverlapping groups.
public struct FileConversionFrames: Equatable, Sendable {
    public let inputs  : CGRect
    public let arrow   : CGRect
    public let selector: CGRect
    public let controls: CGRect
    public let results : CGRect
}
