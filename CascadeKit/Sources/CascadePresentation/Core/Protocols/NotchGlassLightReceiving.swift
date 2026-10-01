//
//  NotchGlassLightReceiving.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI

/// NotchGlassLightReceiving lets AppKit content drive glass light without a
/// SwiftUI update per change. A view inside the notch's content finds the
/// nearest receiver among its superviews and hands it lights in the same
/// normalized space as `notchGlassLights`; an empty array withdraws them, and
/// so does replacing or hiding the content the view belongs to.
///
/// For light that follows a live signal, such as a spectrum at 30 Hz: through
/// the preference every tick re-evaluated SwiftUI, measured at ~1.3 % of a core
/// more than this path. Static light keeps using `notchGlassLights`.
@MainActor
public protocol NotchGlassLightReceiving: NSView {

    /// The outline the lights are normalized to once the notch settles, in
    /// the receiver's coordinates; y runs down from its top edge.
    var glassLightBounds: CGRect { get }

    func setGlassLights(
        _ lights    : [GlassLight],
        from emitter: NSView
    )
}
