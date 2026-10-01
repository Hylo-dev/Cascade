//
//  ControllerTestDriver.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

/// ControllerTestDriver supplies the shared coordinator behavior around the
/// same fixed-display renderer used by production. It keeps legacy test call
/// sites readable without restoring global service ownership to the controller.
@MainActor
final class ControllerTestDriver {
    let surface     : NotchController
    let activityHost: LiveActivityHost
    let widgetHost  : WidgetHost
    let resolver    : MutableDisplayResolver
    let monitor     : RecordingEventMonitor
    private var isExpanded = false
    private var expansionActivityID: String?
    private var isVisible  = true
    private var closeGeneration: UInt64 = 0
    private var isReconciling = false
    private var needsReconciliation = false
    private var widgetContentRevision: UInt64 = 0
    private let autoGrantExpansions: Bool
    private var style: ExternalNotchStyle
    private(set) var expansionRequests: [DisplayExpansionRequest] = []
    private(set) var cancelledExpansionGenerations: [UInt64] = []
    private(set) var collapseRequestCount = 0

    var state: NotchState { surface.state }
    var activeDisplay: ActiveDisplay? { surface.activeDisplay }
    var expandedFrame: CGRect? { surface.expandedFrame }
    var restingFrame: CGRect? { surface.restingFrame }
    var onExpandedFrameChanged: ((CGRect?) -> Void)? {
        get { surface.onExpandedFrameChanged }
        set { surface.onExpandedFrameChanged = newValue }
    }

    init(
        surface     : NotchController,
        activityHost: LiveActivityHost,
        widgetHost  : WidgetHost,
        resolver    : MutableDisplayResolver,
        monitor     : RecordingEventMonitor,
        style       : ExternalNotchStyle,
        autoGrantExpansions: Bool
    ) {
        self.surface      = surface
        self.activityHost = activityHost
        self.widgetHost   = widgetHost
        self.resolver     = resolver
        self.monitor      = monitor
        self.style        = style
        self.autoGrantExpansions = autoGrantExpansions

        activityHost.onChange = { [weak self] in self?.reconcile() }
        activityHost.onValidityChange = { [weak self] in self?.reconcile() }
        widgetHost.onContentChanged = { [weak self] in
            guard let self else { return }
            self.widgetContentRevision &+= 1
            self.reconcile()
        }
        surface.onExpansionRequested = { [weak self] request in
            guard let self else { return }
            self.expansionRequests.append(request)
            if self.autoGrantExpansions {
                self.expand(activityID: request.activityID)
            }
        }
        surface.onExpansionCancelled = { [weak self] generation in
            self?.cancelledExpansionGenerations.append(generation)
        }
        surface.onCollapseRequested = { [weak self] in
            self?.collapseRequestCount += 1
            self?.collapse()
        }
        surface.onCollapseFinished = { [weak self] _ in
            self?.isExpanded = false
            self?.expansionActivityID = nil
            self?.activityHost.setExpansion(.none)
            self?.reconcile()
        }
        surface.onRetainedActivityRootsChanged = { [weak self] in self?.reconcile() }
        monitor.onPointerMoved = { [weak surface] in surface?.handlePointer(at: $0) }
        monitor.onPointerButtonChanged = { [weak surface] in
            surface?.handlePointerButton(isPressed: $0)
        }
        monitor.onActiveDisplayMayHaveChanged = { [weak self] in
            guard let self else { return }
            self.surface.updateDisplay(self.resolver.display)
        }
        monitor.onSpaceChanged = { [weak surface] in surface?.handleSpaceChange() }
        monitor.onScreenLocked = { [weak self] in self?.setVisible(false) }
        monitor.onScreenUnlocked = { [weak self] in self?.setVisible(true) }
    }

    func start() {
        isVisible = true
        activityHost.setVisible(true)
        surface.updateDisplay(resolver.display)
        surface.start()
        reconcile()
    }

    func stop() {
        isVisible = false
        surface.stop()
        widgetHost.update(state: .closed)
        activityHost.stop()
    }

