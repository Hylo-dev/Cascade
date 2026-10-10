//
//  PluginSliderValueText.swift
//  CascadeKit
//

import SwiftUI

/// PluginSliderValueText is the kernel's `sliderValue`: the live value of a slider of the same
/// document, as text. It reads the slider's model through Observation, so it redraws exactly
/// when that value changes, a drag included, and never when anything else in the document does;
/// no publication is involved, and the plugin does not wake. It draws a plain SwiftUI `Text`, so
/// the font, the colour and the line limit are the node's own modifiers', applied around it like
/// any text's.
///
/// The labels of a ruler come from the view's own cache, the same one a ruler's ticks use.
struct PluginSliderValueText: View {

    let store   : PluginNodeStore
    let sliderID: String

    @StateObject
    private var cache = RulerLabelCache()

    var body: some View {
        Text(verbatim: store.sliderReading(sliderID)?.text(cache: cache) ?? "")
    }
}
