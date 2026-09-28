//
//  SpotlightCoordinator.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// SpotlightCoordinator delays only an enabled system search shortcut. Native
/// search opens after the drop lands; its verified AX focus ends the handoff.
/// The native app continues to own search, IME, results, and subsequent typing.
@MainActor
@Observable
final class SpotlightCoordinator {
    private(set) var status = "Spotlight dal notch non attiva"
    @ObservationIgnored private let droplet: any SpotlightDropletPresenting
    @ObservationIgnored private let tap: any SpotlightKeyTapping
    @ObservationIgnored private var monitor: (any SpotlightAccessibilityMonitoring)?
    // Every mutation of these two, including mutating calls on the handoff
    // struct, refreshes the key tap's off-main gate, so no call site can leave
    // it stale.
    @ObservationIgnored private var handoff = SpotlightHandoffState() { didSet { syncKeyGate() } }
    @ObservationIgnored private var shortcut: SpotlightShortcut? { didSet { syncKeyGate() } }
    @ObservationIgnored private var bufferedEvents: [CGEvent] = []
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var pendingToggleGeneration: UInt64?
    @ObservationIgnored private var pendingNativeCloseGeneration: UInt64?
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var suppressShortcutRelease = false
    @ObservationIgnored private var nativeWidth: CGFloat = 520
    @ObservationIgnored private var activeHostID: pid_t?
    @ObservationIgnored private let anchor: @MainActor () -> SpotlightDisplayAnchor?
    @ObservationIgnored private let reservePresentation: (
        SpotlightDisplayAnchor,
        @escaping () -> Void
    ) -> Void
    @ObservationIgnored private let releasePresentation: () -> Void
    @ObservationIgnored private var activeAnchor: SpotlightDisplayAnchor?
    @ObservationIgnored private var isPresentationActive = false
    @ObservationIgnored private var isPresentationReady = false
    @ObservationIgnored private var presentationReadyAction: (() -> Void)?
    @ObservationIgnored private var previewGeneration: UInt64?
    @ObservationIgnored private var presentationGeneration: UInt64 = 0
    @ObservationIgnored private let handoffTimeout: Duration
    private let log = Logger(subsystem: "hylo.Cascade", category: "Spotlight")

    init(
        droplet            : any SpotlightDropletPresenting = SpotlightDropletPanel(),
        tap                : any SpotlightKeyTapping = SpotlightKeyTap(),
        anchor             : @escaping @MainActor () -> SpotlightDisplayAnchor?,
        reservePresentation: @escaping (SpotlightDisplayAnchor, @escaping () -> Void) -> Void,
        releasePresentation: @escaping () -> Void,
        initialShortcut    : SpotlightShortcut? = nil,
        initialProcessID   : pid_t? = nil,
        initiallyEnabled   : Bool? = nil,
        handoffTimeout     : Duration = .seconds(1.8)
    ) {
        self.droplet             = droplet
        self.tap                 = tap
        self.anchor              = anchor
        self.reservePresentation = reservePresentation
        self.releasePresentation = releasePresentation
        self.shortcut            = initialShortcut
        self.activeHostID        = initialProcessID
        self.isEnabled           = initiallyEnabled ?? (initialShortcut != nil)
        self.handoffTimeout      = handoffTimeout
        bufferedEvents.reserveCapacity(128)
        monitor = SpotlightAccessibilityMonitor { [weak self] snapshot in
            Task { @MainActor [weak self] in self?.receive(snapshot) }
        }
        syncKeyGate()
    }

    /// syncKeyGate publishes what `handle` reads for non-shortcut keys: they
    /// matter only while input is buffered or the native field is visible.
    private func syncKeyGate() {
        tap.updateGate(
            keyCode  : shortcut?.keyCode,
            isEngaged: handoff.shouldBufferInput || handoff.nativeIsVisible
        )
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.campo" else { return }
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
        refresh()
    }

