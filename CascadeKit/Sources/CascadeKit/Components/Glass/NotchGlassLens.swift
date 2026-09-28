//
//  NotchGlassLens.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CoreImage
import QuartzCore
import SwiftUI

/// NotchGlassLens turns back on the lens that macOS leaves off on a glass the
/// size of an open notch. Past a certain size NSGlassEffectView frosts its
/// `glassBackground` filter (refraction opacity 0, blur radius 10), so the
/// notch read as a grey panel. With the blur at 0 and the refraction at full
/// opacity it is the clear glass of Apple's controls: the desktop shows
/// through untouched in the middle and bends through the edge, with Apple's
/// own lens profile (-60 over 20 pt at this size). Its face also lifts black
/// to a grey, dims white to 80 % and lays a 5 % white veil over both; all three
/// are undone, so the black beneath the glass stays as black as the hardware
/// cutout and the clear edge darkens only by the glass's own smoke.
///
/// The filter is private Core Animation API, reached by key. Only a filter and
/// keys that exist are touched, so if macOS renames them the glass stays
/// Apple's frosted default rather than breaking. Cost: a walk over the glass's
/// ~20 layers a few times per rebuild, nothing per frame.
@MainActor
enum NotchGlassLens {
    static let tuning: [String: Double] = [
        "inputBlurRadius"          : 0,
        "inputRefractionOpacity"   : 1,
        "inputFaceColorMatrixBlack": 0,
        "inputFaceColorMatrixWhite": 1,
    ]
    static let faceFillKey = "inputFaceColorMatrixFillColor"
    static let faceFill    = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    enum Outcome: Equatable {
        /// The glass has not built its filter yet.
        case missing
        case opened
        /// Every tuned key already held its value.
        case alreadyOpen
    }

    @discardableResult
    static func open(in root: CALayer) -> Outcome {
        var outcome = Outcome.missing
        for layer in backdrops(in: root) {
            guard let filter = layer.filters?
                    .compactMap({ $0 as? NSObject })
                    .first(where: { name(of: $0) == "glassBackground" }),
                  let keys = filter.perform(NSSelectorFromString("inputKeys"))?
                    .takeUnretainedValue() as? [String]
            else { continue }
            if outcome == .missing { outcome = .alreadyOpen }
            for (key, value) in tuning where keys.contains(key) {
                guard (filter.value(forKey: key) as? Double) != value else { continue }
                layer.setValue(value, forKeyPath: "filters.glassBackground.\(key)")
                outcome = .opened
            }
            if keys.contains(faceFillKey),
               filter.value(forKey: faceFillKey).map({ !CFEqual($0 as AnyObject, faceFill) }) ?? true {
                layer.setValue(faceFill, forKeyPath: "filters.glassBackground.\(faceFillKey)")
                outcome = .opened
            }
        }
        return outcome
    }

    private static func name(of filter: NSObject) -> String? {
        filter.responds(to: NSSelectorFromString("name")) ? filter.value(forKey: "name") as? String : nil
    }

    private static func backdrops(in layer: CALayer) -> [CALayer] {
        let own = NSStringFromClass(type(of: layer)) == "CABackdropLayer" ? [layer] : []
        return own + (layer.sublayers ?? []).flatMap { backdrops(in: $0) }
    }
}
