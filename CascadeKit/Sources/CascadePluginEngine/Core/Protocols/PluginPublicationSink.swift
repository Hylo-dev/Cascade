//
//  PluginPublicationSink.swift
//  CascadeKit
//

/// PluginPublicationSink is where the engine sends what changed on screen and the actions it
/// refused. It is called on the engine's queue and must return at once; the renderer makes its
/// own single hop to the main thread.
public protocol PluginPublicationSink: Sendable {

    func deliver(_ changes: [PluginPublicationChange])

    func reject(_ request: PluginActionRequest)
}
