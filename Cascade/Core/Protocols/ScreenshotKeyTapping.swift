//
//  ScreenshotKeyTapping.swift
//  Cascade
//

/// ScreenshotKeyTapping owns reversible native shortcut interception. Stopping
/// releases the system event stream; consumers only receive fresh presses.
@MainActor
protocol ScreenshotKeyTapping: AnyObject {

    var isActive: Bool { get }

    func start(
        shortcuts : ScreenshotShortcuts,
        onShortcut: @escaping @MainActor () -> Void,
        onCancel  : @escaping @MainActor () -> Void,
        onDisabled: @escaping @MainActor () -> Void
    ) -> Bool

    func stop()

    func setCancellationEnabled(_ isEnabled: Bool)
}
