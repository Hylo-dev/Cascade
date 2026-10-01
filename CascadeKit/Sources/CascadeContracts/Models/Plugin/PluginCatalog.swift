//
//  PluginCatalog.swift
//  CascadeKit
//

/// PluginCatalog lists what the host provides in v1: the sources that can wake a plugin and
/// the tier-2 components a document can show, each with its newest version. A manifest that
/// declares anything else fails validation, so a typo surfaces at build time instead of as a
/// feature that silently never starts.
public enum PluginCatalog {

    public static let sources: Set<String> = [
        "media.nowPlaying",
        "bluetooth",
        "power",
        "volume",
        "network",
        "net.webSocket",
        "net.sse",
    ]

    public static let components: [String: Int] = [
        "audio.spectrum"    : 1,
        "media.scrubber"    : 1,
        "audio.outputPicker": 1,
        "power.battery"     : 1,
        "volume.level"      : 1,
    ]
}
