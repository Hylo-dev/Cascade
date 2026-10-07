//
//  CaffeinateSettingsMirror.swift
//  Cascade
//

import CascadeContracts
import Observation

/// CaffeinateSettingsMirror is what Settings shows of Caffeinate's two session-independent
/// preferences, kept on the main actor so a control reads its value in the render that follows
/// the click. The service applies a command on its own queue, so its `state` would lag.
///
/// Values travel both ways, and only one way sends. A write by the user (the control) sends the
/// matching command through `send`. A state the service published (`apply`) writes the values
/// *without* sending: the options page and a refused display assertion also change the service,
/// and echoing a published state back as a command would let a stale one, still in flight,
/// revert what the user just chose. The cost of that choice is a brief flicker if a stale state
/// lands after a click; the next state, which carries the user's change, corrects it.
@MainActor
@Observable
final class CaffeinateSettingsMirror {

    var glyph: CaffeinateGlyph {
        didSet {
            guard !isApplying, glyph != oldValue else { return }

            send(.setGlyph(glyph))
        }
    }

    var keepsDisplayAwake: Bool {
        didSet {
            guard !isApplying, keepsDisplayAwake != oldValue else { return }

            send(.setKeepsDisplayAwake(keepsDisplayAwake))
        }
    }

    @ObservationIgnored
    private var isApplying = false

    @ObservationIgnored
    private let send: (CaffeinateCommand) -> Void

    init(
        glyph            : CaffeinateGlyph,
        keepsDisplayAwake: Bool,
        send             : @escaping (CaffeinateCommand) -> Void
    ) {
        self.glyph             = glyph
        self.keepsDisplayAwake = keepsDisplayAwake
        self.send              = send
    }

    /// apply takes the service's published values without sending a command back.
    func apply(_ state: PluginCaffeinateState) {
        isApplying = true
        defer { isApplying = false }

        glyph             = state.glyph
        keepsDisplayAwake = state.keepsDisplayAwake
    }
}
