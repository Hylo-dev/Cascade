//
//  NotchEngine.swift
//  CascadeKit
//

import AppKit

/// NotchDisplayDescriptor is the settings-safe description of one connected
/// logical display. Runtime IDs address the current session; only `identity`
/// may be persisted across reconnects.
public nonisolated struct NotchDisplayDescriptor: Equatable, Sendable {
    public let runtimeID       : CGDirectDisplayID
    public let identity        : DisplayIdentity?
    public let name            : String
    public let hasHardwareNotch: Bool
    public let style           : ExternalNotchStyle

    public init(
        runtimeID       : CGDirectDisplayID,
        identity        : DisplayIdentity?,
        name            : String,
        hasHardwareNotch: Bool,
        style           : ExternalNotchStyle = .notch
    ) {
        self.runtimeID        = runtimeID
        self.identity         = identity
        self.name             = name
        self.hasHardwareNotch = hasHardwareNotch
        self.style            = style
    }
}

/// NotchEngine wires one global coordinator to persistent fixed-display panels.
/// The app shell owns this entry point; displays may come and go underneath it
/// without recreating global input, activity or widget services.
@MainActor
public final class NotchEngine {
    private let coordinator: NotchDisplayCoordinator

    public var onSettingsRequested: (() -> Void)? {
        get { coordinator.onSettingsRequested }
        set { coordinator.onSettingsRequested = newValue }
    }

    public var expandedDisplayID: CGDirectDisplayID? { coordinator.expandedDisplayID }
    public var expandedFrame    : CGRect? { coordinator.expandedFrame }
    public var restingFrame     : CGRect? { coordinator.restingFrame }

    public var onExpandedFrameChanged: ((CGRect?) -> Void)? {
        get { coordinator.onExpandedFrameChanged }
        set { coordinator.onExpandedFrameChanged = newValue }
    }

    public var displays: [NotchDisplayDescriptor] { coordinator.displayDescriptors }

    public var onDisplaysChanged: (([NotchDisplayDescriptor]) -> Void)? {
        get { coordinator.onDisplaysChanged }
        set { coordinator.onDisplaysChanged = newValue }
    }

    public var onScreenLocked: (() -> Void)? {
        get { coordinator.onScreenLocked }
        set { coordinator.onScreenLocked = newValue }
    }

    public var auxiliaryDisplayID: CGDirectDisplayID? { coordinator.auxiliaryDisplayID }

    public func restingFrame(on displayID: CGDirectDisplayID) -> CGRect? {
        coordinator.restingFrame(on: displayID)
    }

    public init(
        configuration     : NotchConfiguration = .default,
        displayPreferences: DisplayPresentationPreferences = DisplayPresentationPreferences()
    ) {
        let activityHost = LiveActivityHost()
        let widgetHost   = WidgetHost()

        coordinator = NotchDisplayCoordinator(
            inventory   : DisplayInventory(),
            focusMonitor: FocusedWindowMonitor(),
            monitor     : MouseEventMonitor(),
            activityHost: activityHost,
            widgetHost  : widgetHost,
            preferences : displayPreferences,
            makeSurface : { display in
                let hostView = NotchHostView(frame: .zero)
                let panel    = NotchPanel(contentView: hostView)
                return NotchController(
                    configuration : configuration,
                    display       : display,
                    morphEngine   : DisplayLinkMorphEngine(view: hostView),
                    panel         : panel,
                    hostView      : hostView,
                    windowPinner  : SkyLightWindowPinner(),
                    hoverFeedback : HoverFeedback(performer: AppKitHapticPerformer()),
                    sizeCalibration: NotchSizeCalibration(
                        presenter: NotchCalibrationPanel(),
                        store    : NotchSizePreferences()
                    ),
                    activityHost: activityHost,
                    widgetHost  : widgetHost
                )
            }
        )
    }

    public func register(_ widget: NotchWidget) { coordinator.register(widget) }
    public func unregisterWidget(id: WidgetIdentifier) { coordinator.unregisterWidget(id: id) }
    public func present(_ activity: any NotchLiveActivity) { coordinator.present(activity) }
    public func setExpandedFallback(_ activity: (any NotchLiveActivity)?) {
        coordinator.setExpandedFallback(activity)
    }
    public func showNotice(_ notice: any NotchTransientNotice) { coordinator.showNotice(notice) }
    public func updateNotice(_ notice: any NotchTransientNotice) { coordinator.updateNotice(notice) }
    public func endActivity(id: String) { coordinator.endActivity(id: id) }
    public func dismissActivity(id: String) { coordinator.dismissActivity(id: id) }
    public func dismissActivities(from sourceID: String) {
        coordinator.dismissActivities(from: sourceID)
    }
    public func beginSizeCalibration(on displayID: CGDirectDisplayID? = nil) {
        coordinator.beginSizeCalibration(on: displayID)
    }
    public func setSettingsFocused(_ isFocused: Bool) {
        coordinator.setSettingsFocused(isFocused)
    }
    public func setSettingsPresented(
        _ isPresented         : Bool,
        reanchorToCurrentOwner: Bool = false
    ) {
        coordinator.setSettingsPresented(
            isPresented,
            reanchorToCurrentOwner: reanchorToCurrentOwner
        )
    }
    public func setHapticsEnabled(_ isEnabled: Bool) {
        coordinator.setHapticsEnabled(isEnabled)
    }
    public func setBorderAppearance(_ appearance: NotchBorderAppearance) {
        coordinator.setBorderAppearance(appearance)
    }
    public func setSensitiveContentVisible(_ isVisible: Bool) {
        coordinator.setSensitiveContentVisible(isVisible)
    }
    public func setExternalSurfacePresented(_ isPresented: Bool) {
        coordinator.setExternalSurfacePresented(isPresented)
    }
    public func reserveExternalSurface(
        on displayID: CGDirectDisplayID,
        ready       : @escaping () -> Void
    ) {
        coordinator.reserveExternalSurface(on: displayID, ready: ready)
    }
    public func releaseExternalSurface() {
        coordinator.releaseExternalSurface()
    }
    public func setDisplayPreferences(_ preferences: DisplayPresentationPreferences) {
        coordinator.updatePreferences(preferences)
    }
    public func setTransientDisplayStyle(
        _ style       : ExternalNotchStyle,
        for runtimeID : CGDirectDisplayID
    ) {
        coordinator.setTransientDisplayStyle(style, for: runtimeID)
    }
    public func start() { coordinator.start() }
    public func stop() { coordinator.stop() }
}
