//
//  ExitProbe.swift
//  PluginHost
//

#if DEBUG
import CascadeContracts
import CascadePluginSDK
import Darwin

/// ExitProbe ends PluginHost inside `handle()`, which is what the kernel sees of a crash, without
/// leaving a crash report behind every test run.
struct ExitProbe: PluginProvider {

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        _exit(1)
    }
}
#endif
