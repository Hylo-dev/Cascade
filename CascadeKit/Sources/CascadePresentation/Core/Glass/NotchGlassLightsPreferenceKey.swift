//
//  NotchGlassLightsPreferenceKey.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI

/// NotchGlassLightsPreferenceKey combines descendant contributions in view order.
/// Only the first eight lights reach the host, bounding the renderer's work.
public struct NotchGlassLightsPreferenceKey: PreferenceKey {
    public static var defaultValue: [GlassLight] { [] }

    public static func reduce(value: inout [GlassLight], nextValue: () -> [GlassLight]) {
        value = Array(value.prefix(GlassLight.maximumCount))
        let remaining = GlassLight.maximumCount - value.count
        guard remaining > 0 else { return }
        value.append(contentsOf: nextValue().prefix(remaining))
    }
}
