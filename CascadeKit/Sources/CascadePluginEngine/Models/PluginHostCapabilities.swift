//
//  PluginHostCapabilities.swift
//  CascadeKit
//

/// PluginHostCapabilities is what this Cascade provides: the catalog sources it implements, the
/// services plugins may call and the tier-2 components it can draw. A feature that needs
/// anything missing here is unavailable, because declared means required.
struct PluginHostCapabilities: Sendable {

    let sources   : Set<String>
    let services  : Set<String>
    let components: Set<String>
    let supportsFullscreen: Bool

    init(
        sources           : Set<String>,
        services          : Set<String>,
        components        : Set<String>,
        supportsFullscreen: Bool = false
    ) {
        self.sources            = sources
        self.services           = services
        self.components         = components
        self.supportsFullscreen = supportsFullscreen
    }
}
