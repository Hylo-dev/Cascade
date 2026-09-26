//
//  ProbeMessage.swift
//  Cascade Addon Platform Probe
//

import Foundation

/// Bootstrap carries only a fresh endpoint, never business requests or grants.
@objc(ProbeBootstrap)
protocol ProbeBootstrap {
    func connect(to endpoint: NSXPCListenerEndpoint)
}

@objc(ProbeReady)
protocol ProbeReady {
    func ready()
}

/// ProbeChannel keeps the experiment independent of production SDK types.
@objc(ProbeChannel)
protocol ProbeChannel {
    func request(_ data: Data, reply: @escaping (Data) -> Void)
}

struct ProbeRequest: Codable {
    let requestID: UUID
    let operation: String
    let payload: String
}

struct ProbeResponse: Codable {
    let requestID: UUID
    let providerPID: Int32
    let value: String
    var observations: [String: Bool]? = nil
    var instance: UUID? = nil
    var guardDeadline: Double? = nil
    var bundlePath: String? = nil
}

enum ProbeIdentity {
    static let point = "hylo.Cascade.AddonProbe.provider"
    static let provider = "hylo.Cascade.AddonProbeContainer.Provider"
    static let host = "hylo.Cascade.AddonProbe"
    static let team = "A6A5HQL6K4"

    static func requirement(identifier: String) -> String {
        #if RECOVERY_PROBE
        return "anchor apple generic and certificate leaf = H\"4A857D842A5406C2D3071776FDE7B27B3098FE63\" and identifier \"\(identifier)\""
        #else
        "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(identifier)\""
        #endif
    }
}

#if RECOVERY_PROBE
func installRecoveryGuard(seconds: UInt32) -> Double {
    var action = sigaction()
    action.__sigaction_u.__sa_handler = SIG_DFL
    var unblocked = sigset_t()
    guard sigemptyset(&action.sa_mask) == 0,
          sigaction(SIGALRM, &action, nil) == 0,
          sigemptyset(&unblocked) == 0,
          sigaddset(&unblocked, SIGALRM) == 0,
          pthread_sigmask(SIG_UNBLOCK, &unblocked, nil) == 0 else { _exit(96) }
    let deadline = recoveryTime() + Double(seconds)
    alarm(seconds)
    return deadline
}

func recoveryTime() -> Double {
    var value = timespec()
    precondition(clock_gettime(CLOCK_MONOTONIC, &value) == 0)
    return Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000
}
#endif
