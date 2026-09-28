//
//  ProbeHost.swift
//  Cascade Addon Platform Probe
//

import AppKit
import ExtensionFoundation
import ExtensionKit
import Foundation

enum ProbeFailure: Error { case invalidResponse, unexpectedIdentity, missingProxy, duplicateActivation, timeout }

/// ProbeHost exercises a system-launched process; stdout is the test evidence.
#if !PROBE_COUNTER_TESTING
@main
#endif
@MainActor
enum ProbeHost {
    static var extensionProcess: AppExtensionProcess?
    static var connection: NSXPCConnection?
    static var window: NSWindow?
    static var sceneController: EXHostViewController?
    static var sceneDelegate: ProbeSceneDelegate?
    static var listener: NSXPCListener?
    static var listenerDelegate: ProbeListenerDelegate?
    static var bootstrap: NSXPCConnection?
    static var eventReceiver: ProbeEventReceiverService?
    static var watchdog: DispatchWorkItem?
    static var activationStarted = false
    static var deactivated = false
    nonisolated static let outputLock = NSLock()
    static let caseName = CommandLine.arguments.dropFirst().first ?? "standalone-echo"

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--browse") {
            let browser = EXAppExtensionBrowserViewController()
            let browserWindow = NSWindow(contentViewController: browser)
            browserWindow.title = "Cascade — addon platform probe"
            browserWindow.setContentSize(NSSize(width: 600, height: 400))
            browserWindow.center()
            browserWindow.makeKeyAndOrderFront(nil)
            window = browserWindow
            application.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 180) { application.terminate(nil) }
        } else {
            let timeout = DispatchWorkItem {
                emit(["status": "FAIL", "reason": "discovery or connection timed out"])
                exit(2)
            }
            watchdog = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
            Task {
                do {
                    try await run()
                } catch {
                    emit(["status": "FAIL", "reason": String(describing: error)])
                    exit(1)
                }
            }
        }
        application.run()
    }

    static func run() async throws {
        for await identities in try AppExtensionIdentity.matching(appExtensionPointIDs: ProbeIdentity.point) {
            emit(["event": "discovery", "identities": identities.map(\.bundleIdentifier)])
            let candidates = identities.filter { $0.bundleIdentifier == ProbeIdentity.provider }
            guard !candidates.isEmpty else { continue }
            guard candidates.count == 1, let identity = candidates.first else { throw ProbeFailure.unexpectedIdentity }
            let controller = EXHostViewController()
            let delegate = ProbeSceneDelegate()
            sceneController = controller
            sceneDelegate = delegate
            controller.delegate = delegate
            controller.configuration = .init(appExtension: identity, sceneID: "main")
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 230),
                styleMask: [.nonactivatingPanel, .titled, .closable], backing: .buffered, defer: false)
            panel.title = "Cascade — prova scena remota"
            panel.contentViewController = controller
            panel.isFloatingPanel = true
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            window = panel
            return
        }
    }

    static func sceneActivated(_ controller: EXHostViewController) async throws {
        guard !activationStarted, !deactivated else { throw ProbeFailure.duplicateActivation }
        activationStarted = true
        let listener = NSXPCListener.anonymous()
        listener.setConnectionCodeSigningRequirement(ProbeIdentity.requirement(identifier: ProbeIdentity.provider))
        let delegate = ProbeListenerDelegate()
        listener.delegate = delegate
        self.listener = listener
        listenerDelegate = delegate
        eventReceiver = delegate.receiver
        listener.resume()
        let bootstrap = try controller.makeXPCConnection()
        bootstrap.remoteObjectInterface = NSXPCInterface(with: ProbeBootstrap.self)
        self.bootstrap = bootstrap
        bootstrap.resume()
        let channel = try await withCheckedThrowingContinuation { continuation in
            delegate.prepare(accepted: { continuation.resume(returning: $0) }, failed: { continuation.resume(throwing: $0) })
            guard let proxy = bootstrap.remoteObjectProxyWithErrorHandler({ delegate.fail($0) }) as? ProbeBootstrap else {
                delegate.fail(ProbeFailure.missingProxy); return
            }
            proxy.connect(to: listener.endpoint)
        }
        guard !deactivated else {
            channel.invalidate()
            throw ProbeFailure.invalidResponse
        }
        connection = channel
        let request = ProbeRequest(requestID: UUID(), operation: "echo", payload: "remote-scene")
        let response = try await send(request, over: channel)
        guard !deactivated, response.requestID == request.requestID, response.value == request.payload,
              response.providerPID == channel.processIdentifier, response.providerPID != getpid() else {
            throw ProbeFailure.unexpectedIdentity
        }
        let sessionID = UUID()
        guard delegate.receiver.configure(sessionID: sessionID, invalidate: { [weak channel] in channel?.invalidate() }) else {
            throw ProbeFailure.duplicateActivation
        }
        eventReceiver = delegate.receiver
        let subscribe = ProbeRequest(requestID: UUID(), operation: "subscribe", payload: sessionID.uuidString)
        let subscribed = try await send(subscribe, over: channel)
        guard !deactivated, subscribed.requestID == subscribe.requestID, subscribed.value == subscribe.payload,
              subscribed.providerPID == response.providerPID else {
            throw ProbeFailure.invalidResponse
        }
        watchdog?.cancel()
        let application = NSRunningApplication(processIdentifier: response.providerPID)
        emit(["status": "OBSERVATION", "event": "sceneActivated", "hostPID": getpid(),
              "providerPID": response.providerPID, "runningApplicationAvailable": application != nil,
              "applicationBundle": application?.bundleIdentifier ?? "nil"])
        // Interactive probe has an external owner; this guard prevents a forgotten fixture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { NSApplication.shared.terminate(nil) }
    }

    static func send(_ request: ProbeRequest, over connection: NSXPCConnection) async throws -> ProbeResponse {
        let bytes = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let reply = ProbeReply(continuation)
            let timeout = DispatchWorkItem {
                connection.invalidate()
                reply.finish(.failure(ProbeFailure.timeout))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timeout)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                timeout.cancel()
                reply.finish(.failure(error))
            }) as? ProbeChannel else {
                timeout.cancel()
                reply.finish(.failure(ProbeFailure.missingProxy))
                return
            }
            proxy.request(bytes) { data in
                timeout.cancel()
                do {
                    guard data.count <= ProbeCounterReducer.maximumBytes else { throw ProbeFailure.invalidResponse }
                    reply.finish(.success(try JSONDecoder().decode(ProbeResponse.self, from: data)))
                } catch { reply.finish(.failure(error)) }
            }
        }
    }

    static func deactivate() {
        deactivated = true
        listenerDelegate?.fail(ProbeFailure.invalidResponse)
        eventReceiver?.failClosed()
        connection?.invalidate()
        bootstrap?.invalidate()
        listener?.invalidate()
        eventReceiver = nil
        connection = nil
        bootstrap = nil
        listenerDelegate = nil
        listener = nil
    }

    nonisolated static func emit(_ value: [String: Any]) {
        outputLock.lock()
        defer { outputLock.unlock() }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }
}

