//
//  PluginNodeStore.swift
//  CascadeKit
//

import AppKit
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

    private(set) var revision     : UInt64 = 0
    private(set) var root         : PluginNodeModel?
    private(set) var glassLights  : [GlassLight] = []
    private(set) var optionsRoot  : PluginNodeModel?
    private(set) var optionsButtons: [PluginNodeModel] = []

    @ObservationIgnored private var models     : [PluginNodeID: PluginNodeModel] = [:]
    @ObservationIgnored private var generations: [PluginNodeID: UInt64] = [:]
    @ObservationIgnored private var optionsNodes: Set<PluginNodeID> = []

    private let submit       : (PluginActionRequest) -> Void
    private let submitOptions: ((PluginActionRequest, PluginOptionsOrigin) -> Void)?
    private let schedule     : (Duration, @escaping @MainActor () -> Void) -> Void

    init(
        key          : PluginPublicationKey,
        submit       : @escaping (PluginActionRequest) -> Void,
        submitOptions: ((PluginActionRequest, PluginOptionsOrigin) -> Void)? = nil,
        schedule     : @escaping (Duration, @escaping @MainActor () -> Void) -> Void = { delay, task in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / .seconds(1)) {
                MainActor.assumeIsolated(task)
            }
        }
    ) {
        self.key           = key
        self.submit        = submit
        self.submitOptions = submitOptions
        self.schedule      = schedule
    }

    func model(_ id: PluginNodeID) -> PluginNodeModel? {
        models[id]
    }

    /// sliderReading is the value of the slider whose explicit id is `sliderID`, as the user sees
    /// it now: the optimistic one, a drag's included, or else the published one. It reads the
    /// slider's model, so a view that calls it is redrawn when that value changes and at no other
    /// time. Nil when the document has no such slider, which validation prevents.
    func sliderReading(_ sliderID: String) -> PluginSliderReading? {
        guard let slider = models[.explicit(sliderID, kindName: "slider")],
              case .slider(let published, let minimum, let maximum, let step, let style, _) = slider.kind
        else { return nil }

        let shown = slider.optimistic?.number ?? published

        switch style {
            case .standard:
                return PluginSliderReading(value: shown, labels: nil)

            case .ruler(_, let labels):
                return PluginSliderReading(
                    value : step.map { RulerGeometry.snapped(shown, minimum: minimum, maximum: maximum, step: $0) } ?? shown,
                    labels: labels
                )
        }
    }

    func isOptionsNode(_ id: PluginNodeID) -> Bool { optionsNodes.contains(id) }

    /// apply takes one change from the kernel. Removed nodes lose their models, inserted nodes
    /// get new ones, updated nodes have theirs refreshed, and every control but a dragged slider
    /// drops its optimistic value, because the publication is the source of truth.
    func apply(_ change: PluginPublicationChange) {
        revision = change.revision

        guard let content = change.content else {
            models.removeAll()
            generations.removeAll()
            root          = nil
            glassLights   = []
            optionsRoot   = nil
            optionsButtons = []
            optionsNodes  = []
            return
        }

        let table = content.table
        for id in content.diff.removed {
            models.removeValue(forKey: id)
            generations.removeValue(forKey: id)
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
        // The table lays the options subtree out after the widget's, so it runs from the
        // options root to the end. A document without options pays for none of this.
        if let options = table.optionsRoot, let start = table.index(of: options.id) {
            optionsRoot  = models[options.id]
            optionsNodes = Set(table.entries[start...].map(\.id))
        } else if optionsRoot != nil || !optionsNodes.isEmpty {
            optionsRoot  = nil
            optionsNodes = []
        }
        // Every button that carries the options action opens the page: a widget with a face
        // for each size may draw an opener in more than one of them.
        let openers = content.document.optionsAction.map { action in
            table.entries.filter { $0.kind == .button(action: action) }.compactMap { models[$0.id] }
        } ?? []
        if optionsButtons.map(\.id) != openers.map(\.id) {
            optionsButtons = openers
        }
        if glassLights != content.document.glassLights {
            glassLights = content.document.glassLights
        }
    }

    /// isOptionsButton says whether a node is one of the buttons that open the options page.
    func isOptionsButton(_ id: PluginNodeID) -> Bool {
        optionsButtons.contains { $0.id == id }
    }

    /// press sends a button's action. A button holds no state: SwiftUI shows the press, and
    /// whatever the action changes arrives as the next publication.
    func press(
        _ model      : PluginNodeModel,
        optionsOrigin: PluginOptionsOrigin? = nil
    ) {
        guard canInteract(with: model, optionsOrigin: optionsOrigin) else { return }
        let request = PluginActionRequest(key: key, node: model.id, revision: revision)
        send(request, optionsOrigin: optionsOrigin)
    }

    /// set shows a control's new value at once, sends the action, and arms the revert. The
    /// value appears with `animation`, `.snappy` unless the caller passes nil, as a control does
    /// under Reduce Motion.
    func set(
        _ value      : PluginValue,
        on model     : PluginNodeModel,
        optionsOrigin: PluginOptionsOrigin? = nil,
        animation    : Animation? = .snappy
    ) {
        guard canInteract(with: model, optionsOrigin: optionsOrigin) else { return }
        generations[model.id, default: 0] += 1
        let generation = generations[model.id]

        withAnimation(animation) {
            model.optimistic = value
        }
        let request = PluginActionRequest(
            key     : key,
            node    : model.id,
            revision: revision,
            value   : value
        )
        send(request, optionsOrigin: optionsOrigin)

        schedule(Self.confirmationTimeout) { [weak self, weak model] in
            guard let self, let model,
                  models[model.id] === model, generations[model.id] == generation
            else { return }

            revert(model)
        }
    }

    /// drag moves a slider's thumb while the user holds it, sending nothing until release. A new
    /// drag also outdates the revert an earlier release armed, so its timeout cannot pull the
    /// thumb from under the user's hand.
    func drag(
        _ value      : Double,
        on model     : PluginNodeModel,
        optionsOrigin: PluginOptionsOrigin? = nil
    ) {
        guard canInteract(with: model, optionsOrigin: optionsOrigin) else { return }
        generations[model.id, default: 0] += 1
        model.isDragging = true
        model.optimistic = .number(value)
    }

    /// release sends the value the slider was let go at, shown with `animation` (see `set`).
    func release(
        _ model      : PluginNodeModel,
        optionsOrigin: PluginOptionsOrigin? = nil,
        animation    : Animation? = .snappy
    ) {
        guard canInteract(with: model, optionsOrigin: optionsOrigin) else { return }
        model.isDragging = false

        if let value = model.optimistic?.number {
            set(
                .number(value),
                on           : model,
                optionsOrigin: optionsOrigin,
                animation    : animation
            )
        }
    }

    /// cancelDrag ends a drag that will never be released, because its control left the screen
    /// under the user's finger: nothing is sent, the thumb goes back to the published value
    /// and the control takes publications again. A control that is not being dragged is left alone.
    func cancelDrag(_ model: PluginNodeModel) {
        guard models[model.id] === model, model.isDragging else { return }
        generations[model.id, default: 0] += 1
        model.isDragging = false
        model.optimistic = nil
    }

    /// reject reverts the control whose action the kernel refused, unless the user is dragging
    /// it again: the refusal was for the value let go before, and the new one is still to come.
    func reject(_ request: PluginActionRequest) {
        if let model = models[request.node], !model.isDragging {
            revert(model)
        }
    }

    /// canInteract rejects revoked page callbacks before they change optimistic state.
    /// Options controls require their captured origin; compact controls need only their model.
    private func canInteract(
        with model   : PluginNodeModel,
        optionsOrigin: PluginOptionsOrigin?
    ) -> Bool {
        guard models[model.id] === model else { return false }
        return !isOptionsNode(model.id) || (optionsOrigin?.isValid == true && submitOptions != nil)
    }

    private func send(
        _ request    : PluginActionRequest,
        optionsOrigin: PluginOptionsOrigin?
    ) {
        if isOptionsNode(request.node) {
            guard let optionsOrigin else { return }
            submitOptions?(request, optionsOrigin)
        } else {
            submit(request)
        }
    }

    /// revert puts the control back on the published value. It glides there unless the user asked
    /// for Reduce Motion, which the system reports on the main thread, where the store lives.
    private func revert(_ model: PluginNodeModel) {
        generations[model.id, default: 0] += 1

        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy) {
            model.optimistic = nil
        }
    }
}
