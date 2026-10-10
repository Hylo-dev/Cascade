//
//  PluginSliderReading.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PluginSliderReading is what a slider stands for right now, for a `sliderValue` node to
/// draw: the value the user sees, which is the optimistic one while the slider is dragged or
/// awaiting confirmation and the published one otherwise, and the words to write it in.
///
/// A ruler's value is snapped to its step before it is written, because the thumb of a drag is
/// continuous and a time that read `1h 7m` between two ticks would be a figure no release can
/// settle on. A ruler with `duration` labels reads as its ticks do (`1h 30m`), one with
/// `clockTime` as the instant's short local time, and a standard slider is its plain number.
struct PluginSliderReading: Equatable {

    /// value is the slider's value as shown, snapped to the step for a ruler.
    let value : Double

    /// labels is the form of a ruler's value, nil for a standard slider.
    let labels: PluginRulerLabels?

    /// text writes the value. A ruler's goes through the view's `RulerLabelCache`, since a drag
    /// asks for it at the display's rate and each distinct step is formatted only once.
    func text(cache: RulerLabelCache) -> String {
        guard let labels else {
            return value.formatted(.number.precision(.fractionLength(0...2)))
        }

        return cache.text(value: value, labels: labels)
    }
}