/// ProbeListenerDelegate serializes delivery of the single authenticated channel from the listener.
final class ProbeListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let lock = NSLock()
    private var delivered = false
    private var accepted: ((NSXPCConnection) -> Void)?
    private var failed: ((Error) -> Void)?
    let receiver = ProbeEventReceiverService()

    func prepare(accepted: @escaping (NSXPCConnection) -> Void, failed: @escaping (Error) -> Void) {
        lock.lock()
        self.accepted = accepted
        self.failed = failed
        lock.unlock()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lock.lock()
        guard !delivered else { lock.unlock(); return false }
        delivered = true
        let callback = accepted
        lock.unlock()
        connection.remoteObjectInterface = NSXPCInterface(with: ProbeChannel.self)
        connection.exportedInterface = NSXPCInterface(with: ProbeEventReceiver.self)
        connection.exportedObject = receiver
        connection.interruptionHandler = { [weak receiver] in receiver?.failClosed() }
        connection.invalidationHandler = { [weak receiver] in receiver?.failClosed() }
        connection.resume()
        callback?(connection)
        return true
    }

    func fail(_ error: Error) {
        lock.lock()
        guard !delivered else { lock.unlock(); return }
        delivered = true
        let callback = failed
        lock.unlock()
        callback?(error)
    }
}

final class ProbeEventReceiverService: NSObject, ProbeEventReceiver {
    private let lock = NSLock()
    private var reducer: ProbeCounterReducer?
    private var invalidated = false
    private var invalidate: (() -> Void)?
    private let observe: ([String: Any]) -> Void

    init(observe: @escaping ([String: Any]) -> Void = ProbeHost.emit) {
        self.observe = observe
    }

    func configure(sessionID: UUID, invalidate: @escaping () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard reducer == nil, !invalidated else { return false }
        reducer = ProbeCounterReducer(sessionID: sessionID)
        self.invalidate = invalidate
        return true
    }

    func receive(_ data: Data, reply: @escaping (Data) -> Void) {
        lock.lock()
        guard !invalidated, var reducer else {
            let invalidate = terminateLocked()
            lock.unlock()
            reply(Data())
            invalidate?()
            return
        }
        let ack = reducer.accept(data)
        self.reducer = reducer
        let reject = ack == nil || ack?.terminal == true
        let invalidate = reject ? terminateLocked() : nil
        lock.unlock()

        if let ack, ack.accepted,
           let event = try? JSONDecoder().decode(ProbeCounterEvent.self, from: data) {
            observe(["status": "OBSERVATION", "event": "counterChanged",
                            "sessionID": event.sessionID.uuidString,
                            "sequence": event.sequence, "action": event.action.rawValue,
                            "count": event.count])
        }
        reply(ack.flatMap { try? JSONEncoder().encode($0) } ?? Data())
        if reject { invalidate?() }
    }

    func failClosed() {
        lock.lock()
        let invalidate = terminateLocked()
        lock.unlock()
        invalidate?()
    }

    /// terminateLocked retires authority before invoking the external callback; the caller holds the lock.
    private func terminateLocked() -> (() -> Void)? {
        invalidated = true
        reducer = nil
        let callback = invalidate
        invalidate = nil
        return callback
    }
}

/// ProbeReply delivers a continuation at most once, because error, invalidation and reply can race.
final class ProbeReply {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProbeResponse, Error>?
    init(_ continuation: CheckedContinuation<ProbeResponse, Error>) { self.continuation = continuation }
    func finish(_ result: Result<ProbeResponse, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

@MainActor
final class ProbeSceneDelegate: NSObject, EXHostViewControllerDelegate {
    func hostViewControllerDidActivate(_ viewController: EXHostViewController) {
        ProbeHost.emit(["event": "sceneDelegateActivated"])
        Task {
            do { try await ProbeHost.sceneActivated(viewController) }
            catch { ProbeHost.emit(["status": "FAIL", "reason": String(describing: error)]); exit(1) }
        }
    }
    func hostViewControllerWillDeactivate(_ viewController: EXHostViewController, error: Error?) {
        ProbeHost.deactivate()
        ProbeHost.emit(["event": "sceneDeactivated", "reason": error.map(String.init(describing:)) ?? "none"])
    }
}
