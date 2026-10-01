//
//  PluginVolumeLevelComponent.swift
//  CascadeKit
//

import SwiftUI

/// PluginVolumeLevelComponent is the tier-2 component volume.level: a dimmed capsule track with a
/// white fill for the level, filling the width it is given, as Cascade's volume notice drew it.
struct PluginVolumeLevelComponent: View {

    let level: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.23))

                Capsule()
                    .fill(.white)
                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, level))) / 100)
            }
        }
        .accessibilityHidden(true)
    }
}
