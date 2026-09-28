//
//  FocusedWindowMonitoring.swift
//  CascadeKit
//

import AppKit

/// FocusedWindowMonitoring publishes the external focused window in global
/// AppKit coordinates. A nil frame means focus is unavailable and callers must
/// use their pointer/main-display fallback.
@MainActor
protocol FocusedWindowMonitoring: AnyObject {

    var onChange: ((CGRect?) -> Void)? { get set }

    func start()
    func stop()
    func refresh()
}
