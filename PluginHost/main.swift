//
//  main.swift
//  PluginHost
//

import CascadePluginHost
import CascadePluginSDK
import CascadePlugins
import Foundation

// PluginHost runs Cascade's first-party plugins, each on its own thread, in a process of its
// own: a plugin that crashes or hangs costs a PluginHost restart, never Cascade. It accepts only
// the app it is bundled in, signed by its own team when it has one. It also runs the catalog
// sources the kernel leases, such as power, and sends their states back.

var providers = FirstPartyPlugins.providers
#if DEBUG
providers.merge(PluginHostProbes.providers) { current, _ in current }
#endif

let ownIdentifier = Bundle.main.bundleIdentifier ?? ""
let appIdentifier = ownIdentifier.hasSuffix(".PluginHost") ? String(ownIdentifier.dropLast(".PluginHost".count)) : ownIdentifier
let service       = PluginHostService(runner: PluginRunner(providers: providers), sources: PluginSourceRuntime(sources: PluginHostCatalog.sources()))
let delegate      = PluginHostListener(
    service    : service,
    requirement: PluginHostSigning.requirement(identifier: appIdentifier, team: PluginHostSigning.currentTeam)
)

let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
