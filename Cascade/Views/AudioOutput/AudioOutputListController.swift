//
//  AudioOutputListController.swift
//  Cascade
//

import AppKit
import CascadeKit
import CoreAudio

/// AudioOutputListController keeps native labels, checkmarks and keyboard
/// buttons. Its stack measures the actual names, with no fixed popup dimensions.
@MainActor
final class AudioOutputListController: NSViewController {

    private let outputs  : [(id: AudioDeviceID, name: String)]
    private let current  : AudioDeviceID
    private let devices  : OutputDeviceAccess
    private let presenter: NotchPopoverPresenter

    init(
        outputs  : [(id: AudioDeviceID, name: String)],
        current  : AudioDeviceID,
        devices  : OutputDeviceAccess,
        presenter: NotchPopoverPresenter
    ) {
        self.outputs   = outputs
        self.current   = current
        self.devices   = devices
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 4
        stack.edgeInsets  = NSEdgeInsets(
            top   : 10,
            left  : 10,
            bottom: 10,
            right : 10
        )

        let heading = NSTextField(labelWithString: "Uscita audio del Mac")
        heading.font      = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        stack.addArrangedSubview(heading)

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true

        for device in outputs {
            let button = AudioOutputDeviceButton(
                device   : device,
                isCurrent: device.id == current,
                target   : self,
                action   : #selector(selectOutput(_:))
            )
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        }

        if outputs.isEmpty {
            let empty = NSTextField(labelWithString: "Nessuna uscita disponibile")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
        }

        view = stack
    }

    @objc
    private func selectOutput(_ sender: AudioOutputDeviceButton) {
        let selected = sender.deviceID
        presenter.dismiss()

        Task { [devices] in
            if !(await devices.selectOutput(selected)) { NSSound.beep() }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        presenter.dismiss()
    }

    @objc
    func cancel(_ sender: Any?) {
        presenter.dismiss()
    }
}
