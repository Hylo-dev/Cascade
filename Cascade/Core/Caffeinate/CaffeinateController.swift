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
        publishPreferences()
    }

    /// handleAction checks the native state token as well as the broker's revision. A click
    /// already accepted by the broker cannot act on a session replaced before main received it.
    func handleAction(_ request: PluginActionRequest) {
        guard source.isAvailable, !source.state.isBusy, !isShuttingDown,
              request.key.plugin.rawValue == CaffeinatePlugin.identifier,
              request.key.feature == CaffeinatePlugin.feature,
              request.key.surface == .widget
        else { return }

        let suffix = "." + source.state.token.uuidString + ":button"
        if request.node.rawValue == "#display." + source.state.token.uuidString + ":toggle",
           case .bool(let display)? = request.value {
            guard display != keepDisplayAwake else { return }
            preferences.set(!display, forKey: "caffeinate.allowDisplaySleep")
            if source.state.isActive { changeSession(start: true, until: source.state.until) }
            else { publishPreferences() }
            return
        }
        guard request.value == nil else { return }
        if let minutes = [0, 15, 30, 60, 120, 240, 480].first(where: {
            request.node.rawValue == "#duration.\($0)" + suffix
        }) {
            guard minutes != self.minutes else { return }
            if source.state.isActive { start(minutes: minutes) }
            else {
                preferences.set(minutes, forKey: "caffeinate.minutes")
                publishPreferences()
            }
            return
        }
        switch request.node.rawValue {
            case "#toggle" + suffix, "#toggle.compact" + suffix: toggle()
            case "#stop" + suffix:
                if source.state.isActive { changeSession(start: false, until: nil) }
            case "#credits" + suffix:
                publishPreferences(showsCredits: !source.state.showsCredits)
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
        source.update(PluginCaffeinateState(
            isActive        : state.isActive,
            isBusy          : true,
            keepDisplayAwake: keepDisplayAwake,
            until           : state.until,
            minutes         : minutes,
            showsCredits    : state.showsCredits
        ))
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
            error           : error,
            minutes         : minutes,
            showsCredits    : source.state.showsCredits
        ))
        if snapshot.isActive, let until = snapshot.until, !isShuttingDown {
            let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.changeSession(start: false, until: nil) }
            }
            RunLoop.main.add(timer, forMode: .common)
            deadlineTimer = timer
        }
    }

    /// publishPreferences invalidates copied controls even when no native resource
    /// changes. The active absolute deadline remains owned by the session and its timer.
    private func publishPreferences(showsCredits: Bool? = nil) {
        let state = source.state
        source.update(PluginCaffeinateState(
            isActive        : state.isActive,
            isBusy          : state.isBusy,
            keepDisplayAwake: keepDisplayAwake,
            until           : state.until,
            error           : state.error,
            minutes         : minutes,
            showsCredits    : showsCredits ?? state.showsCredits
        ))
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
