//
//  AudioOutputPicker.swift
//  Cascade
//

import AppKit
import CascadeKit
import CoreAudio
import SwiftUI

/// AudioOutputPicker presents actual macOS output devices in an owned popover.
/// Selecting a row is the only operation
/// that changes routing; this does not claim to transfer a remote player session.
struct AudioOutputPicker: NSViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title : "",
            target: context.coordinator,
            action: #selector(Coordinator.showOutputs(_:))
        )
        button.image = NSImage(
            systemSymbolName        : "airplay.audio",
            accessibilityDescription: "Uscita audio del Mac"
        )
        button.imagePosition       = .imageOnly
        button.isBordered          = false
        button.contentTintColor    = .secondaryLabelColor
        button.symbolConfiguration = .init(
            pointSize: 20,
            weight   : .regular
        )
        button.toolTip = "Uscita audio del Mac"
        button.setAccessibilityLabel("Uscita audio del Mac")
        return button
    }

    func updateNSView(
        _ button: NSButton,
        context : Context
    ) {}

    static func dismantleNSView(
        _ button   : NSButton,
        coordinator: Coordinator
    ) {
        coordinator.presenter.dismiss()
        button.target = nil
    }

    @MainActor
    final class Coordinator: NSObject {

        let presenter = NotchPopoverPresenter()
        private let devices = OutputDeviceAccess()

        /// showOutputs registers with the notch before querying Core Audio, so
        /// dismissal also invalidates a still-pending output list.
        @objc
        func showOutputs(_ sender: NSButton) {
            if presenter.isPresented {
                presenter.dismiss()
                return
            }
            presenter.present(from: sender) { [devices, presenter] in
                let outputs = await devices.outputDevices()
                guard !Task.isCancelled else { return nil }
                let current = await devices.defaultOutput()
                guard !Task.isCancelled else { return nil }
                return AudioOutputListController(
                    outputs  : outputs,
                    current  : current,
                    devices  : devices,
                    presenter: presenter
                )
            }
        }
    }
}