    /// refresh is called on activation/settings visits, never from a timer.
    func refresh() {
        guard isEnabled, !handoff.shouldBufferInput else { return }
        guard #available(macOS 26, *) else {
            status = "La goccia Liquid Glass richiede macOS 26 o successivo"
            return
        }
        guard AXIsProcessTrusted() else {
            disconnectNative()
            status = "Consenti Accessibilità per Spotlight dal notch"
            return
        }
        let preferences = UserDefaults(suiteName: "com.apple.symbolichotkeys")
        let bindings = preferences?.dictionary(forKey: "AppleSymbolicHotKeys")
        guard let binding = bindings?["64"] as? [String: Any], let shortcut = SpotlightShortcut(preference: binding) else {
            disconnectNative()
            status = "Attiva una scorciatoia di sistema per Spotlight"
            return
        }
        guard let host = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.campo").first else {
            disconnectNative()
            status = "Apri Spotlight una volta per collegarla al notch"
            return
        }
        if activeHostID == host.processIdentifier, tap.isActive,
           self.shortcut?.keyCode == shortcut.keyCode, self.shortcut?.flags == shortcut.flags { return }
        self.shortcut = shortcut
        activeHostID = host.processIdentifier
        monitor?.start(processID: host.processIdentifier, generation: handoff.generation)
        let installed = tap.start(handler: { [weak self] type, event in
            self?.handle(type: type, event: event) ?? false
        }, onDisabled: { [weak self] in
            Task { @MainActor [weak self] in
                self?.log.error("Spotlight shortcut tap was disabled by the system")
                self?.cancelHandoff()
                self?.tap.stop()
                self?.status = "Scorciatoia nativa attiva · riapri il menu per riprovare"
            }
        })
        status = installed ? "Spotlight si stacca dal notch" : "Scorciatoia nativa attiva · Accessibilità non disponibile"
    }

    private func disconnectNative() {
        cancelHandoff()
        handoff.forgetNativePresence()
        tap.stop()
        monitor?.stop()
        activeHostID = nil
        shortcut = nil
    }

    func stop() {
        isEnabled = false
        cancelHandoff()
        handoff.forgetNativePresence()
        tap.stop()
        monitor?.stop()
        activeHostID = nil
        suppressShortcutRelease = false
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        status = "Spotlight dal notch non attiva"
    }

    func preview(at requestedAnchor: SpotlightDisplayAnchor? = nil) {
        guard !handoff.shouldBufferInput, !isPresentationActive,
              let anchor = requestedAnchor ?? anchor() else { return }
        beginPresentation(at: anchor) { [weak self] generation in
            guard let self else { return }
            self.previewGeneration = generation
            self.droplet.preview(at: anchor) { [weak self] in
                self?.finishPreview(generation: generation)
            }
        }
    }

    /// screenLocked invalidates every pending generation before display focus
    /// can resolve elsewhere on unlock.
    func screenLocked() {
        cancelHandoff()
        handoff.forgetNativePresence()
        suppressShortcutRelease = false
    }

    func open() {
        guard !handoff.nativeIsVisible, isEnabled, shortcut != nil,
              let generation = handoff.begin() else { return }
        preemptPreview()
        animateOpening(generation: generation)
    }

    func displaysDidChange(_ connectedDisplayIDs: Set<CGDirectDisplayID>) {
        guard let activeAnchor,
              !connectedDisplayIDs.contains(activeAnchor.displayID) else { return }
        let shouldRestoreNative = handoff.shouldBufferInput && !handoff.nativeWasRequested
        cancelHandoff()
        if shouldRestoreNative, let shortcut { tap.invokeNative(shortcut) }
    }

    /// handle does no AX work and never constructs animation views in the event
    /// callback. Only the short handoff retains keystrokes, bounded to 128 events.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard let shortcut else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, key == Int64(shortcut.keyCode), suppressShortcutRelease {
            suppressShortcutRelease = false
            return true
        }
        if type == .keyDown, shortcut.matches(event) {
            log.info("Spotlight shortcut: phase=\(self.handoff.diagnosticPhase, privacy: .public), repeat=\(event.getIntegerValueField(.keyboardEventAutorepeat))")
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return handoff.shouldBufferInput }
            preemptPreview()
            if let generation = handoff.reserveToggleAfterPossibleDismissal() {
                suppressShortcutRelease = true
                bufferedEvents.removeAll(keepingCapacity: true)
                resolveToggleAfterEscape(generation: generation)
                return true
            }
            if handoff.nativeWasRequested {
                // Campo may ignore a toggle during its opening animation.
                // Close once its actual field is settled, unless a newer open
                // has superseded this intent in the meantime.
                suppressShortcutRelease = true
                let needsNativeClose = handoff.nativeMayBePresent
                cancelFromShortcut(nativeClosing: needsNativeClose, awaitNativeOpening: needsNativeClose)
                return true
            }
            if handoff.nativeIsVisible {
                // Pass this close command to the native host, but record the
                // intent now. Waiting for AXHidden loses a rapid reopening.
                suppressShortcutRelease = false
                cancelFromShortcut(nativeClosing: true)
                return false
            }
            suppressShortcutRelease = true
            if handoff.shouldBufferInput {
                let needsNativeClose = handoff.nativeMayBePresent
                cancelFromShortcut(nativeClosing: needsNativeClose, awaitNativeOpening: needsNativeClose)
            } else if let generation = handoff.begin() {
                bufferedEvents.removeAll(keepingCapacity: true)
                Task { @MainActor [weak self] in self?.animateOpening(generation: generation) }
            }
            return true
        }
        if type == .keyDown, key == 53, handoff.nativeIsVisible {
            // Campo clears a nonempty query but dismisses an empty field.
            // Do not infer which happened or read the user's query text.
            handoff.nativeMayDismiss()
            return false
        }
        guard handoff.shouldBufferInput else { return false }
        if key == 53, type == .keyDown {
            let needsNativeClose = handoff.nativeMayBePresent
            cancelFromShortcut(nativeClosing: needsNativeClose, awaitNativeOpening: needsNativeClose)
            return true
        }
        // Switching applications or invoking another global command is an
        // explicit interruption. It must not be swallowed by a visual effect.
        if type == .keyDown, (event.flags.contains(.maskCommand) && key == 48) || event.flags.contains(.maskControl) {
            cancelFromShortcut(nativeClosing: false)
            return false
        }
        if bufferedEvents.count < 128, let copy = event.copy() { bufferedEvents.append(copy) }
        return true
    }

    private func resolveToggleAfterEscape(generation: UInt64) {
        pendingToggleGeneration = generation
        timeout?.cancel()
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, self.handoff.generation == generation,
                  self.pendingToggleGeneration == generation, let shortcut = self.shortcut else { return }
            // If AX stalls, preserve the requested native toggle without
            // leaving the keyboard gated or guessing whether Escape cleared.
            self.cancelFromShortcut(nativeClosing: false)
            self.tap.invokeNative(shortcut)
        }
        monitor?.clearTarget(generation: generation)
    }

    /// Only the window teardown is deferred out of the event-tap callback.
    /// Intent, generation and the keyboard buffer change synchronously.
    func cancelFromShortcut(nativeClosing: Bool, awaitNativeOpening: Bool = false) {
        if nativeClosing { handoff.nativeWillClose() }
        else { handoff.cancel() }
        let generation = handoff.generation
        pendingNativeCloseGeneration = awaitNativeOpening ? generation : nil
        pendingToggleGeneration = nil
        timeout?.cancel()
        if awaitNativeOpening {
            timeout = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: self.handoffTimeout)
                guard !Task.isCancelled,
                      self.handoff.generation == generation,
                      self.pendingNativeCloseGeneration == generation,
                      !self.handoff.nativeIsKnownVisible else { return }
                self.pendingNativeCloseGeneration = nil
                self.timeout = nil
                self.handoff.forgetNativePresence()
                self.handoff.observeNative(isVisible: false, generation: generation)
                self.endPresentation()
            }
        } else {
            timeout = nil
        }
        bufferedEvents.removeAll(keepingCapacity: true)
        monitor?.clearTarget(generation: generation)
        Task { @MainActor [weak self] in
            guard let self, self.handoff.generation == generation else { return }
            self.droplet.cancel()
            if !nativeClosing { self.endPresentation() }
        }
    }

    private func animateOpening(generation: UInt64) {
        guard handoff.generation == generation else { return }
        guard isEnabled, shortcut != nil,
              let anchor = activeAnchor ?? anchor() else {
            cancelHandoff()
            return
        }
        pendingNativeCloseGeneration = nil
        log.info("Spotlight droplet started: generation=\(generation)")
        schedulePresentation(at: anchor) { [weak self] in
            self?.playOpening(generation: generation, anchor: anchor)
        }
    }

    private func playOpening(
        generation: UInt64,
        anchor    : SpotlightDisplayAnchor
    ) {
        guard handoff.generation == generation, isPresentationActive else { return }
        timeout?.cancel()
        // This watchdog exists only for a requested opening; it is not an idle
        // poll. Stale generations cannot cancel a subsequent animation.
        timeout = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.handoffTimeout)
            guard !Task.isCancelled, self.handoff.generation == generation,
                  self.handoff.shouldBufferInput,
                  !self.handoff.nativeIsKnownVisible else { return }
            self.log.error("Native Spotlight did not become ready within the handoff deadline")
            self.cancelHandoff()
            self.status = "Spotlight non risponde · riprova la scorciatoia"
        }
        droplet.play(at: anchor, nativeSize: CGSize(width: nativeWidth, height: 87)) { [weak self] landing in
            guard let self, self.handoff.requestNative(generation: generation) else { return }
            self.droplet.yieldToNative()
            self.monitor?.prepare(landingFrame: landing,
                desktopTop: NSScreen.screens.first?.frame.maxY ?? anchor.screen.frame.maxY,
                screenSize: anchor.screen.frame.size, generation: generation)
        }
    }

    func receive(_ snapshot: SpotlightWindowSnapshot) {
        guard isEnabled, snapshot.processID == activeHostID,
              snapshot.generation == handoff.generation else { return }
        let nativeWasKnownVisible = handoff.nativeIsKnownVisible
        handoff.recordNativePresence(isVisible: snapshot.isVisible, generation: snapshot.generation)
        if pendingNativeCloseGeneration == snapshot.generation {
            if !snapshot.isVisible, !handoff.nativeMayBePresent {
                pendingNativeCloseGeneration = nil
                timeout?.cancel()
                timeout = nil
                handoff.observeNative(isVisible: false, generation: snapshot.generation)
                completeNativeClosure()
            } else if snapshot.isVisible, snapshot.isSettled, snapshot.isFocused == true, let shortcut {
                pendingNativeCloseGeneration = nil
                timeout?.cancel()
                timeout = nil
                tap.invokeNative(shortcut)
            }
            return
        }
        if pendingToggleGeneration == snapshot.generation {
            guard !snapshot.isVisible || snapshot.isFocused != nil else { return }
            pendingToggleGeneration = nil
            timeout?.cancel()
            timeout = nil
            if snapshot.isVisible && snapshot.isFocused == true {
                // Escape only cleared the query: this shortcut closes native.
                cancelFromShortcut(nativeClosing: true)
                if let shortcut { tap.invokeNative(shortcut) }
            } else {
                animateOpening(generation: snapshot.generation)
            }
            return
        }
        if !snapshot.isVisible, nativeWasKnownVisible, handoff.shouldBufferInput {
            cancelHandoff()
            return
        }
        if handoff.claimNativeInvocation(isVisible: snapshot.isVisible, generation: snapshot.generation), let shortcut {
            tap.invokeNative(shortcut)
            return
        }
        handoff.observeNative(isVisible: snapshot.isVisible, generation: snapshot.generation)
        if !snapshot.isVisible, !handoff.shouldBufferInput {
            completeNativeClosure()
        }
        // Campo first exposes a display-sized animation surface. Waiting for
        // its final frame or focus leaves two capsules visible for that entire
        // transition. Remove our glass on the first native visibility report.
        if snapshot.isVisible, handoff.nativeWasRequested { droplet.revealNative() }
        guard snapshot.isReady, handoff.acceptNativeReady(generation: snapshot.generation) else { return }
        pendingToggleGeneration = nil
        timeout?.cancel()
        timeout = nil
        if let width = snapshot.frame?.width, width >= 200, width <= 1000 { nativeWidth = width }
        tap.deliver(bufferedEvents, to: snapshot.processID)
        bufferedEvents.removeAll(keepingCapacity: true)
        droplet.revealNative()
        status = "Spotlight si stacca dal notch"
    }

    private func cancelHandoff() {
        pendingNativeCloseGeneration = nil
        handoff.cancel()
        pendingToggleGeneration = nil
        timeout?.cancel()
        timeout = nil
        bufferedEvents.removeAll(keepingCapacity: true)
        droplet.cancel()
        monitor?.clearTarget(generation: handoff.generation)
        endPresentation()
    }

    /// completeNativeClosure releases the external owner only after the native
    /// monitor has observed that its window is actually gone.
    func completeNativeClosure() {
        endPresentation()
    }

    private func preemptPreview() {
        guard previewGeneration != nil else { return }
        previewGeneration = nil
        droplet.cancel()
    }

    private func finishPreview(generation: UInt64) {
        guard previewGeneration == generation else { return }
        previewGeneration = nil
        endPresentation()
    }

    private func schedulePresentation(
        at anchor: SpotlightDisplayAnchor,
        ready    : @escaping () -> Void
    ) {
        if isPresentationActive {
            presentationReadyAction = ready
            if isPresentationReady {
                presentationReadyAction = nil
                ready()
            }
            return
        }
        beginPresentation(at: anchor) { _ in ready() }
    }

    private func beginPresentation(
        at anchor: SpotlightDisplayAnchor,
        ready    : @escaping (UInt64) -> Void
    ) {
        guard !isPresentationActive else { return }
        isPresentationActive = true
        isPresentationReady = false
        activeAnchor = anchor
        presentationGeneration &+= 1
        let generation = presentationGeneration
        presentationReadyAction = { ready(generation) }
        reservePresentation(anchor) { [weak self] in
            guard let self, self.isPresentationActive,
                  self.presentationGeneration == generation else { return }
            self.isPresentationReady = true
            let action = self.presentationReadyAction
            self.presentationReadyAction = nil
            action?()
        }
    }

    private func endPresentation() {
        guard isPresentationActive else { return }
        presentationGeneration &+= 1
        isPresentationActive = false
        isPresentationReady = false
        presentationReadyAction = nil
        previewGeneration = nil
        activeAnchor = nil
        releasePresentation()
    }
}
