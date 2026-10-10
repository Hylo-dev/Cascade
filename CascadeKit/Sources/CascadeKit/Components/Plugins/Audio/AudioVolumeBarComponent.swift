//
//  AudioVolumeBarComponent.swift
//  CascadeKit
//

import SwiftUI

/// AudioVolumeBarComponent is the tier-2 component audio.volumeBar: the global volume as a
/// vertical capsule. It reads the mixer model from the component services and draws the level,
/// the output's icon and, while the user adjusts, the percentage. The plugin publishes nothing
/// for it: the level is live system state, which a document cannot hold.
///
/// A click opens the widget's detail (the mixer) when the widget has one; a drag sets the level;
/// scrolling over the bar sets it too. With no model, or before the first reading, it draws the
/// unavailable look and takes no input, rather than a control that would do nothing.
struct AudioVolumeBarComponent: View {

    @Environment(\.pluginComponentServices)
    private var services

    @Environment(\.pluginOpenDetail)
    private var openDetail

    var body: some View {
        if let model = services?.audio, let system = model.system {
            AudioGlobalVolumeControl(
                model          : model,
                system         : system,
                showsPercentage: model.isAdjusting,
                onClick        : openDetail
            )
        } else {
            unavailable
        }
    }

    private var unavailable: some View {
        AudioVolumeCapsule(
            level          : 0,
            isMuted        : false,
            icon           : nil,
            showsPercentage: false,
            onLevel        : { _ in },
            onEnd          : {},
            onClick        : nil
        )
        .overlay(alignment: .bottom) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: AudioVolumeCapsule.iconSize, height: AudioVolumeCapsule.iconSize)
                .padding(.bottom, AudioVolumeCapsule.iconInset)
        }
        .accessibilityElement()
        .accessibilityLabel(AudioGlobalVolumeControl.accessibilityLabel)
        .accessibilityValue(AudioGlobalVolumeControl.accessibilityValue(of: nil))
    }
}
