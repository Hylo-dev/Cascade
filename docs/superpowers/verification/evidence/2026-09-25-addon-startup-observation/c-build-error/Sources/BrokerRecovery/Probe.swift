// Disposable app → sandboxed XPC broker → external ExtensionFoundation provider.
import AppKit
import ExtensionFoundation
import Foundation

let rootID = "hylo.Cascade.AddonProbe"
let brokerID = rootID + ".DiscoveryBroker"
enum Failure: Error { case invalidIdentity, missingProxy }

@objc protocol BrokerControl {
    func command(_ name: String, nonce: String, reply: @escaping (Data) -> Void)
}

@MainActor final class Session {
    let instance = UUID().uuidString
    let guardDeadline = installRecoveryGuard(seconds: 35)
    var process: AppExtensionProcess?
    var bootstrap: NSXPCConnection?
    var listener: NSXPCListener?
    var delegate: ProbeListenerDelegate?
    var channel: NSXPCConnection?
    #if STARTUP_PROBE
    var startupTask: Task<Void, Never>?
    var startupPhase = "idle"
    #endif

    func start() async throws {
        for await identities in try AppExtensionIdentity.matching(appExtensionPointIDs: ProbeIdentity.point) {
            let candidates = identities.filter { $0.bundleIdentifier == ProbeIdentity.provider }
            guard !candidates.isEmpty else { continue }
            guard candidates.count == 1, let identity = candidates.first else { throw Failure.invalidIdentity }
            #if STARTUP_PROBE
            startupPhase = "initializer-pending"
            #endif
            let process = try await AppExtensionProcess(configuration: .init(appExtensionIdentity: identity))
            self.process = process
            #if STARTUP_PROBE
            startupPhase = "process-ready"
            #endif
            let listener = NSXPCListener.anonymous()
            listener.setConnectionCodeSigningRequirement(ProbeIdentity.requirement(identifier: ProbeIdentity.provider))
            let delegate = ProbeListenerDelegate()
            self.listener = listener; self.delegate = delegate
            listener.delegate = delegate; listener.resume()
            let bootstrap = try process.makeXPCConnection()
            self.bootstrap = bootstrap
            bootstrap.remoteObjectInterface = NSXPCInterface(with: ProbeBootstrap.self)
            bootstrap.resume()
            channel = try await withCheckedThrowingContinuation { continuation in
                delegate.prepare(accepted: { continuation.resume(returning: $0) }, failed: { continuation.resume(throwing: $0) })
                guard let proxy = bootstrap.remoteObjectProxyWithErrorHandler({ delegate.fail($0) }) as? ProbeBootstrap
                else { delegate.fail(Failure.missingProxy); return }
                proxy.connect(to: listener.endpoint)
            }
            #if STARTUP_PROBE
            startupPhase = "channel-ready"
            #endif
            return
        }
        throw Failure.missingProxy
    }

    func command(_ name: String, nonce: String) async throws -> [String: Any] {
        var report: [String: Any] = ["nonce": nonce, "brokerPID": getpid(), "brokerInstance": instance,
            "brokerGuard": guardDeadline, "brokerPath": Bundle.main.bundleURL.path]
        #if STARTUP_PROBE
        report["startupPhase"] = startupPhase
        if name == "begin-startup" {
            guard startupTask == nil else { throw Failure.invalidIdentity }
            startupTask = Task { @MainActor in
                do { try await start() }
                catch { startupPhase = "failed: \(error)" }
            }
            return report
        }
        if name == "crash-broker" {
            if raise(SIGKILL) != 0 { exit(84) }
            while true { pause() }
        }
        #endif
        if name == "broker-info" { return report }
        if name == "stop-broker" { exit(0) }
        if name == "invalidate" || name == "release" {
            channel?.invalidate(); bootstrap?.invalidate(); listener?.invalidate(); process?.invalidate()
            channel = nil; bootstrap = nil; listener = nil; delegate = nil; process = nil
            return report
        }
        if name == "finish-provider" {
            guard let channel else { throw Failure.missingProxy }
            let request = ProbeRequest(requestID: UUID(), operation: "exit", payload: nonce)
            guard let proxy = channel.remoteObjectProxyWithErrorHandler({ _ in }) as? ProbeChannel
            else { throw Failure.missingProxy }
            proxy.request(try JSONEncoder().encode(request)) { _ in }
            // Only confirms dispatch. The external observer must confirm the exit.
            return report
        }
        guard name == "hello" || name == "hold" else { throw Failure.missingProxy }
        if channel == nil { try await start() }
        guard let channel else { throw Failure.missingProxy }
        let request = ProbeRequest(requestID: UUID(), operation: name == "hello" ? "echo" : "hold", payload: nonce)
        let data = try JSONEncoder().encode(request)
        let response: ProbeResponse = try await withCheckedThrowingContinuation { continuation in
            let reply = ProbeReply(continuation)
            guard let proxy = channel.remoteObjectProxyWithErrorHandler({ reply.finish(.failure($0)) }) as? ProbeChannel
            else { reply.finish(.failure(Failure.missingProxy)); return }
            proxy.request(data) { bytes in
                do {
                    guard bytes.count <= 65536 else { throw Failure.invalidIdentity }
                    reply.finish(.success(try JSONDecoder().decode(ProbeResponse.self, from: bytes)))
                } catch { reply.finish(.failure(error)) }
            }
        }
        guard response.requestID == request.requestID, response.value == nonce,
              response.providerPID == channel.processIdentifier, response.providerPID != getpid(),
              let instance = response.instance, let deadline = response.guardDeadline,
              let path = response.bundlePath else { throw Failure.invalidIdentity }
        report["provider"] = ["pid": response.providerPID, "instance": instance.uuidString,
                              "guardDeadline": deadline, "bundlePath": path, "authenticated": true]
        return report
    }
}

