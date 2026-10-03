//
//  PluginSymbolView.swift
//  CascadeKit
//

import SwiftUI

/// PluginSymbolView animates an opted-in symbol once when its name changes. SwiftUI owns
/// the finite effect: there is no frame callback, polling or idle animation. Reduce Motion
/// suppresses the bounce, and ordinary plugin symbols retain their existing static path.
struct PluginSymbolView: View {

    let name: String

    @Environment(\.accessibilityReduceMotion)
    private var reducesMotion

    var body: some View {
        if reducesMotion {
            Image(systemName: name)
        } else {
            Image(systemName: name)
                .symbolEffect(.bounce, options: .nonRepeating, value: name)
        }
    }
}
