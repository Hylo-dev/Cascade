//
//  ProbeHost.swift
//  Cascade Addon Platform Probe
//

import AppKit
import ExtensionFoundation
import ExtensionKit
import Foundation

enum ProbeFailure: Error { case invalidResponse, unexpectedIdentity, missingProxy }

/// ProbeHost exercises a system-launched process; stdout is the test evidence.
@main
@MainActor
enum ProbeHost {
    static var extensionProcess: AppExtensionProcess?
    static var connection: NSXPCConnection?
    static var window: NSWindow?
    static var listener: NSXPCListener?
    static var listenerDelegate: ProbeListenerDelegate?
    static var bootstrap: NSXPCConnection?
    static var watchdog: DispatchWorkItem?
    static let caseName = CommandLine.arguments.dropFirst().first ?? "standalone-echo"
    #if RECOVERY_PROBE
    static var launchNonce = ""
    static weak var releasedChannel: NSXPCConnection?
    static weak var releasedBootstrap: NSXPCConnection?
    static weak var releasedListener: NSXPCListener?
    static weak var releasedDelegate: ProbeListenerDelegate?
    #endif

    static func main() {
        #if RECOVERY_PROBE
        if caseName == "recovery-guard-check" {
            var inherited = sigset_t()
            guard pthread_sigmask(SIG_BLOCK, nil, &inherited) == 0 else { _exit(96) }
            emit(["event":"guard-check", "inheritedAlarmBlocked":sigismember(&inherited, SIGALRM) == 1])
            _ = installRecoveryGuard(seconds: 1)
            while true { pause() }
        }
        _ = installRecoveryGuard(seconds: 35)
        #endif
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
            #if RECOVERY_PROBE
            let nonce = UUID().uuidString
            launchNonce = nonce
            // Capture only the request nonce, never a process/channel owner.
            let process = try await AppExtensionProcess(configuration: .init(appExtensionIdentity: identity,
                onInterruption: { RecoveryNotifications.record(nonce: nonce) }))
            #else
            let process = try await AppExtensionProcess(configuration: .init(appExtensionIdentity: identity))
            #endif
            extensionProcess = process
            let listener = NSXPCListener.anonymous()
            listener.setConnectionCodeSigningRequirement(ProbeIdentity.requirement(identifier: ProbeIdentity.provider))
            let delegate = ProbeListenerDelegate()
            listener.delegate = delegate
            self.listener = listener
            listenerDelegate = delegate
            listener.resume()
            let bootstrap = try process.makeXPCConnection()
            bootstrap.remoteObjectInterface = NSXPCInterface(with: ProbeBootstrap.self)
            self.bootstrap = bootstrap
            bootstrap.resume()
            let channel = try await withCheckedThrowingContinuation { continuation in
                delegate.prepare(accepted: { continuation.resume(returning: $0) }, failed: { continuation.resume(throwing: $0) })
                guard let proxy = bootstrap.remoteObjectProxyWithErrorHandler({ error in
                    delegate.fail(error)
                }) as? ProbeBootstrap else {
                    delegate.fail(ProbeFailure.missingProxy)
                    return
                }
                proxy.connect(to: listener.endpoint)
            }
            connection = channel
            #if RECOVERY_PROBE
            if caseName == "recovery" {
                watchdog?.cancel()
                emit(["event": "client-ready", "launchNonce": nonce])
                DispatchQueue.global().async {
                    while let command = readLine() {
                        Task { @MainActor in await recoveryCommand(command) }
                    }
                }
                return
            }
            #endif
            let operation = caseName.contains("spin") ? "spin" : (["malformed", "sandbox"].contains(caseName) ? caseName : "echo")
            let payload = caseName == "sandbox" ? (ProcessInfo.processInfo.environment["CASCADE_PROBE_FOREIGN_FILE"] ?? "") : "cascade-native-probe"
            let request = ProbeRequest(requestID: UUID(), operation: operation, payload: payload)
            let response = try await send(request, over: channel)
            guard response.requestID == request.requestID,
                  response.value == request.payload,
                  response.providerPID == channel.processIdentifier,
                  response.providerPID != getpid() else { throw ProbeFailure.unexpectedIdentity }
            watchdog?.cancel()
            if caseName.contains("spin") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    emit(["status": "FAIL", "reason": "external harness did not finish the bounded spin case"])
                    exit(2)
                }
            }
            emit(["status": caseName == "standalone-echo" ? "PASS" : "OBSERVATION", "case": caseName, "requestID": request.requestID.uuidString,
                  "hostPID": getpid(), "providerPID": response.providerPID,
                  "peerRequirement": ProbeIdentity.requirement(identifier: ProbeIdentity.provider)])
            if let observations = response.observations { emit(["event": "sandbox", "observations": observations]) }
            if caseName == "application-stop-spin" {
                guard let application = NSRunningApplication(processIdentifier: response.providerPID) else {
                    emit(["status": "FAIL", "reason": "authenticated extension has no NSRunningApplication handle",
                          "applicationHandlePresent": false, "forceTerminateInvoked": false])
                    return
                }
                guard application.bundleIdentifier == ProbeIdentity.provider,
                      application.executableURL?.lastPathComponent == "ProbeProvider" else {
                    emit(["status": "FAIL", "reason": "running application handle does not identify the authenticated fixture",
                          "applicationBundle": application.bundleIdentifier ?? "nil"])
                    return
                }
                let requested = application.forceTerminate()
                emit(["event": "applicationStopRequested", "requested": requested,
                      "applicationHandlePresent": true, "forceTerminateInvoked": true,
                      "providerPID": response.providerPID])
                // The harness observes real exit; request acceptance is not success.
                return
            }
            if caseName == "normal-host-spin" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NSApplication.shared.terminate(nil)
                }
                return
            }
            if caseName == "crash-host-spin" {
                // External supervisor kills this host after recording its provider PID.
                return
            }
            channel.invalidate()
            bootstrap.invalidate()
            listener.invalidate()
            process.invalidate()
            connection = nil
            extensionProcess = nil
            self.bootstrap = nil
            self.listener = nil
            listenerDelegate = nil
            if caseName == "invalidate-spin" {
                emit(["event": "invalidated", "providerPID": response.providerPID])
                // Keep host alive while the supervisor observes the actual exit.
                return
            }
            exit(0)
        }
    }

    static func send(_ request: ProbeRequest, over connection: NSXPCConnection) async throws -> ProbeResponse {
        let bytes = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let reply = ProbeReply(continuation)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                reply.finish(.failure(error))
            }) as? ProbeChannel else {
                reply.finish(.failure(ProbeFailure.missingProxy))
                return
            }
            proxy.request(bytes) { data in
                do {
                    guard data.count <= 65_536 else { throw ProbeFailure.invalidResponse }
                    reply.finish(.success(try JSONDecoder().decode(ProbeResponse.self, from: data)))
                } catch { reply.finish(.failure(error)) }
            }
        }
    }

    #if RECOVERY_PROBE
    static func recoveryCommand(_ command: String) async {
        switch command {
        case "hello", "hold":
            do {
                guard let connection else { throw ProbeFailure.missingProxy }
                let request = ProbeRequest(requestID: UUID(), operation: command == "hello" ? "echo" : "hold", payload: UUID().uuidString)
                let response = try await send(request, over: connection)
                guard response.requestID == request.requestID, response.value == request.payload,
                      response.providerPID == connection.processIdentifier,
                      response.providerPID != getpid(), let instance = response.instance,
                      let deadline = response.guardDeadline,
                      let bundlePath = response.bundlePath,
                      bundlePath == ProcessInfo.processInfo.environment["CASCADE_RECOVERY_PROVIDER_BUNDLE"]
                else { throw ProbeFailure.unexpectedIdentity }
                emit(["event": command, "authenticated": true, "pid": response.providerPID,
                      "instance": instance.uuidString, "guardDeadline": deadline,
                      "bundlePath":bundlePath, "time": recoveryTime()])
            } catch { emit(["event":"response-error", "error":String(reflecting:error)]) }
        case "invalidate", "release":
            releasedChannel = connection; releasedBootstrap = bootstrap
            releasedListener = listener; releasedDelegate = listenerDelegate
            connection?.invalidate(); bootstrap?.invalidate(); listener?.invalidate()
            if command == "invalidate" { extensionProcess?.invalidate() }
            connection = nil; bootstrap = nil; listener = nil; listenerDelegate = nil; extensionProcess = nil
            emit(["event":"invalidated", "time":recoveryTime()])
        case "provider-exit", "provider-crash":
            guard let connection else { emit(["event":"response-error"]); return }
            emit(["event":"provider-stop-requested", "time":recoveryTime()])
            let request = ProbeRequest(requestID: UUID(), operation: command == "provider-exit" ? "exit" : "crash", payload: UUID().uuidString)
            do { _ = try await send(request, over: connection); emit(["event":"stop-reply"]) }
            catch { emit(["event":"stop-reply-unavailable", "detail":String(reflecting:error)]) }
        case "observation":
            let notifications = RecoveryNotifications.snapshot()
            emit(["event":"observation", "time":recoveryTime(), "launchNonce":launchNonce,
                  "notifications":notifications,
                  "ownedReferences":["process":extensionProcess != nil,"channel":connection != nil,
                    "bootstrap":bootstrap != nil,"listener":listener != nil,"delegate":listenerDelegate != nil],
                  "releasedReferencesStillAlive":["channel":releasedChannel != nil,"bootstrap":releasedBootstrap != nil,
                    "listener":releasedListener != nil,"delegate":releasedDelegate != nil]])
        case "ping": emit(["event":"ping", "time":recoveryTime()])
        case "quit": emit(["event":"quit", "time":recoveryTime()]); exit(0)
        case "crash":
            emit(["event":"crash", "time":recoveryTime()])
            if raise(SIGKILL) != 0 { exit(84) }
            while true { pause() }
        default: emit(["event":"command-error"])
        }
    }
    #endif

    static func emit(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }
}

#if RECOVERY_PROBE
/// RecoveryNotifications records recovery notifications under a lock, because the callback may run
/// on any queue; storage does not retain its process or channels.
private enum RecoveryNotifications {
    static let lock = NSLock()
    static var values: [[String: Any]] = []
    static func record(nonce: String) {
        lock.lock(); defer { lock.unlock() }
        values.append(["nonce":nonce,"time":recoveryTime()])
    }
    static func snapshot() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}
#endif
