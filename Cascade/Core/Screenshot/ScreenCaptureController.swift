//
//  ScreenCaptureController.swift
//  Cascade
//

import CascadePluginEngine
import CascadePlugins
import CascadeContracts
import CoreGraphics
import Foundation

/// ScreenCaptureController owns one native recording independently of visible
/// views. Only confirmed capture publishes state through the plugin source;
/// stopping retains its indicator until Apple's writer has finalized the file.
@MainActor
final class ScreenCaptureController {

    private struct Recording {
        let session  : UUID
        let url      : URL
        let startedAt: Date
    }

    private let capture: any ScreenCapturing
    private let canRecord: @MainActor () -> Bool
    private let publish: @MainActor (PluginScreenRecordingState) -> Void
    private let close  : @MainActor () -> Void
    private let failed : @MainActor (String) -> Void
    private var recording : Recording?
    private var eventTask : Task<Void, Never>?
    private var stopTask  : Task<Void, Never>?
    private var limitTask : Task<Void, Never>?
    private var isWorking = false
    private var isStopping = false
    private var preparingURL: URL?
    private var pendingTerminal: ScreenRecordingEvent?
    private var stopRequestedDuringStart = false
    private var isStartingRecording = false

    var isRecording: Bool { recording != nil }

    init(
        capture: any ScreenCapturing,
        canRecord: @escaping @MainActor () -> Bool = { false },
        publish: @escaping @MainActor (PluginScreenRecordingState) -> Void,
        close  : @escaping @MainActor () -> Void,
        failed : @escaping @MainActor (String) -> Void
    ) {
        self.capture = capture
        self.canRecord = canRecord
        self.publish = publish
        self.close = close
        self.failed = failed
        let events = capture.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handleNativeEvent(event)
            }
        }
    }

    func perform(
        _ mode: ScreenshotMode,
        on displayID: CGDirectDisplayID,
        options: ScreenCaptureOptions = ScreenCaptureOptions()
    ) async {
        guard !isWorking, !isStopping else { return }
        guard options.target == .screen else { return }
        if mode == .recording, recording != nil {
            close()
            return
        }
        guard mode != .recording || canRecord() else {
            failed(String(localized: "Recording controls are unavailable. Wait for the plugin or re-enable it."))
            return
        }

        isWorking = true
        isStartingRecording = mode == .recording
        stopRequestedDuringStart = false
        defer {
            isWorking = false
            isStartingRecording = false
            preparingURL = nil
            pendingTerminal = nil
            stopRequestedDuringStart = false
        }
        close()
        do {
            await capture.configure(options)
            if options.delaySeconds > 0 {
                try await Task.sleep(for: .seconds(min(60, options.delaySeconds)))
            }
            let url = try await capture.destination(for: mode)
            try Task.checkCancellation()
            if mode == .capture {
                try await capture.capture(displayID: displayID, to: url)
            } else {
                if stopRequestedDuringStart { return }
                preparingURL = url
                pendingTerminal = nil
                let startedAt = try await capture.startRecording(displayID: displayID, to: url)
                if Task.isCancelled || stopRequestedDuringStart || pendingTerminal != nil {
                    _ = try await capture.stopRecording()
                    if case .failed(_, let message) = pendingTerminal, !Task.isCancelled { failed(message) }
                    return
                }
                recording = Recording(
                    session  : UUID(),
                    url      : url,
                    startedAt: startedAt
                )
                updatePublication()
                limitTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(8 * 60 * 60 - 15)) }
                    catch { return }
                    self?.requestStop()
                }
            }
        } catch {
            if mode == .recording {
                _ = try? await capture.stopRecording()
                clearRecording()
            }
            if !Task.isCancelled { failed(error.localizedDescription) }
        }
    }

    /// handleAction receives only broker-accepted controls. Its node carries the native
    /// session too, so a queued Stop from the previous recording cannot reach a new writer.
    func handleAction(_ request: PluginActionRequest) {
        guard let recording,
              request.key.plugin.rawValue == ScreenRecordingPlugin.identifier,
              request.key.feature == ScreenRecordingPlugin.feature,
              request.key.surface == .activity,
              request.value == nil,
              request.node.rawValue == "#stop." + recording.session.uuidString + ":button"
        else { return }

        requestStop()
    }

    func requestStop() {
        if isStartingRecording {
            stopRequestedDuringStart = true
            return
        }
        guard recording != nil, stopTask == nil else { return }

        stopTask = Task { [weak self] in
            await self?.stop()
            self?.stopTask = nil
        }
    }

    /// shutdown waits asynchronously for the file, including an already pending
    /// Stop. AppKit may defer termination while this suspends; the main thread is free.
    func shutdown() async {
        if let stopTask { await stopTask.value }
        else { await stop() }
        eventTask?.cancel()
        eventTask = nil
    }

    private func stop() async {
        guard recording != nil, !isStopping else { return }

        isStopping = true
        updatePublication()
        do { _ = try await capture.stopRecording() }
        catch { failed(error.localizedDescription) }
        clearRecording()
    }

    func handleNativeEvent(_ event: ScreenRecordingEvent) {
        let url: URL
        switch event {
            case .finished(let output): url = output
            case .failed(let output, _): url = output
        }
        if url == preparingURL {
            pendingTerminal = event
            return
        }
        guard let recording, !isStopping else { return }

        switch event {
            case .finished(let url) where url == recording.url:
                requestStop()
            case .failed(let url, let message) where url == recording.url:
                failed(message)
                requestStop()
            default: break
        }
    }

    private func clearRecording() {
        recording = nil
        isStopping = false
        limitTask?.cancel()
        limitTask = nil
        publish(PluginScreenRecordingState())
    }

    /// updatePublication emits only recording lifecycle changes. PluginHost renders their
    /// description; the capture file and its native lifetime remain here.
    private func updatePublication() {
        guard let recording else { return }

        publish(PluginScreenRecordingState(
            session   : recording.session,
            startedAt : recording.startedAt,
            isStopping: isStopping
        ))
    }
}
