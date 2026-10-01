//
//  main.swift
//  PluginHost
//

import CoreBluetooth
import Foundation

/// PluginHostService stands in for the bundled PluginHost XPC service. It accepts only the
/// host whose bundle identifier precedes ".Service" in its own, signed by the same team.
final class PluginHostService: NSObject, SpikeService, NSXPCListenerDelegate, CBCentralManagerDelegate {

    private let incarnation = UUID().uuidString
    private let bluetoothQueue = DispatchQueue(label: "spike.bluetooth")

    private var central         : CBCentralManager?
    private var pendingBluetooth: ((Int) -> Void)?

    func listener(
        _ listener                    : NSXPCListener,
        shouldAcceptNewConnection peer: NSXPCConnection
    ) -> Bool {
        let own  = Bundle.main.bundleIdentifier ?? ""
        let host = own.hasSuffix(".Service") ? String(own.dropLast(".Service".count)) : ""

        peer.setCodeSigningRequirement(SpikeIdentity.requirement(identifier: host))
        peer.exportedInterface = NSXPCInterface(with: SpikeService.self)
        peer.exportedObject    = self
        peer.resume()

        return true
    }

    func hello(reply: @escaping (Int32, String) -> Void) {
        reply(getpid(), incarnation)
    }

    func hang(reply: @escaping () -> Void) {
        while true {
            pause()
        }
    }

    func exitCooperatively() {
        exit(0)
    }

    func automation(
        bundleIdentifier: String,
        ask             : Bool,
        reply           : @escaping (Int32) -> Void
    ) {
        reply(automationStatus(bundleIdentifier: bundleIdentifier, ask: ask))
    }

    func send(
        bundleIdentifier: String,
        reply           : @escaping (Int32, String) -> Void
    ) {
        let (status, name) = applicationName(bundleIdentifier: bundleIdentifier)
        reply(status, name)
    }

    func bluetooth(
        request: Bool,
        reply  : @escaping (Int) -> Void
    ) {
        guard request else {
            reply(CBManager.authorization.rawValue)
            return
        }

        bluetoothQueue.async {
            self.pendingBluetooth = reply
            self.central          = CBCentralManager(delegate: self, queue: self.bluetoothQueue)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state != .unknown, let reply = pendingBluetooth else { return }

        pendingBluetooth = nil
        reply(CBManager.authorization.rawValue)
    }
}

let service  = PluginHostService()
let listener = NSXPCListener.service()
listener.delegate = service
listener.resume()