final class Service: NSObject, BrokerControl, NSXPCListenerDelegate {
    @MainActor static let session = Session()
    func command(_ name: String, nonce: String, reply: @escaping (Data) -> Void) {
        Task { @MainActor in
            do { reply(try JSONSerialization.data(withJSONObject: try await Self.session.command(name, nonce: nonce))) }
            catch { reply(try! JSONSerialization.data(withJSONObject: ["error": String(reflecting: error)])) }
        }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(ProbeIdentity.requirement(identifier: rootID))
        connection.exportedInterface = NSXPCInterface(with: BrokerControl.self)
        connection.exportedObject = self; connection.resume()
        return true
    }
}

@main @MainActor enum Probe {
    static var connection: NSXPCConnection?
    static var stoppingBroker = false
    static func main() {
        _ = installRecoveryGuard(seconds: 45)
        #if BROKER
        _ = Service.session
        let listener = NSXPCListener.service()
        let service = Service(); listener.delegate = service
        withExtendedLifetime(service) { listener.resume(); RunLoop.current.run() }
        #else
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        connectBroker()
        emit(["event": "client-ready"])
        DispatchQueue.global().async {
            while let command = readLine() { Task { @MainActor in perform(command) } }
        }
        app.run()
        #endif
    }
    static func connectBroker() {
        let connection = NSXPCConnection(serviceName: brokerID)
        connection.setCodeSigningRequirement(ProbeIdentity.requirement(identifier: brokerID))
        connection.remoteObjectInterface = NSXPCInterface(with: BrokerControl.self)
        self.connection = connection; connection.resume()
    }
    static func perform(_ name: String) {
        if name == "ping" { emit(["event": "ping", "pid": getpid()]); return }
        if name == "quit" { emit(["event": "quit"]); exit(0) }
        if name == "crash" {
            emit(["event": "crash"])
            if raise(SIGKILL) != 0 { exit(84) }
            while true { pause() }
        }
        // The external observer authorizes this only after both registered exits.
        if name == "restart", stoppingBroker {
            connection?.invalidate(); connection = nil
            stoppingBroker = false
            connectBroker()
            emit(["event": "restart"])
            return
        }
        guard let connection else { emit(["event": "response-error"]); return }
        let nonce = UUID().uuidString
        if name == "stop-broker" || name == "crash-broker" { stoppingBroker = true; emit(["event": name]) }
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            Task { @MainActor in
                guard self.connection === connection else { return }
                emit(["event": stoppingBroker ? "broker-unavailable" : "response-error",
                      "error": String(reflecting: error)])
            }
        } as! BrokerControl
        proxy.command(name, nonce: nonce) { bytes in
            guard bytes.count <= 16384, var report = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  report["nonce"] as? String == nonce,
                  report["brokerPID"] as? Int32 == connection.processIdentifier,
                  report["brokerPath"] as? String == Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/DiscoveryBroker.xpc").path
            else { emit(["event": "response-error", "details": String(data: bytes.prefix(16384), encoding: .utf8) ?? "invalid"]); return }
            if name == "hello" || name == "hold" {
                guard let provider = report["provider"] as? [String: Any], provider["authenticated"] as? Bool == true,
                      provider["bundlePath"] as? String == ProcessInfo.processInfo.environment["CASCADE_RECOVERY_PROVIDER_BUNDLE"]
                else { emit(["event": "response-error", "reason": "wrong provider path"]); return }
            }
            report["event"] = name; report["authenticated"] = true
            emit(report)
        }
    }
}

func emit(_ value: [String: Any]) {
    FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) + Data([10]))
}
