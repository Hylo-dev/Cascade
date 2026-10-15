//
//  AudioVolumeBarComponent.swift
//  CascadeKit
//

import SwiftUI

/// AudioVolumeBarComponent is the tier-2 component audio.volumeBar: the global volume as a
/// vertical capsule. It reads the mixer model from the component services and draws the level,
/// the output's icon and, dragged past an end, a rubber-band stretch. It never writes the percentage; that is
/// the mixer's. The plugin
/// publishes nothing for it: the level is live system state, which a document cannot hold.
///
/// A click opens the widget's detail (the mixer) when the widget has one; a drag sets the level;
/// scrolling over the bar sets it too. With no model, or before the first reading, it draws the
/// unavailable look and takes no input, rather than a control that would do nothing.
struct AudioVolumeBarComponent: View {

    /// widthRatio keeps the widget in its 1x2 slots but draws a thinner pill inside them.
    private static let widthRatio: CGFloat = 0.6

    /// verticalInset makes the widget's pill the mixer's, so the glide between them is a move and
    /// not a resize. Under a hardware notch the 1x2 slot is E - N - 22 points tall (E the expanded
    /// height, N the notch's: two main rows and their gutter, `NotchLayoutResolver`) and the
    /// mixer's capsule row E - N - 28 (the page's insets, the title band and the row's padding,
    /// `AudioMixerComponent`), so giving back 3 points above and below matches them on every
    /// notched display; the width follows through the pill's aspect. Without a hardware notch the
    /// two differ slightly and the glide scales across the difference.
    private static let verticalInset: CGFloat = 3

    @Environment(\.pluginComponentServices)
    private var services

    @Environment(\.pluginOpenDetail)
    private var openDetail

    var body: some View {
        if let model = services?.audio, let system = model.system {
            AudioGlobalVolumeControl(
                role           : .widget,
                widthRatio     : Self.widthRatio,
                model          : model,
                system         : system,
                showsPercentage: false,
                onClick        : openDetail
            )
            .padding(.vertical, Self.verticalInset)
        } else {
            unavailable
        }
    }

    private var unavailable: some View {
        AudioVolumeCapsule(
            widthRatio     : Self.widthRatio,
            level          : 0,
            isMuted        : false,
            icon           : .symbol("speaker.slash"),
            iconOpacity    : 0.5,
            showsPercentage: false,
            onLevel        : { _ in },
            onEnd          : {},
            onClick        : nil
        )
        .padding(.vertical, Self.verticalInset)
        .accessibilityElement()
        .accessibilityLabel(AudioGlobalVolumeControl.accessibilityLabel)
        .accessibilityValue(AudioGlobalVolumeControl.accessibilityValue(of: nil))
    }
}
