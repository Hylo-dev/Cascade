//
//  ActiveDisplayResolving.swift
//  CascadeKit
//

import Foundation

/// ActiveDisplayResolving resolves which screen Cascade should follow right now.
///
/// It is a protocol so the engine can be driven by a fake multi-display layout
/// in tests, with no real screens attached. The concrete `SafeAreaNotchDetector`
/// reads AppKit; every caller depends only on this contract.
protocol ActiveDisplayResolving {

    /// Resolve the screen the overlay should live on (the screen under the
    /// pointer, falling back to the main screen), together with its notch
    /// metrics. Returns `nil` only if there is somehow no screen at all.
    func resolveActiveDisplay() -> ActiveDisplay?
}
