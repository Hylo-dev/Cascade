//
//  PluginInstant+Advanced.swift
//  CascadeKit
//

@testable import CascadePluginEngine

extension PluginInstant {

    /// advanced moves both clocks by the same number of seconds.
    func advanced(by seconds: Double) -> PluginInstant {
        PluginInstant(
            wall     : wall.addingTimeInterval(seconds),
            monotonic: monotonic + .seconds(seconds)
        )
    }
}
