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

/// AudioOutputListController keeps native labels, checkmarks and keyboard
/// buttons. Its stack measures the actual names, with no fixed popup dimensions.
@MainActor
private final class AudioOutputListController: NSViewController {

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
        super.init(
            nibName: nil,
            bundle : nil
        )
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
        heading.font = .systemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .semibold
        )
        heading.textColor = .secondaryLabelColor
        stack.addArrangedSubview(heading)

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(
            equalTo : stack.widthAnchor,
            constant: -20
        ).isActive = true

        for device in outputs {
            let button = AudioOutputDeviceButton(
                device   : device,
                isCurrent: device.id == current,
                target   : self,
                action   : #selector(selectOutput(_:))
            )
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(
                equalTo : stack.widthAnchor,
                constant: -20
            ).isActive = true
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

/// AudioOutputDeviceButton carries a typed device ID independently of its
/// localized label. The empty image reserves the current-device check column.
@MainActor
private final class AudioOutputDeviceButton: NSButton {

    let deviceID: AudioDeviceID

    init(
        device   : (id: AudioDeviceID, name: String),
        isCurrent: Bool,
        target   : AnyObject,
        action   : Selector
    ) {
        deviceID = device.id
        super.init(frame: .zero)
        title       = device.name
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        bezelStyle                     = .recessed
        showsBorderOnlyWhileMouseInside = true
        alignment                      = .left
        imagePosition                  = .imageLeft
        imageHugsTitle                 = true
        font                           = .systemFont(ofSize: NSFont.systemFontSize)
        toolTip                        = device.name
        image = isCurrent ? NSImage(
            systemSymbolName        : "checkmark",
            accessibilityDescription: "Selezionata"
        ) : NSImage(size: CGSize(width: 14, height: 14))
        setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        setAccessibilityLabel(device.name)
        setAccessibilityValue(isCurrent ? "Selezionata" : "")
    }

    required init?(coder: NSCoder) { nil }
}

private actor OutputDeviceAccess {
    func selectOutput(_ selected: AudioDeviceID) -> Bool {
        var device = selected
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device) == noErr
    }

    func defaultOutput() -> AudioDeviceID {
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size <= 65_536 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var property = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let result = withUnsafeMutablePointer(to: &name) {
                AudioObjectGetPropertyData(device, &property, 0, nil, &nameSize, $0)
            }
            guard result == noErr, let name else { return nil }
            return (device, name.takeRetainedValue() as String)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
