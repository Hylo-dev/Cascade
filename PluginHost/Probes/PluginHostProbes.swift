//
//  PluginHostProbes.swift
//  PluginHost
//

#if DEBUG
import CascadePluginSDK

/// PluginHostProbes are the plugins a Debug PluginHost carries for the integration tests: one
/// that answers with its host's PID, one that never returns from `handle()`, and one that ends
/// the process inside it. A Release PluginHost has none of them.
enum PluginHostProbes {

    static let providers: [String: any PluginProvider] = [
        "ProbeEcho": EchoProbe(),
        "ProbeHang": HangProbe(),
        "ProbeExit": ExitProbe(),
        "ProbeTrap": TrapProbe(),
    ]
}
#endif
