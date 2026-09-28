//
//  VisibleActivityProjection.swift
//  CascadeKit
//

/// VisibleActivityProjection reports which exact provider instances remain
/// eligible after applying the coordinator's complete retained-root union.
struct VisibleActivityProjection {

    let accepted: [any NotchActivity]
    let rejected: [any NotchActivity]
}
