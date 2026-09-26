//
//  ProbeProvider.swift
//  Cascade Addon Platform Probe
//

import ExtensionFoundation
import Foundation
import Darwin

/// ProbeConfiguration authenticates callers before exposing the fixed probe API.
struct ProbeConfiguration: AppExtensionConfiguration {
    nonisolated func accept(connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ProbeBootstrap.self)
        connection.exportedObject = ProbeBootstrapService()
        connection.resume()
        return true
    }
}

final class ProbeBootstrapService: NSObject, ProbeBootstrap {
    private var channel: NSXPCConnection?

    func connect(to endpoint: NSXPCListenerEndpoint) {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.setCodeSigningRequirement(ProbeIdentity.requirement(identifier: ProbeIdentity.host))
        connection.exportedInterface = NSXPCInterface(with: ProbeChannel.self)
        connection.exportedObject = ProbeService()
        connection.remoteObjectInterface = NSXPCInterface(with: ProbeReady.self)
        channel = connection
        connection.resume()
        (connection.remoteObjectProxy as? ProbeReady)?.ready()
    }
}

final class ProbeService: NSObject, ProbeChannel {
    func request(_ data: Data, reply: @escaping (Data) -> Void) {
        var operations = ["echo", "spin", "malformed", "checkpoint", "exit", "sandbox"]
        #if RECOVERY_PROBE
        operations += ["hold", "crash"]
        #endif
        guard data.count <= 65_536,
              let request = try? JSONDecoder().decode(ProbeRequest.self, from: data),
              operations.contains(request.operation) else {
            reply(Data())
            return
        }
        if request.operation == "malformed" { reply(Data("invalid-json".utf8)); return }
        var response = ProbeResponse(requestID: request.requestID, providerPID: getpid(), value: request.payload)
        #if RECOVERY_PROBE
        response.instance = RecoveryFixture.instance
        response.guardDeadline = RecoveryFixture.guardDeadline
        response.bundlePath = Bundle.main.bundleURL.path
        #endif
        if request.operation == "sandbox" {
            var checks: [String: Bool] = [:]
            // This is a newly-created, nonsensitive sentinel owned by the test harness.
            checks["foreignFixtureReadDenied"] = (try? Data(contentsOf: URL(fileURLWithPath: request.payload))) == nil
            let socketFD = socket(AF_INET, SOCK_STREAM, 0)
            if socketFD < 0 {
                checks["networkDenied"] = errno == EPERM || errno == EACCES
            } else {
                defer { close(socketFD) }
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = UInt16(9).bigEndian
                address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
                let result = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                checks["networkDenied"] = result < 0 && (errno == EPERM || errno == EACCES)
            }
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            do { try child.run(); child.waitUntilExit(); checks["subprocessDenied"] = false }
            catch { checks["subprocessDenied"] = true }
            response.observations = checks
        }
        reply((try? JSONEncoder().encode(response)) ?? Data())
        #if RECOVERY_PROBE
        if request.operation == "hold" { while true { pause() } }
        if request.operation == "crash" {
            if raise(SIGKILL) != 0 { _exit(84) }
            while true { pause() }
        }
        #endif
        if request.operation == "spin" {
            // Noncooperative worker bounded by the external test deadline/cleanup.
            DispatchQueue.global().async {
                while true { _ = arc4random() }
            }
        }
        if request.operation == "exit" { exit(0) }
    }
}

@main
struct ProbeProvider: AppExtension {
    init() {
        #if RECOVERY_PROBE
        _ = RecoveryFixture.guardDeadline
        #endif
        #if STARTUP_PROBE
        RecoveryFixture.instance.uuidString.withCString { startup_probe_park($0, RecoveryFixture.guardDeadline) }
        #endif
        NSLog("Cascade probe provider bundle=%@", Bundle.main.bundleURL.path)
    }
    var configuration: ProbeConfiguration { ProbeConfiguration() }
}

#if RECOVERY_PROBE
private enum RecoveryFixture {
    static let instance = UUID()
    static let guardDeadline = installRecoveryGuard(seconds: 25)
}
#endif
