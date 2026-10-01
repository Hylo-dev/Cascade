//
//  PluginHealthReaction.swift
//  CascadeKit
//

/// PluginHealthReaction is what the supervisor does about an incident.
public enum PluginHealthReaction: Equatable, Sendable {

    case keep                   // Carry on.
    case retry(after: Duration) // Pause, then start again with a refresh.
    case disable                // Stop until the user re-enables it.
    case quarantine             // Stop until the user re-enables it, with its history cleared then.
}
