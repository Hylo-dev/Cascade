//
//  AirPodsTurntableSurface.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import QuartzCore
import os

/// AirPodsTurntableSurface plays Apple's installed banner movie for one AirPods model as a single
/// Core Animation turn of at most 48 small frames, then keeps only a poster. Loading runs on a
/// utility task and is cancelled when the surface leaves the screen, which also releases every
/// image; Reduce Motion loads the poster alone. A product it cannot resolve shows the model's SF
/// Symbol instead.
final class AirPodsTurntableSurface: NSView, CAAnimationDelegate {

    private static let logger       = Logger(subsystem: "hylo.Cascade", category: "AirPodsArtwork")
    private static let animationKey = "airpods.connectionTurn"

    private var model             : PluginBluetoothDeviceModel?
    private var productID         : UInt16?
    private var colorID           : UInt8?
    private var fallbackSymbolName: String?
    private var allowsAnimation    = false
    private var isActive           = false
    private var hasAnimated        = false
    private var isFallbackShown    = false
    private var poster            : CGImage?
    private var loadTask          : Task<Void, Never>?
    private var loadGeneration    : UInt64 = 0
    private var windowObserver    : NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer             = true
        layer?.contentsGravity = .resizeAspect
        layer?.contentsScale   = 3
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    func configure(
        model             : PluginBluetoothDeviceModel,
        productID         : UInt16? = nil,
        colorID           : UInt8?  = nil,
        fallbackSymbolName: String? = nil,
        allowsAnimation   : Bool,
        isActive          : Bool
    ) {
        if self.model != model || self.productID != productID || self.colorID != colorID
            || self.fallbackSymbolName != fallbackSymbolName {
            releaseResources()

            self.model              = model
            self.productID          = productID
            self.colorID            = colorID
            self.fallbackSymbolName = fallbackSymbolName
        }

        self.allowsAnimation = allowsAnimation
        self.isActive        = isActive

        guard isActive else {
            releaseResources()
            return
        }

        if !allowsAnimation {
            layer?.removeAnimation(forKey: Self.animationKey)
            layer?.contents = poster
        }

        guard poster == nil, loadTask == nil, !isFallbackShown else { return }
        guard let productID else {
            showFallback()
            return
        }

        let includeMotion = allowsAnimation && !hasAnimated
        let generation    = loadGeneration
        let worker        = Task.detached(priority: .utility) { () throws -> OfficialHeadphoneArtwork? in
            let resolver = OfficialHeadphoneAssetResolver()
            guard let asset = try resolver.resolve(productID: productID, colorID: colorID) else { return nil }

            return try await OfficialHeadphoneArtwork.load(asset: asset, includeMotion: includeMotion)
        }

        loadTask = Task { [weak self] in
            defer {
                if self?.loadGeneration == generation { self?.loadTask = nil }
            }

            do {
                let artwork = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled,
                      let self,
                      self.isActive,
                      self.loadGeneration == generation
                else { return }

                if let artwork {
                    self.show(artwork)
                } else {
                    self.showFallback()
                }
            } catch is CancellationError {
                // The host removed or suspended the notice while decoding.
            } catch {
                guard !Task.isCancelled, self?.loadGeneration == generation else { return }

                Self.logger.error("Could not load AirPods artwork: \(String(describing: error), privacy: .public)")
                self?.showFallback()
            }
        }
    }

    private func show(_ artwork: OfficialHeadphoneArtwork) {
        poster          = artwork.poster
        layer?.contents = artwork.poster

        guard allowsAnimation, !hasAnimated, artwork.frames.count > 1 else { return }

        hasAnimated = true

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values                = artwork.frames
        animation.duration              = artwork.duration
        animation.calculationMode       = .discrete
        animation.repeatCount           = 1
        animation.delegate              = self
        animation.isRemovedOnCompletion = true
        layer?.add(animation, forKey: Self.animationKey)
    }

    func animationDidStop(
        _ animation  : CAAnimation,
        finished flag: Bool
    ) {
        // Removing the animation frees every sampled frame. The layer returns
        // to Apple's first banner frame, leaving no live decoder or timer.
        if flag { layer?.contents = poster }
    }

    func releaseResources() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil

        layer?.removeAllAnimations()
        layer?.contents = nil
        poster          = nil
        isFallbackShown = false
    }

    /// viewDidMoveToWindow ties the surface's lifetime to the window, because
    /// the notch is a standalone AppKit host, not a SwiftUI scene. Its mounted
    /// view and panel visibility provide the real lifetime; scenePhase can be
    /// background even while this nonactivating panel is visible.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }

        guard let window else {
            releaseResources()
            return
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object : window,
            queue  : .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let model = self.model else { return }

                self.configure(
                    model             : model,
                    productID         : self.productID,
                    colorID           : self.colorID,
                    fallbackSymbolName: self.fallbackSymbolName,
                    allowsAnimation   : self.allowsAnimation,
                    isActive          : self.window?.isVisible == true && !self.isHiddenOrHasHiddenAncestor
                )
            }
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        releaseResources()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()

        guard let model else { return }

        configure(
            model             : model,
            productID         : productID,
            colorID           : colorID,
            fallbackSymbolName: fallbackSymbolName,
            allowsAnimation   : allowsAnimation,
            isActive          : true
        )
    }

    isolated deinit {
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        loadTask?.cancel()
    }

    private func showFallback() {
        isFallbackShown = true

        let symbolName: String
        if let fallbackSymbolName {
            symbolName = fallbackSymbolName
        } else {
            switch model {
                case .airPods:    symbolName = "airpods"
                case .airPodsPro: symbolName = "airpodspro"
                case .airPodsMax: symbolName = "airpodsmax"
                default:          symbolName = "headphones"
            }
        }

        let symbol        = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.white])
        layer?.contents = symbol?.withSymbolConfiguration(configuration)
    }
}
