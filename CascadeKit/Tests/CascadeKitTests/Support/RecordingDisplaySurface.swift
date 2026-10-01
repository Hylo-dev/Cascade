//
//  RecordingDisplaySurface.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class RecordingDisplaySurface: NotchDisplayPresenting {
    var onSettingsRequested: (() -> Void)?
    var onExpandedFrameChanged: ((CGRect?) -> Void)?
    var expandedFrame: CGRect? { nil }
    var onExpansionRequested: ((DisplayExpansionRequest) -> Void)?
    var onExpansionCancelled: ((UInt64) -> Void)?
    var onCollapseRequested : (() -> Void)?
    var onCollapseFinished  : ((UInt64) -> Void)?
    var onInteractionHoldChanged: ((NotchInteractionKind, Bool) -> Void)?
    var onDragOwnershipChanged: ((Bool) -> Void)?
    var onRetainedActivityRootsChanged: (() -> Void)?
    var onFileDragHoverChanged: (([URL]?) -> Void)?
    var onFileDrop: (([URL]) -> Bool)?
    var onUnsupportedFileDrop: (() -> Void)?
    private var mountedActivityRoots: [any NotchActivity] = []
    private var outgoingActivityRoots: [any NotchActivity] = []
    var retainsOutgoingRootsOnReplacement = false
    var retainedActivityRoots: [any NotchActivity] {
        let mountedIdentities = Set(mountedActivityRoots.map(ObjectIdentifier.init))
        return mountedActivityRoots + outgoingActivityRoots.filter {
            !mountedIdentities.contains(ObjectIdentifier($0))
        }
    }

    private(set) var display      : ActiveDisplay
    private(set) var presentations: [DisplayPresentation] = []
    private(set) var closeRequests: [UInt64] = []
    private(set) var isStarted = false
    private(set) var isStopped = false
    private(set) var stopCount = 0
    private(set) var visibilityUpdates: [Bool] = []
    private(set) var settingsFocusUpdates: [Bool] = []
    private(set) var pointerUpdates: [CGPoint] = []
    private(set) var buttonUpdates: [Bool] = []
    private(set) var hapticsUpdates: [Bool] = []
    private(set) var borderUpdates: [NotchBorderAppearance] = []
    private(set) var sensitiveContentUpdates: [Bool] = []
    private(set) var externalSurfaceUpdates: [Bool] = []
    private(set) var fileDragRecognitionUpdates: [Bool] = []
    private(set) var fileDragOfferHintUpdates: [Bool] = []
    private(set) var fileDropEnabledUpdates: [Bool] = []
    private(set) var fileDragGestureEndCount = 0
    private(set) var calibrationStartCount = 0
    var acceptsCalibration = true
    var restingFrame: CGRect? {
        CGRect(
            x     : display.frame.midX - 48,
            y     : display.frame.maxY - 8,
            width : 96,
            height: 8
        )
    }

    init(display: ActiveDisplay) {
        self.display = display
    }

    func start() { isStarted = true }
    func updateDisplay(_ display: ActiveDisplay) { self.display = display }
    func applyPresentation(_ presentation: DisplayPresentation) {
        let incomingIdentities = Set(presentation.visibleActivityRoots.map(ObjectIdentifier.init))
        outgoingActivityRoots = retainsOutgoingRootsOnReplacement
            ? mountedActivityRoots.filter { !incomingIdentities.contains(ObjectIdentifier($0)) }
            : []
        mountedActivityRoots = presentation.visibleActivityRoots
        presentations.append(presentation)
        if let primary = presentation.primary {
            _ = primary.makeCompactLeadingView(in: NotchActivityViewContext(
                presentation : .compactLeading,
                availableSize: CGSize(width: 10, height: 10)
            ))
        }
    }
    func discardRetainedActivityRoots(_ identities: Set<ObjectIdentifier>) {
        outgoingActivityRoots.removeAll { identities.contains(ObjectIdentifier($0)) }
    }
    func close(animated: Bool, generation: UInt64) { closeRequests.append(generation) }
    func cancelClose() {}
    func setVisible(_ isVisible: Bool) { visibilityUpdates.append(isVisible) }
    func handlePointer(at point: CGPoint) { pointerUpdates.append(point) }
    func handlePointerButton(isPressed: Bool) { buttonUpdates.append(isPressed) }
    func handleSpaceChange() {}
    func beginSizeCalibration() -> Bool {
        calibrationStartCount += 1
        return acceptsCalibration
    }
    func setSettingsFocused(_ isFocused: Bool) { settingsFocusUpdates.append(isFocused) }
    func setExternalSurfacePresented(_ isPresented: Bool) {
        externalSurfaceUpdates.append(isPresented)
    }
    func setHapticsEnabled(_ isEnabled: Bool) { hapticsUpdates.append(isEnabled) }
    func setBorderAppearance(_ appearance: NotchBorderAppearance) { borderUpdates.append(appearance) }
    func setSensitiveContentVisible(_ isVisible: Bool) { sensitiveContentUpdates.append(isVisible) }
    func setFileDropEnabled(_ isEnabled: Bool) { fileDropEnabledUpdates.append(isEnabled) }
    func endRecognizedFileDragGesture() { fileDragGestureEndCount += 1 }
    func setRecognizedFileDragActive(
        _ isActive: Bool,
        at point: CGPoint,
        hasValidatedOfferHint: Bool
    ) {
        fileDragRecognitionUpdates.append(isActive)
        fileDragOfferHintUpdates.append(hasValidatedOfferHint)
    }
    func stop() { isStopped = true; stopCount += 1 }

    func sendFileDragHover(_ urls: [URL]?) { onFileDragHoverChanged?(urls) }
    func sendFileDrop(_ urls: [URL]) -> Bool { onFileDrop?(urls) ?? false }

    func requestExpansion(
        activityID: String?,
        trigger   : DisplayExpansionTrigger,
        generation: UInt64
    ) {
        onExpansionRequested?(DisplayExpansionRequest(
            displayID: display.displayID,
            activityID: activityID,
            trigger: trigger,
            generation: generation
        ))
    }

    func cancelExpansion(generation: UInt64) { onExpansionCancelled?(generation) }
    func requestCollapse() { onCollapseRequested?() }
    func finishCollapse(generation: UInt64) { onCollapseFinished?(generation) }
    func releaseOutgoingRoots() {
        outgoingActivityRoots.removeAll()
        onRetainedActivityRootsChanged?()
    }
    func setDragOwner(_ isOwner: Bool) { onDragOwnershipChanged?(isOwner) }
    func setInteractionHold(_ kind: NotchInteractionKind, active: Bool) {
        onInteractionHoldChanged?(kind, active)
    }
}
