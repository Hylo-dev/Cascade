//
//  HangProbe.swift
//  PluginHost
//

#if DEBUG
import CascadeContracts
import CascadePluginSDK
import Darwin

/// HangProbe never returns from `handle()`. It waits in `pause()` without spinning, as a plugin
/// stuck on a lock would, until the kernel's SIGKILL ends the process.
struct HangProbe: PluginProvider {

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        while true {
            pause()
        }
    }
}
#endif
