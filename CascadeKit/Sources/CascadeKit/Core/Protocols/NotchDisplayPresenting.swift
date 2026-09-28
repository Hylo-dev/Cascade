//
//  NotchDisplayPresenting.swift
//  CascadeKit
//

import AppKit
import OSLog

/// NotchDisplayPresenting is the fixed-display boundary between global
/// arbitration and one panel's geometry, springs, views and local interaction.
@MainActor
protocol NotchDisplayPresenting: AnyObject {
    var onSettingsRequested: (() -> Void)? { get set }
    var onExpandedFrameChanged: ((CGRect?) -> Void)? { get set }
    var expandedFrame: CGRect? { get }
    var restingFrame: CGRect? { get }
    var onExpansionRequested    : ((DisplayExpansionRequest) -> Void)? { get set }
    var onExpansionCancelled    : ((UInt64) -> Void)? { get set }
    var onCollapseRequested     : (() -> Void)? { get set }
    var onCollapseFinished      : ((UInt64) -> Void)? { get set }
    var onInteractionHoldChanged: ((NotchInteractionKind, Bool) -> Void)? { get set }
    var onDragOwnershipChanged  : ((Bool) -> Void)? { get set }
    var onRetainedActivityRootsChanged: (() -> Void)? { get set }
    var onFileDragHoverChanged: (([URL]?) -> Void)? { get set }
    var onFileDrop: (([URL]) -> Bool)? { get set }
    var onUnsupportedFileDrop: (() -> Void)? { get set }
    /// Exact provider instances still owned by the renderer, including its
    /// current mounted projection and roots leaving through a transition.
    var retainedActivityRoots: [any NotchActivity] { get }

    func start()
    func updateDisplay(_ display: ActiveDisplay)
    func applyPresentation(_ presentation: DisplayPresentation)
    func discardRetainedActivityRoots(_ identities: Set<ObjectIdentifier>)
    func close(animated: Bool, generation: UInt64)
    func cancelClose()
    func setVisible(_ isVisible: Bool)
    func handlePointer(at point: CGPoint)
    func handlePointerButton(isPressed: Bool)
    func handleSpaceChange()
    @discardableResult
    func beginSizeCalibration() -> Bool
    func setSettingsFocused(_ isFocused: Bool)
    func setExternalSurfacePresented(_ isPresented: Bool)
    func setHapticsEnabled(_ isEnabled: Bool)
    func setBorderAppearance(_ appearance: NotchBorderAppearance)
    func setSensitiveContentVisible(_ isVisible: Bool)
    func setFileDropEnabled(_ isEnabled: Bool)
    func endRecognizedFileDragGesture()
    func setRecognizedFileDragActive(
        _ isActive: Bool,
        at point: CGPoint,
        hasValidatedOfferHint: Bool
    )
    func stop()
}

extension NotchDisplayPresenting {
    func setRecognizedFileDragActive(_ isActive: Bool, at point: CGPoint) {
        setRecognizedFileDragActive(
            isActive,
            at: point,
            hasValidatedOfferHint: false
        )
    }
}
