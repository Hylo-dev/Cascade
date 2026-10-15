//
//  NotchGlassLightEmitting.swift
//  CascadeKit
//

import AppKit

/// NotchGlassLightEmitting is for an AppKit emitter whose light changes only on its own events,
/// such as the volume fill, which moves only when the level does. Its light is normalized to the
/// receiver's outline, and that outline changes when the notch opens or closes; an emitter that
/// re-emits many times a second (the Music cover) catches up by itself, but one that waits for its
/// own events would leave its light placed on the old outline. The receiver calls
/// `glassLightBoundsDidChange` on each emitter it holds once the outline has changed, not on every
/// frame of the morph, and the emitter answers by placing its light again.
@MainActor
public protocol NotchGlassLightEmitting: NSView {

    func glassLightBoundsDidChange()
}
