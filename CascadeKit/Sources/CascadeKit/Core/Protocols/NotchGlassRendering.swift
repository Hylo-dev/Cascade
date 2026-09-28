//
//  NotchGlassRendering.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CoreImage
import QuartzCore
import SwiftUI

/// NotchGlassRendering keeps native material updates separate from widget layout.
@MainActor
protocol NotchGlassRendering {
    var view: NSView { get }
    var isSupported: Bool { get }

    func setColor(_ color: Color)
    func setLights(_ lights: [GlassLight])

    /// `body` is where the notch is this frame and `target` where its morph is
    /// heading; both come from the same geometry that produced `path`.
    func apply(
        path        : CGPath,
        body        : NotchGlassBody,
        target      : NotchGlassBody,
        canvasBounds: CGRect,
        progress    : CGFloat,
        isVisible   : Bool
    )
}
