//
//  CaffeinateShortcutRecorder.swift
//  Cascade
//

import AppKit
import Observation
import SwiftUI

/// CaffeinateShortcutRecording is the recorder's one piece of state that lives outside the view:
/// whether it is listening, and the key monitor that listens. The monitor is a *local* one,
/// installed only while the user is recording and removed the moment a key is accepted, cancelled
/// or the view goes away, so at rest the recorder costs nothing and never sees a key typed in
/// another app. A local monitor also delivers the layout-independent `keyCode` that Carbon's
/// registration wants, which SwiftUI's `onKeyPress` does not.
///
/// While it listens it swallows every key down, so a stray letter does not beep or reach another
/// control in the Settings window.
@MainActor
@Observable
final class CaffeinateShortcutRecording {

    private(set) var isRecording = false

    @ObservationIgnored
    private var monitor: Any?

    @ObservationIgnored
    private var onRecorded: ((CaffeinateShortcut) -> Void)?

    func begin(onRecorded: @escaping (CaffeinateShortcut) -> Void) {
        guard !isRecording else { return }

        isRecording     = true
        self.onRecorded = onRecorded
        monitor         = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // The event is not Sendable, so only its two values cross into the main actor.
            let keyCode = event.keyCode
            let flags   = event.modifierFlags

            MainActor.assumeIsolated {
                self?.receive(
                    keyCode: keyCode,
                    flags  : flags
                )
            }

            return nil
        }
    }

    func cancel() {
        isRecording = false
        onRecorded  = nil

        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func receive(
        keyCode: UInt16,
        flags  : NSEvent.ModifierFlags
    ) {
        switch CaffeinateShortcut.recording(keyCode: keyCode, flags: flags) {
            case .shortcut(let shortcut):
                let onRecorded = self.onRecorded

                cancel()
                onRecorded?(shortcut)

            case .cancel:
                cancel()

            case .ignored:
                break
        }
    }
}

/// CaffeinateShortcutRecorder shows the current shortcut as a button. Clicking it starts
/// recording; the next valid combination is handed to `onChange`, Escape gives up, and Clear
/// turns the shortcut off (`nil`). It validates nothing itself: the key table and the modifier
/// rule live in `CaffeinateShortcut.recording`, and whether the system accepted the combination
/// comes back as `isUnavailable`.
struct CaffeinateShortcutRecorder: View {

    let shortcut     : CaffeinateShortcut?
    let isUnavailable: Bool
    let onChange     : (CaffeinateShortcut?) -> Void

    @State
    private var recording = CaffeinateShortcutRecording()

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {

            HStack(spacing: 8) {

                Button {
                    if recording.isRecording {
                        recording.cancel()
                    } else {
                        recording.begin(onRecorded: onChange)
                    }
                } label: {
                    Text(label)
                        .frame(minWidth: 110)
                }
                .accessibilityIdentifier("settings.caffeinateShortcut.record")

                if shortcut != nil {
                    Button("Clear") {
                        recording.cancel()
                        onChange(nil)
                    }
                    .accessibilityIdentifier("settings.caffeinateShortcut.clear")
                }
            }

            if isUnavailable {
                Text("Shortcut unavailable")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { recording.cancel() }
    }

    private var label: String {
        if recording.isRecording { return String(localized: "Type shortcut…") }

        return shortcut?.displayString ?? String(localized: "None")
    }
}
