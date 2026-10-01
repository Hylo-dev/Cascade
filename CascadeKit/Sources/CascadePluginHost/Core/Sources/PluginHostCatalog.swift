//
//  PluginHostCatalog.swift
//  CascadeKit
//

/// PluginHostCatalog is the catalog sources PluginHost implements. Cascade offers exactly these
/// names to plugins as hosted sources, so a feature that needs one PluginHost lacks is
/// unavailable instead of waiting for states that never come.
public enum PluginHostCatalog {

    public static let names: Set<String> = ["power"]

    /// sources builds the sources, by name, for PluginHost's runtime.
    public static func sources() -> [String: any PluginCatalogSource] {
        ["power": PowerSource()]
    }
}
