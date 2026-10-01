//
//  PluginIncident.swift
//  CascadeKit
//

/// PluginIncident is a failure the supervisor holds against a plugin.
public enum PluginIncident: Equatable, Sendable {

    case threw              // handle() threw, or the executor could not run it.
    case hung               // handle() outlived its deadline.
    case invalidPublication // A publication broke a rule the plugin could have known.
    case overBudget         // An event left the plugin in CPU debt.
}
