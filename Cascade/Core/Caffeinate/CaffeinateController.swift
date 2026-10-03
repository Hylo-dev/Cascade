//
//  CaffeinateController.swift
//  Cascade
//

import Foundation
import CascadeContracts
import CascadePluginEngine
import CascadePlugins

/// CaffeinateController maps accepted plugin controls to a background assertion owner.
/// Only acquisition, release and the single session deadline publish state. A disabled
/// source or termination waits asynchronously for in-flight acquisition before releasing it.
@MainActor
final class CaffeinateController: NSObject {

    let source : CaffeinatePluginSource
    private let session: CaffeinateSession
    private let preferences: UserDefaults
    private var operation: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var deadlineTimer: Timer?
    private var isShuttingDown = false
    private var ownsResources = false

    var needsShutdown: Bool { ownsResources || operation != nil || isShuttingDown }

    var minutes: Int {
        let saved = preferences.integer(forKey: "caffeinate.minutes")
        return [0, 15, 30, 60, 120, 240, 480].contains(saved) ? saved : 0
    }

    var keepDisplayAwake: Bool { !preferences.bool(forKey: "caffeinate.allowDisplaySleep") }

    init(
        source     : CaffeinatePluginSource,
        session    : CaffeinateSession,
        preferences: UserDefaults = .standard
    ) {
        self.source      = source
        self.session     = session
        self.preferences = preferences
        super.init()
        source.onReleased = { [weak self] in
            Task { await self?.shutdown() }
        }
    }

    /// handleAction checks the native state token as well as the broker's revision. A click
    /// already accepted by the broker cannot act on a session replaced before main received it.
    func handleAction(_ request: PluginActionRequest) {
        guard source.isAvailable, !source.state.isBusy, !isShuttingDown,
              request.key.plugin.rawValue == CaffeinatePlugin.identifier,
              request.key.feature == CaffeinatePlugin.feature,
              request.key.surface == .widget, request.value == nil
        else { return }

        let suffix = "." + source.state.token.uuidString + ":button"
        switch request.node.rawValue {
            case "#toggle" + suffix, "#toggle.compact" + suffix: toggle()
            case "#options" + suffix:
                // TODO: ADDON-NOTCH-OPTIONS in docs/TODO.md. An external menu must not
                // substitute for an addon-owned page covering the notch widget grid.
                break
            default: break
        }
    }

    func toggle() {
        guard source.isAvailable, operation == nil, !isShuttingDown else { return }

        if source.state.isActive { changeSession(start: false, until: nil) }
        else { start(minutes: minutes) }
    }

    func start(minutes: Int) {
        guard source.isAvailable, operation == nil, !isShuttingDown,
              [0, 15, 30, 60, 120, 240, 480].contains(minutes)
        else { return }

        preferences.set(minutes, forKey: "caffeinate.minutes")
        changeSession(start: true, until: minutes == 0 ? nil : Date.now.addingTimeInterval(Double(minutes * 60)))
    }

    private func changeSession(
        start: Bool,
        until: Date?
    ) {
        guard operation == nil, !start || (source.isAvailable && !isShuttingDown) else { return }

        deadlineTimer?.invalidate()
        deadlineTimer = nil
        let state = source.state
        source.update(PluginCaffeinateState(isActive: state.isActive, isBusy: true, keepDisplayAwake: keepDisplayAwake, until: state.until))
        let display = keepDisplayAwake
        operation = Task { [weak self, session] in
            var failure: String?
            do {
                if start { try await session.start(keepDisplayAwake: display, until: until) }
                else { try await session.stop() }
            } catch { failure = error.localizedDescription }

            guard let self else {
                try? await session.stop()
                return
            }
            if isShuttingDown || !source.isAvailable {
                do { try await session.stop() }
                catch { failure = error.localizedDescription }
            }
            let snapshot = await session.snapshot()
            publish(snapshot, error: failure)
            operation = nil
        }
    }

    private func publish(
        _ snapshot: CaffeinateSessionSnapshot,
        error     : String?
    ) {
        ownsResources = snapshot.hasResources
        source.update(PluginCaffeinateState(
            isActive        : snapshot.isActive,
            keepDisplayAwake: snapshot.isActive ? snapshot.keepDisplayAwake : keepDisplayAwake,
            until           : snapshot.isActive ? snapshot.until : nil,
            error           : error
        ))
        if snapshot.isActive, let until = snapshot.until, !isShuttingDown {
            let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.changeSession(start: false, until: nil) }
            }
            RunLoop.main.add(timer, forMode: .common)
            deadlineTimer = timer
        }
    }

    /// shutdown never waits on the UI thread. The operating system also releases all of
    /// this process's assertions if termination occurs before a native release can finish.
    func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        isShuttingDown = true
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        let task = Task { [self] in
            await operation?.value
            var failure: String?
            do { try await session.stop() }
            catch { failure = error.localizedDescription }
            publish(await session.snapshot(), error: failure)
        }
        shutdownTask = task
        await task.value
        shutdownTask = nil
        isShuttingDown = false
    }

}
