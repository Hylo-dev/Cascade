//
//  EchoProbe.swift
//  PluginHost
//

#if DEBUG
import CascadeContracts
import CascadePluginSDK
import Darwin

/// EchoProbe publishes its host's PID as text, so a test can tell one PluginHost from the next.
struct EchoProbe: PluginProvider {

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        try PluginOutput(
            publications: [
                PluginPublication(feature: "probe", surface: .widget, document: PluginDocument(root: PluginNode(.text(String(getpid()))))),
            ]
        )
    }
}
#endif
