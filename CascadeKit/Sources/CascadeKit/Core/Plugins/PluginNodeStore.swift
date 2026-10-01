//
//  PluginNodeStore.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginEngine
import Foundation
import Observation
import SwiftUI

/// PluginNodeStore renders one publication: one `PluginNodeModel` per node, updated from the
/// kernel's diffs on the main thread. Only the models a diff names are touched, so only their
/// views are invalidated. The dictionary of models is not observed: a parent whose children
/// change is itself in the diff and rebuilds its child views, and a node that did not change is
/// never looked at.
///
/// The store also owns the optimistic state of controls. A toggle, or a slider on release, shows
/// its new value at once and sends the action; the next publication always wins, and with no
/// publication within `confirmationTimeout`, or when the kernel refuses the action, the value
/// reverts. While a slider is dragged, publications do not move its thumb.
@Observable
final class PluginNodeStore {

    static let confirmationTimeout = Duration.milliseconds(1_500)

    let key: PluginPublicationKey

    private(set) var revision   : UInt64 = 0
    private(set) var root       : PluginNodeModel?
    private(set) var glassLights: [GlassLight] = []

    @ObservationIgnored private var models     : [PluginNodeID: PluginNodeModel] = [:]
    @ObservationIgnored private var generations: [PluginNodeID: UInt64] = [:]

    private let submit  : (PluginActionRequest) -> Void
    private let schedule: (Duration, @escaping @MainActor () -> Void) -> Void

    init(
        key     : PluginPublicationKey,
        submit  : @escaping (PluginActionRequest) -> Void,
        schedule: @escaping (Duration, @escaping @MainActor () -> Void) -> Void = { delay, task in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / .seconds(1)) {
                MainActor.assumeIsolated(task)
            }
        }
    ) {
        self.key      = key
        self.submit   = submit
        self.schedule = schedule
    }

    func model(_ id: PluginNodeID) -> PluginNodeModel? {
        models[id]
    }

    /// apply takes one change from the kernel. Removed nodes lose their models, inserted nodes
    /// get new ones, updated nodes have theirs refreshed, and every control but a dragged slider
    /// drops its optimistic value, because the publication is the source of truth.
    func apply(_ change: PluginPublicationChange) {
        revision = change.revision

        guard let content = change.content else {
            models.removeAll()
            root        = nil
            glassLights = []
            return
        }

        let table = content.table
        for id in content.diff.removed {
            models.removeValue(forKey: id)
        }
        for id in content.diff.inserted {
            if let index = table.index(of: id) {
                models[id] = PluginNodeModel(table.entries[index], in: table)
            }
        }
        for id in content.diff.updated {
            if let index = table.index(of: id) {
                models[id]?.update(table.entries[index], in: table)
            }
        }

        for model in models.values where model.optimistic != nil && !model.isDragging {
            generations[model.id, default: 0] += 1
            model.optimistic = nil
        }

        if root?.id != table.root.id {
            root = models[table.root.id]
        }
        if glassLights != content.document.glassLights {
            glassLights = content.document.glassLights
        }
    }

    /// press sends a button's action. A button holds no state: SwiftUI shows the press, and
    /// whatever the action changes arrives as the next publication.
    func press(_ model: PluginNodeModel) {
        submit(PluginActionRequest(key: key, node: model.id, revision: revision))
    }

    /// set shows a control's new value at once, sends the action, and arms the revert.
    func set(
        _ value : PluginValue,
        on model: PluginNodeModel
    ) {
        generations[model.id, default: 0] += 1
        let generation = generations[model.id]

        withAnimation(.snappy) {
            model.optimistic = value
        }
        submit(PluginActionRequest(key: key, node: model.id, revision: revision, value: value))

        schedule(Self.confirmationTimeout) { [weak self, weak model] in
            guard let self, let model, generations[model.id] == generation else { return }

            revert(model)
        }
    }

    /// drag moves a slider's thumb while the user holds it, sending nothing until release.
    func drag(
        _ value : Double,
        on model: PluginNodeModel
    ) {
        model.isDragging = true
        model.optimistic = .number(value)
    }

    /// release sends the value the slider was let go at.
    func release(_ model: PluginNodeModel) {
        model.isDragging = false

        if let value = model.optimistic?.number {
            set(.number(value), on: model)
        }
    }

    /// reject reverts the control whose action the kernel refused.
    func reject(_ request: PluginActionRequest) {
        if let model = models[request.node] {
            revert(model)
        }
    }

    private func revert(_ model: PluginNodeModel) {
        generations[model.id, default: 0] += 1

        withAnimation(.snappy) {
            model.optimistic = nil
        }
    }
}
