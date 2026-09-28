//
//  Probe.swift
//  Cascade Addon Platform Probe
//

// Disposable discovery-only fixture. Never creates AppExtensionProcess.
import AppKit
import ExtensionFoundation
import ExtensionKit
import Foundation

let hostID = "hylo.Cascade.AddonProbe"
let brokerID = "hylo.Cascade.AddonProbe.DiscoveryBroker"
let pointID = "hylo.Cascade.AddonProbe.provider"
let signer = "4A857D842A5406C2D3071776FDE7B27B3098FE63"

func requirement(_ identifier: String) -> String {
    "anchor apple generic and identifier \"\(identifier)\" and certificate leaf = H\"\(signer)\""
}

@objc protocol DiscoveryChannel {
    func discover(_ nonce: String, browse: Bool, reply: @escaping (Data) -> Void)
}

@MainActor var browserWindow: NSWindow?

@MainActor
func collect(_ nonce: String) async -> Data {
    var result: [String: Any] = ["nonce": nonce, "pid": getpid(),
        "bundleID": Bundle.main.bundleIdentifier ?? "nil", "bundleURL": Bundle.main.bundleURL.path,
        "legacy": ["status": "no-update"], "modern": ["status": "no-update"]]
    let legacy = Task { @MainActor in
        do {
            for await identities in try AppExtensionIdentity.matching(appExtensionPointIDs: pointID) {
                result["legacy"] = ["status": "observed", "identities": identities.map(\.bundleIdentifier)]
            }
        } catch {
            result["legacy"] = ["status": "error", "error": String(reflecting: error)]
        }
    }
    let modern = Task { @MainActor in
        if #available(macOS 26, *) {
            do {
                let point = try AppExtensionPoint(identifier: "hylo.Cascade.AddonProbe.provider")
                let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: point)
                // Keep the monitor alive for the sampling interval.
                for _ in 0..<18 {
                    let state = monitor.state
                    result["modern"] = ["status": "observed", "identities": state.identities.map(\.bundleIdentifier),
                                        "disabled": state.disabledCount, "unapproved": state.unapprovedCount]
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            } catch {
                if !(error is CancellationError) {
                    result["modern"] = ["status": "error", "error": String(reflecting: error)]
                }
            }
        } else { result["modern"] = ["status": "unavailable"] }
    }
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    legacy.cancel(); modern.cancel()
    return try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
}

final class DiscoveryService: NSObject, DiscoveryChannel, NSXPCListenerDelegate {
    func discover(_ nonce: String, browse: Bool, reply: @escaping (Data) -> Void) {
        Task { @MainActor in
            if browse {
                NSApplication.shared.setActivationPolicy(.accessory)
                let window = NSWindow(contentViewController: EXAppExtensionBrowserViewController())
                window.title = "Cascade — broker discovery probe"
                window.setContentSize(NSSize(width: 640, height: 440))
                window.center(); window.makeKeyAndOrderFront(nil)
                browserWindow = window
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            reply(await collect(nonce))
        }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement(hostID))
        connection.exportedInterface = NSXPCInterface(with: DiscoveryChannel.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

@main enum Probe {
    @MainActor static var channel: NSXPCConnection?
    @MainActor static func main() {
        signal(SIGALRM, SIG_DFL)
        alarm(90)
        #if BROKER
        let listener = NSXPCListener.service()
        let service = DiscoveryService()
        listener.delegate = service
        withExtendedLifetime(service) { listener.resume(); RunLoop.current.run() }
        #else
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let nonce = UUID().uuidString
            let control = await collect(nonce)
            emit(["event": "app-control", "report": try! JSONSerialization.jsonObject(with: control)])
            let connection = NSXPCConnection(serviceName: brokerID)
            connection.setCodeSigningRequirement(requirement(brokerID))
            connection.remoteObjectInterface = NSXPCInterface(with: DiscoveryChannel.self)
            channel = connection
            connection.resume()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                emit(["event": "channel-error", "error": String(reflecting: error)])
                exit(2)
            } as! DiscoveryChannel
            let browse = CommandLine.arguments.contains("--broker-browser")
            proxy.discover(nonce, browse: browse) { bytes in
                guard bytes.count < 16384,
                      let report = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      report["nonce"] as? String == nonce,
                      report["pid"] as? Int32 == connection.processIdentifier,
                      report["bundleID"] as? String == brokerID else {
                    emit(["event": "invalid-broker-response"]); exit(3)
                }
                emit(["event": "broker-discovery", "authenticated": true, "report": report])
                if browse {
                    // Retain the process and window for bounded manual inspection only.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 60) { exit(0) }
                } else { exit(0) }
            }
        }
        app.run()
        #endif
    }
}

func emit(_ value: [String: Any]) {
    let bytes = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(bytes + Data([10]))
}
