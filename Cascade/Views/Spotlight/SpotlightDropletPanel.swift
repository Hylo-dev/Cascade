//
//  SpotlightDropletPanel.swift
//  Cascade
//

import AppKit
import QuartzCore

/// SpotlightDropletPanel drives a finite native-glass animation before handing off to Spotlight.
///
/// Its display link exists only while geometry or opacity changes. Landing holds
/// a static surface with no timer or display link while the caller positions and
/// focuses the native window. The panel never reads AX or sends keyboard events.
@MainActor
final class SpotlightDropletPanel: NSObject {

    private enum Animation {
        case droplet(SpotlightDropletTimeline)
        case dissolve(CGFloat)
    }

    private var panel                    : SpotlightDropletWindow?
    private var displayLink              : CADisplayLink?
    private var animation                : Animation?
    private var completion               : ((CGRect) -> Void)?
    private var previewCompletion        : (() -> Void)?
    private var animationStart           : CFTimeInterval = 0
    private var hasPresentedLandingFrame : Bool = false

    override init() {
        super.init()
    }

    isolated deinit {
        displayLink?.invalidate()
        panel?.orderOut(nil)
    }

    /// makeLayout samples only public screen geometry once before the animation begins.
    private func makeLayout(
        at anchor  : SpotlightDisplayAnchor,
        nativeSize : CGSize
    ) -> SpotlightDropletLayout {
        return SpotlightDropletLayout(
            screenFrame       : anchor.screen.frame,
            restingNotchBounds: anchor.restingBounds,
            nativeSize        : nativeSize
        )
    }

    /// startDisplayLink follows the target screen's refresh rate only while work remains.
    private func startDisplayLink() {
        guard let contentView = panel?.contentView else {
            return
        }

        animationStart = CACurrentMediaTime()
        let link = contentView.displayLink(
            target   : self,
            selector : #selector(tick(_:))
        )
        link.add(
            to      : .main,
            forMode : .common
        )
        displayLink = link
    }

    /// stopDisplayLink breaks the target retention cycle before completion can reenter the presenter.
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        animation = nil
        animationStart = 0
        hasPresentedLandingFrame = false
    }

    /// removeSurface releases compositing resources when playback is replaced or its fade ends.
    private func removeSurface() {
        stopDisplayLink()
        completion = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        let previewCompletion = previewCompletion
        self.previewCompletion = nil
        previewCompletion?()
    }

    /// dissolve discards a pending handoff before scheduling the short, finite opacity transition.
    private func dissolve() {
        stopDisplayLink()
        completion = nil

        guard let panel, panel.isVisible else {
            removeSurface()
            return
        }

        animation = .dissolve(panel.alphaValue)
        startDisplayLink()
    }

    /// tick updates native frames only; one extra refresh presents the final frame before completion.
    @objc
    private func tick(_ link: CADisplayLink) {
        guard let animation else {
            stopDisplayLink()
            return
        }

        let elapsed = max(0, link.timestamp - animationStart)
        switch animation {
        case .droplet(let timeline):
            if hasPresentedLandingFrame {
                finishHandoff(at: timeline.layout.landingBounds)
                return
            }

            let frame = timeline.frame(at: elapsed)
            if #available(macOS 26.0, *),
               let glassView = panel?.contentView as? SpotlightDropletGlassView {
                glassView.apply(frame)
            }
            if frame.isComplete && timeline.reducesMotion {
                // Reduced Motion has occupied the landing rect since its first
                // frame, so it needs no additional refresh before native focus.
                finishHandoff(at: timeline.layout.landingBounds)
            } else {
                hasPresentedLandingFrame = frame.isComplete
            }

        case .dissolve(let initialOpacity):
            let progress = min(1, elapsed / 0.080)
            panel?.alphaValue = initialOpacity * CGFloat(1 - progress * progress * (3 - 2 * progress))
            if progress >= 1 {
                removeSurface()
            }
        }
    }

    /// finishHandoff consumes completion before calling it so reentrant cancellation is harmless.
    private func finishHandoff(at landingBounds: CGRect) {
        let callback = completion
        completion = nil
        stopDisplayLink()
        callback?(landingBounds)
    }
}

extension SpotlightDropletPanel: SpotlightDropletPresenting {

    func play(
        at anchor  : SpotlightDisplayAnchor,
        nativeSize : CGSize,
        completion : @escaping (CGRect) -> Void
    ) {
        removeSurface()
        let layout = makeLayout(
            at         : anchor,
            nativeSize : nativeSize
        )

        guard #available(macOS 26.0, *) else {
            // The older deployment floor has no native Liquid Glass. Preserve
            // Spotlight functionality without manufacturing a substitute material.
            completion(layout.landingBounds)
            return
        }

        let timeline = SpotlightDropletTimeline(
            layout        : layout,
            reducesMotion : NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let panel = SpotlightDropletWindow(frame: layout.canvasBounds)
        panel.contentView = SpotlightDropletGlassView(timeline: timeline)

        self.panel      = panel
        self.completion = completion
        animation       = .droplet(timeline)

        panel.orderFrontRegardless()
        startDisplayLink()
    }

    func yieldToNative() {
        // Native Spotlight uses level 23 on the supported Campo host. Lower
        // the glass before posting the shortcut, so even a delayed focus/AX
        // response cannot leave it painted on top of the native text field.
        panel?.level = NSWindow.Level(rawValue: 22)
    }

    func revealNative() {
        removeSurface()
    }

    func cancel() {
        // Disabling or replacing the integration must release resources even
        // if this display is asleep and cannot supply another animation frame.
        removeSurface()
    }

    func preview(
        at anchor  : SpotlightDisplayAnchor,
        completion: @escaping () -> Void
    ) {
        play(
            at         : anchor,
            nativeSize : CGSize(
                width  : 520,
                height : 87
            ),
            completion : { [weak self] _ in
                self?.previewCompletion = completion
                self?.dissolve()
            }
        )
    }
}