    func present(_ activity: any NotchLiveActivity) { activityHost.present(activity) }
    func showNotice(_ notice: any NotchTransientNotice) {
        guard isVisible else { return }
        activityHost.showNotice(notice)
    }
    func updateNotice(_ notice: any NotchTransientNotice) { activityHost.updateNotice(notice) }
    func setExpandedFallback(_ activity: (any NotchLiveActivity)?) {
        activityHost.setExpandedFallback(activity)
    }
    func endActivity(id: String) { activityHost.end(id: id) }
    func dismissActivity(id: String) { activityHost.dismiss(id: id) }
    func dismissActivities(from sourceID: String) { activityHost.dismissActivities(from: sourceID) }
    func register(_ widget: NotchWidget) {
        widgetHost.register(widget)
        widgetContentRevision &+= 1
        reconcile()
    }
    func unregisterWidget(id: WidgetIdentifier) { widgetHost.unregister(id: id); reconcile() }
    func beginSizeCalibration() { _ = surface.beginSizeCalibration() }
    func setSettingsFocused(_ isFocused: Bool) { surface.setSettingsFocused(isFocused) }
    func setExternalSurfacePresented(_ isPresented: Bool) {
        surface.setExternalSurfacePresented(isPresented)
    }
    func setHapticsEnabled(_ isEnabled: Bool) { surface.setHapticsEnabled(isEnabled) }
    func setBorderAppearance(_ appearance: NotchBorderAppearance) {
        surface.setBorderAppearance(appearance)
    }
    func setStyle(_ style: ExternalNotchStyle) {
        self.style = style
        reconcile()
    }
    func simulateCompactRoutingMovedAwayWhileRetainingExpanded(
        _ activity: any NotchLiveActivity
    ) {
        surface.applyPresentation(DisplayPresentation(
            primary: nil,
            secondary: nil,
            notice: nil,
            expanded: activity,
            expandedIsLiveActivity: true,
            showsWidgets: false,
            widgetContentRevision: widgetContentRevision,
            style: style
        ))
    }
    func setSensitiveContentVisible(_ isVisible: Bool) {
        surface.setSensitiveContentVisible(isVisible)
    }

    func grantPendingExpansion() throws {
        let request = try #require(expansionRequests.last)
        expand(activityID: request.activityID)
    }

    private func expand(activityID: String?) {
        isExpanded = true
        expansionActivityID = activityID
        surface.cancelClose()
        if let activityID {
            activityHost.setExpansion(.activity(activityID))
        } else if let primary = activityHost.selection.primary {
            activityHost.setExpansion(.activity(primary.id))
        } else {
            activityHost.setExpansion(.fallback)
        }
        reconcile()
    }

    private func collapse() {
        guard isExpanded else { return }
        closeGeneration &+= 1
        surface.close(animated: true, generation: closeGeneration)
    }

    private func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible {
            isExpanded = false
            expansionActivityID = nil
            surface.setVisible(false)
        }
        activityHost.setVisible(visible)
        if visible {
            surface.setVisible(true)
        }
        reconcile()
    }

    private func reconcile() {
        guard !isReconciling else {
            needsReconciliation = true
            return
        }
        isReconciling = true
        repeat {
            needsReconciliation = false
            if isExpanded, expansionActivityID == nil {
                let expansion = activityHost.selection.primary.map {
                    ActivityExpansionSelection.activity($0.id)
                } ?? .fallback
                if activityHost.expansionSelection != expansion {
                    activityHost.setExpansion(expansion)
                    needsReconciliation = true
                    continue
                }
            }
            let selection = activityHost.selection
            let presentation = DisplayPresentation(
                primary     : selection.primary,
                secondary   : selection.secondary,
                notice      : selection.notice,
                expanded    : isExpanded ? selection.expanded : nil,
                expandedIsLiveActivity: isExpanded && {
                    if case .activity = activityHost.expansionSelection { return true }
                    return false
                }(),
                showsWidgets: isExpanded && selection.expanded == nil,
                widgetContentRevision: widgetContentRevision,
                style       : style
            )
            let roots = presentation.visibleActivityRoots + surface.retainedActivityRoots
            let projected = activityHost.setVisibleActivities(roots)
            let accepted = Set(projected.accepted.map(ObjectIdentifier.init))
            if presentation.showsWidgets && isVisible {
                widgetHost.update(state: .open)
            }
            surface.applyPresentation(presentation.removingInvalidRoots(
                accepted: accepted,
                host    : activityHost
            ))
            _ = activityHost.setVisibleActivities(
                presentation.visibleActivityRoots + surface.retainedActivityRoots
            )
            if !presentation.showsWidgets || !isVisible {
                widgetHost.update(state: .closed)
            }
        } while needsReconciliation
        isReconciling = false
    }
}
