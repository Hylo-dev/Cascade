//
//  PluginSurfaces+Kind.swift
//  CascadeKit
//

extension PluginSurfaces {

    /// declares says whether the feature can appear on the given surface.
    public func declares(_ kind: PluginSurfaceKind) -> Bool {
        switch kind {
            case .widget  : widget != nil
            case .activity: activity != nil
            case .notice  : notice != nil
        }
    }
}
