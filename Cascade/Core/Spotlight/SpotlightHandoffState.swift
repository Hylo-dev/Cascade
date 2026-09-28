//
//  SpotlightHandoffState.swift
//  Cascade
//



/// Commands change intent synchronously. AX observations acknowledge that intent;
/// delayed observations from a closed window cannot control a later opening.
nonisolated struct SpotlightHandoffState {
    private enum Phase { case idle, droplet, nativeRequested, visible, closing }
    private var phase = Phase.idle
    private var possibleNativeDismissal = false
    private var nativeInvocationClaimed = false
    private var nativeOpeningInFlight = false
    private var lastNativeVisibility = false
    private(set) var generation: UInt64 = 0

    var diagnosticPhase: String { String(describing: phase) }

    var shouldBufferInput: Bool { phase == .droplet || phase == .nativeRequested }
    var nativeWasRequested: Bool { phase == .nativeRequested }
    var nativeIsVisible: Bool { phase == .visible }
    var nativeMayBePresent: Bool { nativeOpeningInFlight || lastNativeVisibility }
    var nativeIsKnownVisible: Bool { lastNativeVisibility }

    mutating func recordNativePresence(isVisible: Bool, generation: UInt64) {
        guard self.generation == generation else { return }
        lastNativeVisibility = isVisible
        if isVisible { nativeOpeningInFlight = false }
    }

    mutating func forgetNativePresence() {
        nativeOpeningInFlight = false
        lastNativeVisibility = false
    }

    mutating func begin() -> UInt64? {
        guard phase == .idle || phase == .closing else { return nil }
        generation &+= 1
        possibleNativeDismissal = false
        nativeInvocationClaimed = false
        phase = .droplet
        return generation
    }

    mutating func requestNative(generation: UInt64) -> Bool {
        guard self.generation == generation, phase == .droplet else { return false }
        phase = .nativeRequested
        return true
    }

    mutating func claimNativeInvocation(isVisible: Bool, generation: UInt64) -> Bool {
        guard self.generation == generation, phase == .nativeRequested,
              !isVisible, !nativeInvocationClaimed, !nativeOpeningInFlight else { return false }
        nativeInvocationClaimed = true
        nativeOpeningInFlight = true
        return true
    }

    mutating func acceptNativeReady(generation: UInt64) -> Bool {
        guard self.generation == generation, phase == .nativeRequested else { return false }
        phase = .visible
        return true
    }

    mutating func nativeMayDismiss() {
        if phase == .visible { possibleNativeDismissal = true }
    }

    mutating func reserveToggleAfterPossibleDismissal() -> UInt64? {
        guard phase == .visible, possibleNativeDismissal else { return nil }
        phase = .idle
        return begin()
    }

    mutating func nativeWillClose() {
        generation &+= 1
        possibleNativeDismissal = false
        phase = .closing
    }

    mutating func observeNative(isVisible: Bool, generation: UInt64) {
        guard self.generation == generation else { return }
        switch phase {
        case .idle, .visible:
            phase = isVisible ? .visible : .idle
        case .closing:
            if !isVisible { phase = .idle }
        case .droplet, .nativeRequested:
            break
        }
    }

    mutating func cancel() {
        nativeOpeningInFlight = false
        generation &+= 1
        possibleNativeDismissal = false
        phase = .idle
    }
}
