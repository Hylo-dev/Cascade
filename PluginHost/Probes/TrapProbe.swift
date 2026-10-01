//
//  TrapProbe.swift
//  PluginHost
//

#if DEBUG
import CascadeContracts
import CascadePluginSDK

/// TrapProbe crashes PluginHost for real inside `handle()`, so a test can measure how long the
/// crash reporter keeps the dying process around before the kernel hears of the loss.
struct TrapProbe: PluginProvider {

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        fatalError("TrapProbe crashes PluginHost on purpose")
    }
}
#endif
