//
//  NotchHostView.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CascadePresentation
import OSLog
import QuartzCore
import SwiftUI

private let fileDropLog = Logger(subsystem: "hylo.Cascade", category: "FileDrop")

private enum FileDropRejection: String {
    case sourceDoesNotCopy
    case oversizedBatch
    case promisedFile
    case unsupportedItem
    case unreadableFile
}

/// NotchHostView is the layer-backed canvas the notch chrome is drawn in.
///
/// It shares one outline between native glass, the opaque accessibility fallback,
/// and content clipping. Morphing assigns a new path each frame — the GPU rasterizes it —
/// so we never override `draw(_:)`. The view spans a fixed band across the top
/// of the active screen and does *not* resize during a morph; only the layer
/// path changes, which keeps the window geometry (an expensive thing to touch)
/// completely still while the notch animates.
///
/// Hit-testing is deliberately narrow: child controls receive points inside
/// the current path, while points outside it pass through the panel.
final class NotchHostView: NSView {

    static let fileDropTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .init("com.apple.pasteboard.promised-file-url"),
        .init("com.apple.pasteboard.promised-file-content-type")
    ]

    let auxiliaryInteraction = NotchAuxiliaryInteraction()

    var onSettingsRequested: (() -> Void)?
    var onFileDragHoverChanged: (([URL]?) -> Void)?
    var onFileDrop: (([URL]) -> Bool)?
    var onUnsupportedFileDrop: (() -> Void)?
    private let settingsButton = NSButton()

    private let shapeLayer       = CAShapeLayer()
    private let contentMaskLayer = CAShapeLayer()
    private let contentContainer  = NSView(frame: .zero)
    private let borderRenderer    = NotchBorderRenderer()
    private let glassRenderer: any NotchGlassRendering
    private var accessibilityObserver: NSObjectProtocol?
    private var isChromeVisible = false
    private var materialProgress: CGFloat = 0
    private var glassBody   = NotchGlassBody.zero
    private var glassTarget = NotchGlassBody.zero
    private var glassLightSources = NotchGlassLightSources()
    private var glassLightEmitters: [ObjectIdentifier: GlassLightEmitter] = [:]
    private(set) var glassLightBounds = CGRect.zero
    private var isFileDropEnabled = false
    private var fileDropExclusionFrame: CGRect = .zero
    private var fileDropIntakeFrame: CGRect?
    private var cachedFileOffer: (sequence: Int, changeCount: Int, urls: [URL])?
    private var hoveredFileOfferKey: (sequence: Int, changeCount: Int)?
    private var rejectedFileOfferKey: (sequence: Int, changeCount: Int)?
    private var loggedEnteredSequence: Int?
    private var loggedUpdatedSequence: Int?

    var borderAppearance: NotchBorderAppearance { borderRenderer.appearance }

    /// Hosts the SwiftUI content shown inside the open notch (the widgets).
    private let contentHost = NSHostingView(rootView: AnyView(EmptyView()))

    /// The activity hosts stay separate because compact content straddles the
    /// physical cutout while expanded content occupies the surface below it.
    /// Hidden hosts receive an empty root, which also stops TimelineView and
    /// other SwiftUI scheduling owned by content that is no longer visible.
    private let compactLeadingHost   = NSHostingView(rootView: AnyView(EmptyView()))
    private let compactTrailingHost  = NSHostingView(rootView: AnyView(EmptyView()))
    private let expandedActivityHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let detachedActivityHost = NSHostingView(rootView: AnyView(EmptyView()))

    /// The interactive hit path, in view coordinates, kept in sync with the
    /// morph so the overlay only swallows clicks where the notch actually is.
    private var hitPath: CGPath?

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, glassRenderer: NotchGlassRenderer())
    }

    init(frame frameRect: NSRect, glassRenderer: any NotchGlassRendering) {
        self.glassRenderer = glassRenderer
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        glassRenderer = NotchGlassRenderer()
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {

        wantsLayer = true
        clipsToBounds = false
        layer?.masksToBounds = false

        shapeLayer.fillColor   = NSColor.black.cgColor
        shapeLayer.anchorPoint = .zero
        shapeLayer.frame       = bounds

        layer?.addSublayer(shapeLayer)
        layer?.addSublayer(borderRenderer.chargingGlow)

        addSubview(glassRenderer.view)

        contentContainer.wantsLayer  = true
        contentContainer.frame       = bounds
        contentMaskLayer.fillColor   = NSColor.black.cgColor
        contentContainer.layer?.mask = contentMaskLayer
        addSubview(contentContainer)

        for hostingView in [contentHost, compactLeadingHost, compactTrailingHost, expandedActivityHost, detachedActivityHost] {
            // Decorative light may cross the content margins. The shared
            // contentMaskLayer, not each rectangular host, owns the final clip.
            hostingView.clipsToBounds = false
            hostingView.isHidden = true
            contentContainer.addSubview(hostingView)
        }

        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Impostazioni di Cascade")
        settingsButton.imagePosition = .imageOnly
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .lightGray
        settingsButton.toolTip = "Impostazioni…"
        settingsButton.setAccessibilityIdentifier("notch.settings")
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.isHidden = true
        contentContainer.addSubview(settingsButton)

        addSubview(borderRenderer.view)
        setBorderAppearance(.neutral, animated: false)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object : nil,
            queue  : .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.setBorderAppearance(self.borderAppearance, animated: false)
            }
        }
    }

    /// setBorderAppearance changes the rim independently of content or geometry.
    /// System preferences are also reapplied when they change while idle.
    func setBorderAppearance(
        _ appearance: NotchBorderAppearance,
        animated    : Bool
    ) {
        let workspace = NSWorkspace.shared
        borderRenderer.setAppearance(
            appearance,
            animated           : animated && !workspace.accessibilityDisplayShouldReduceMotion,
            reducesTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increasesContrast  : workspace.accessibilityDisplayShouldIncreaseContrast
        )
        updateChromeMaterial()
    }

    /// setSettingsButton keeps app chrome above either widgets or live activities,
    /// while the shared notch mask clips it during the expansion animation.
    func setSettingsButton(
        frame    : CGRect,
        isVisible: Bool
    ) {
        settingsButton.frame = frame
        settingsButton.isHidden = !isVisible || onSettingsRequested == nil
    }

    @objc private func openSettings() { onSettingsRequested?() }

    func setFileDropExclusionFrame(_ frame: CGRect) {
        fileDropExclusionFrame = frame
    }

    func setFileDropEnabled(_ isEnabled: Bool) {
        guard isFileDropEnabled != isEnabled else { return }
        isFileDropEnabled = isEnabled
        if isEnabled {
            registerForDraggedTypes(Self.fileDropTypes)
        } else {
            unregisterDraggedTypes()
            clearFileDragHover()
            cachedFileOffer = nil
            rejectedFileOfferKey = nil
        }
        fileDropLog.notice(
            "phase=readiness enabled=\(isEnabled) registered=\(self.registeredDraggedTypes.count) windowAttached=\(self.window != nil)"
        )
    }

    /// A temporary destination used only while a native file drag is active.
    /// Ordinary mouse hit testing remains bound to the animated notch outline.
    func setFileDropIntakeFrame(_ frame: CGRect?) {
        fileDropIntakeFrame = frame
    }

    /// Set the notch fill. Called once by the controller from the configuration;
    /// the renderer keeps the path moving, the color is stable. The SwiftUI
    /// `Color` is bridged to a `CGColor` here, at the AppKit boundary.
    func setChromeColor(_ color: Color) {
        shapeLayer.fillColor = NSColor(color).cgColor
        glassRenderer.setColor(color)
    }

    /// Show or hide the widget content and place it within the open notch.
    func setContent(
        _ view   : AnyView,
        frame    : CGRect,
        isVisible: Bool
    ) {
        update(
            host     : contentHost,
            view     : isVisible ? view : nil,
            frame    : frame
        )
    }

    /// Set the two compact activity surfaces on either side of the physical
    /// notch. The gap between the supplied frames is intentionally untouched:
    /// it is the real camera cutout, not a SwiftUI spacer that could receive a
    /// click or accidentally draw over the hardware.
    func setCompactActivityContent(
        leading      : AnyView?,
        leadingFrame : CGRect,
        trailing     : AnyView?,
        trailingFrame: CGRect
    ) {
        update(
            host : compactLeadingHost,
            view : leading,
            frame: leadingFrame
        )
        update(
            host : compactTrailingHost,
            view : trailing,
            frame: trailingFrame
        )
        update(
            host : expandedActivityHost,
            view : nil,
            frame: .zero
        )
    }

    /// Set expanded activity content below the physical cutout. The controller
    /// computes the safe frame once per discrete presentation change; this host
    /// does not participate in the per-frame layer morph.
    func setExpandedActivityContent(
        _ view: AnyView?,
        frame : CGRect
    ) {
        update(
            host : compactLeadingHost,
            view : nil,
            frame: .zero
        )
        update(
            host : compactTrailingHost,
            view : nil,
            frame: .zero
        )
        update(
            host : expandedActivityHost,
            view : view,
            frame: frame
        )
    }

    /// Clear activity roots when widgets own the expanded surface or the panel
    /// is hidden. Clearing the roots is what makes hidden content truly idle.
    func clearActivityContent() {
        clearDetachedActivityContent()
        update(
            host : compactLeadingHost,
            view : nil,
            frame: .zero
        )
        update(
            host : compactTrailingHost,
            view : nil,
            frame: .zero
        )
        update(
            host : expandedActivityHost,
            view : nil,
            frame: .zero
        )
    }

    /// The satellite shares the chrome mask, but keeps its own host so its icon
    /// can travel into the island without rebuilding SwiftUI on every frame.
    func setDetachedActivityContent(
        _ view  : AnyView,
        frame   : CGRect,
        onSelect: @escaping () -> Void
    ) {
        let button = AnyView(
            Button(action: onSelect) {
                view.allowsHitTesting(false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Espandi attività")
        )
        update(host: detachedActivityHost, view: button, frame: frame)
    }

    func clearDetachedActivityContent() {
        guard !detachedActivityHost.isHidden else { return }
        update(host: detachedActivityHost, view: nil, frame: .zero)
    }

    private func update(
        host : NSHostingView<AnyView>,
        view : AnyView?,
        frame: CGRect
    ) {
        let token = glassLightSources.replace(source: ObjectIdentifier(host))
        // Emitters inside the outgoing root go with it, before SwiftUI tears
        // their views down, exactly like its preference contribution.
        for (source, emitter) in glassLightEmitters where emitter.view.map({ $0.isDescendant(of: host) }) ?? true {
            glassLightEmitters[source] = nil
            glassLightSources.remove(source: source)
        }
        if let view {
            host.rootView = AnyView(NotchGlassLightObserver(content: view, token: token) { [weak self, weak host] emission in
                guard let self, let host, !host.isHidden,
                      self.glassLightSources.update(emission.lights, for: emission.token) else { return }
                self.glassRenderer.setLights(self.glassLightSources.lights)
            })
        } else {
            host.rootView = AnyView(EmptyView())
        }
        glassRenderer.setLights(glassLightSources.lights)
        host.frame    = frame
        host.isHidden = view == nil
    }

    // The notch hangs from the top, so we keep the default bottom-left origin
    // (y grows upward); the renderer hands us geometry in those coordinates.
    override var isFlipped: Bool {
        false
    }

    /// Push a freshly resolved geometry to the screen.
    ///
    /// `isChromeVisible` may be false in a custom configuration: the path still
    /// tracks the interactive zone so input routing and content clipping remain
    /// correct even when the chrome itself is hidden.
    func apply(
        geometry       : NotchGeometry,
        targetGeometry : NotchGeometry? = nil,
        centerX        : CGFloat,
        topY           : CGFloat,
        isChromeVisible: Bool,
        borderOpacity  : CGFloat = 1,
        materialProgress: CGFloat = 1,
        detachedFrame  : CGRect = .zero,
        detachedProgress: CGFloat = 0,
        isAttaching    : Bool = false,
        softwareDroplet: Bool = false,
        dropletProgress: CGFloat = 0,
        softwareMetrics: SoftwareNotchMetrics = SoftwareNotchMetrics()
    ) {

        // Per-frame geometry changes must not animate implicitly — the spring is
        // already the animation. A no-action transaction stops Core Animation
        // from adding its own quarter-second fade to every path swap.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Frames change only with the window; every write still costs a commit.
        if shapeLayer.frame != bounds {
            shapeLayer.frame        = bounds
            contentContainer.frame  = bounds
            contentMaskLayer.frame  = bounds
        }

        let ordinaryNotchPath = CGPath.notch(
            geometry: geometry,
            centerX : centerX,
            topY    : topY
        )
        let notchPath: CGPath
        if softwareDroplet {
            let restingRadius = min(
                softwareMetrics.restingSize.height / 2,
                softwareMetrics.restingSize.width / 2
            )
            let restingPath = CGPath.notch(
                geometry: NotchGeometry(
                    leftExtent        : softwareMetrics.restingSize.width / 2 - restingRadius,
                    rightExtent       : softwareMetrics.restingSize.width / 2 - restingRadius,
                    height            : softwareMetrics.restingSize.height,
                    bottomCornerRadius: restingRadius,
                    topCornerRadius   : restingRadius
                ),
                centerX : centerX,
                topY    : topY
            )
            notchPath = CGPath.softwareNotchDroplet(
                resting          : restingPath,
                bodyGeometry     : geometry,
                centerX          : centerX,
                topY             : topY,
                expansionProgress: dropletProgress,
                metrics          : softwareMetrics
            )
        } else {
            notchPath = ordinaryNotchPath
        }

        let progress = min(1.18, max(0, detachedProgress))
        let travel = isAttaching ? (1 - min(1, progress)) * 28 : 0
        let bubble = CGRect(
            x     : detachedFrame.midX - detachedFrame.width * progress / 2 - travel,
            y     : detachedFrame.midY - detachedFrame.height * progress / 2,
            width : detachedFrame.width * progress,
            height: detachedFrame.height * progress
        )
        let path = CGPath.notchDroplet(
            notch     : notchPath,
            rightEdge : centerX + geometry.rightExtent,
            bubble    : bubble,
            attachment: isAttaching ? 1 - min(1, progress) : 0
        )
        // Keep the icon's layout stable while the enclosing drop scales and moves.
        detachedActivityHost.layer?.setAffineTransform(CGAffineTransform(
            translationX: bubble.midX - detachedFrame.midX,
            y           : bubble.midY - detachedFrame.midY
        ))
        detachedActivityHost.alphaValue = min(1, progress)

        shapeLayer.path       = path
        glassBody   = NotchGlassBody(geometry: geometry, centerX: centerX, topY: topY)
        glassTarget = NotchGlassBody(geometry: targetGeometry ?? geometry, centerX: centerX, topY: topY)
        glassLightBounds = Self.outlineBounds(of: targetGeometry ?? geometry, centerX: centerX, topY: topY)
        self.isChromeVisible  = isChromeVisible
        self.materialProgress = materialProgress.isFinite ? min(1, max(0, materialProgress)) : 0
        updateChromeMaterial()
        contentMaskLayer.path = path
        borderRenderer.apply(
            path     : path,
            canvasBounds: bounds,
            isVisible: isChromeVisible,
            opacity  : borderOpacity,
            scale    : window?.backingScaleFactor ?? 2
        )

        CATransaction.commit()

        hitPath = path
    }

    /// updateChromeMaterial also runs on accessibility changes while idle. The
    /// fallback keeps the configured solid color and the exact same silhouette.
    private func updateChromeMaterial() {
        guard let path = shapeLayer.path else { return }
        let usesGlass = glassRenderer.isSupported && materialProgress > 0
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        shapeLayer.isHidden = !isChromeVisible || usesGlass
        glassRenderer.apply(
            path        : path,
            body        : glassBody,
            target      : glassTarget,
            canvasBounds: bounds,
            progress    : materialProgress,
            isVisible   : isChromeVisible && usesGlass
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit passes superview coordinates. The canvas now sits above the
        // halo gutter, while the animated path remains in local coordinates.
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        if fileDropIntakeFrame?.contains(localPoint) == true {
            // During a native file drag the host itself owns the widened
            // destination. Child content cannot steal the destination lookup.
            return self
        }
        guard containsInteractivePoint(localPoint) else {
            return nil
        }

        return super.hitTest(point) ?? self
    }

    /// containsInteractivePoint tests the live outline rather than its bounding
    /// box. The distinction matters at rounded corners where the transparent
    /// pixels belong to the menu bar underneath and must remain clickable.
    func containsInteractivePoint(_ point: CGPoint) -> Bool {
        hitPath?.contains(point, using: .winding, transform: .identity) == true
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let point = fileDropPoint(for: sender)
        if loggedEnteredSequence != sender.draggingSequenceNumber {
            loggedEnteredSequence = sender.draggingSequenceNumber
            fileDropLog.notice(
                "phase=nativeEntered enabled=\(self.isFileDropEnabled) inside=\(self.containsFileDropPoint(point)) registered=\(self.registeredDraggedTypes.count) windowAttached=\(self.window != nil)"
            )
        }
        return resolveFileOffer(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let point = fileDropPoint(for: sender)
        if loggedUpdatedSequence != sender.draggingSequenceNumber {
            loggedUpdatedSequence = sender.draggingSequenceNumber
            fileDropLog.notice(
                "phase=nativeUpdated inside=\(self.containsFileDropPoint(point)) enabled=\(self.isFileDropEnabled)"
            )
        }
        guard containsFileDropPoint(point) else {
            clearFileDragHover()
            return []
        }
        return resolveFileOffer(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        clearFileDragHover()
        cachedFileOffer = nil
        rejectedFileOfferKey = nil
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        clearFileDragHover()
        cachedFileOffer = nil
        rejectedFileOfferKey = nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let point = fileDropPoint(for: sender)
        guard containsFileDropPoint(point), resolveFileOffer(sender) == .copy,
              let offer = cachedFileOffer else {
            fileDropLog.notice("phase=drop error=invalidDestination")
            clearFileDragHover()
            return false
        }
        let accepted = onFileDrop?(offer.urls) ?? false
        clearFileDragHover()
        cachedFileOffer = nil
        return accepted
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let point = fileDropPoint(for: sender)
        return containsFileDropPoint(point) && resolveFileOffer(sender) == .copy
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        clearFileDragHover()
        cachedFileOffer = nil
        rejectedFileOfferKey = nil
    }

    private func resolveFileOffer(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isFileDropEnabled else { return [] }
        let point = fileDropPoint(for: sender)
        guard containsFileDropPoint(point) else { return [] }
        let changeCount = sender.draggingPasteboard.changeCount
        guard sender.draggingSourceOperationMask.contains(.copy) else {
            rejectFileOffer(
                sequence: sender.draggingSequenceNumber,
                changeCount: changeCount,
                reason: .sourceDoesNotCopy
            )
            return []
        }
        if let cachedFileOffer,
           cachedFileOffer.sequence == sender.draggingSequenceNumber,
           cachedFileOffer.changeCount == changeCount {
            publishFileDragHover(cachedFileOffer)
            return .copy
        }
        guard let items = sender.draggingPasteboard.pasteboardItems,
              !items.isEmpty, items.count <= 32 else {
            rejectFileOffer(
                sequence: sender.draggingSequenceNumber,
                changeCount: changeCount,
                reason: .oversizedBatch
            )
            return []
        }
        let promiseTypes: Set<NSPasteboard.PasteboardType> = [
            .init("com.apple.pasteboard.promised-file-url"),
            .init("com.apple.pasteboard.promised-file-content-type")
        ]
        var urls: [URL] = []
        urls.reserveCapacity(items.count)
        for item in items {
            guard promiseTypes.isDisjoint(with: item.types) else {
                rejectFileOffer(
                    sequence: sender.draggingSequenceNumber,
                    changeCount: changeCount,
                    reason: .promisedFile
                )
                return []
            }
            guard item.types.contains(.fileURL),
                  let value = item.string(forType: .fileURL),
                  let url = URL(string: value), url.isFileURL else {
                rejectFileOffer(
                    sequence: sender.draggingSequenceNumber,
                    changeCount: changeCount,
                    reason: .unsupportedItem
                )
                return []
            }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                rejectFileOffer(
                    sequence: sender.draggingSequenceNumber,
                    changeCount: changeCount,
                    reason: .unreadableFile
                )
                return []
            }
            urls.append(url)
        }
        let offer = (sender.draggingSequenceNumber, changeCount, urls)
        cachedFileOffer = offer
        sender.numberOfValidItemsForDrop = urls.count
        publishFileDragHover(offer)
        return .copy
    }

    private func fileDropPoint(for sender: any NSDraggingInfo) -> CGPoint {
        guard let destinationWindow = sender.draggingDestinationWindow,
              let hostWindow = window,
              destinationWindow !== hostWindow else {
            return convert(sender.draggingLocation, from: nil)
        }
        let screenPoint = destinationWindow.convertPoint(
            toScreen: sender.draggingLocation
        )
        return convert(hostWindow.convertPoint(fromScreen: screenPoint), from: nil)
    }

    private func containsFileDropPoint(_ point: CGPoint) -> Bool {
        if let fileDropIntakeFrame {
            return fileDropIntakeFrame.contains(point)
        }
        return containsInteractivePoint(point) && !fileDropExclusionFrame.contains(point)
    }

    private func publishFileDragHover(_ offer: (sequence: Int, changeCount: Int, urls: [URL])) {
        guard hoveredFileOfferKey?.sequence != offer.sequence
                || hoveredFileOfferKey?.changeCount != offer.changeCount else { return }
        hoveredFileOfferKey = (offer.sequence, offer.changeCount)
        onFileDragHoverChanged?(offer.urls)
    }

    private func clearFileDragHover() {
        guard hoveredFileOfferKey != nil else { return }
        hoveredFileOfferKey = nil
        onFileDragHoverChanged?(nil)
    }

    private func rejectFileOffer(
        sequence: Int,
        changeCount: Int,
        reason: FileDropRejection
    ) {
        clearFileDragHover()
        cachedFileOffer = nil
        guard rejectedFileOfferKey?.sequence != sequence
                || rejectedFileOfferKey?.changeCount != changeCount else { return }
        rejectedFileOfferKey = (sequence, changeCount)
        fileDropLog.notice("phase=offer error=\(reason.rawValue, privacy: .public)")
        onUnsupportedFileDrop?()
    }

    /// outlineBounds is `CGPath.notch(...).boundingBoxOfPath` without building
    /// the path: the body plus the concave shoulders flaring out at the top.
    private static func outlineBounds(
        of geometry: NotchGeometry,
        centerX    : CGFloat,
        topY       : CGFloat
    ) -> CGRect {
        let shoulder = max(0, min(geometry.topCornerRadius, geometry.height / 2, geometry.width / 2))
        return CGRect(
            x     : centerX - geometry.leftExtent - shoulder,
            y     : topY - geometry.height,
            width : geometry.width + shoulder * 2,
            height: geometry.height
        )
    }

    isolated deinit {
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }
}

/// GlassLightEmitter remembers an AppKit emitter without retaining its view.
@MainActor
private final class GlassLightEmitter {
    let token: NotchGlassLightSources.Token
    weak var view: NSView?

    init(token: NotchGlassLightSources.Token, view: NSView) {
        self.token = token
        self.view  = view
    }
}

extension NotchHostView: NotchGlassLightReceiving {
    /// setGlassLights merges an AppKit emitter with the SwiftUI contributions.
    /// Each emitter is its own source; an empty array, or an emitter that is
    /// hidden, forgets it.
    func setGlassLights(_ lights: [GlassLight], from emitter: NSView) {
        let source = ObjectIdentifier(emitter)
        guard !lights.isEmpty, !emitter.isHiddenOrHasHiddenAncestor, emitter.isDescendant(of: self) else {
            guard glassLightEmitters.removeValue(forKey: source) != nil else { return }
            glassLightSources.remove(source: source)
            glassRenderer.setLights(glassLightSources.lights)
            return
        }
        let entry = glassLightEmitters[source]
            ?? GlassLightEmitter(token: glassLightSources.replace(source: source), view: emitter)
        glassLightEmitters[source] = entry
        guard glassLightSources.update(lights, for: entry.token) else { return }
        glassRenderer.setLights(glassLightSources.lights)
    }
}
