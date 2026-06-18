//
//  WidgetHost.swift
//  CascadeKit
//

import SwiftUI

/// WidgetHost owns the registered widgets and decides which are live.
///
/// It is the bridge between the discrete `NotchState` and the widgets: when a
/// region becomes visible the host `activate`s its widgets (handing each a
/// context) and when it hides the host `suspend`s them, so a closed notch holds
/// no widget resources. It also builds the SwiftUI view the renderer shows
/// inside the open notch.
@MainActor
final class WidgetHost {

    /// Fired when a widget asks for a content refresh; the controller re-renders.
    var onContentChanged: (() -> Void)?

    private var widgets   : [NotchWidget] = []
    private var contexts  : [WidgetIdentifier: WidgetContext] = [:]
    private var liveState : NotchState = .closed

    func register(_ widget: NotchWidget) {
        widgets.append(widget)
    }

    /// React to a state transition: activate widgets whose region just became
    /// visible, suspend those whose region just hid, and refresh the rest.
    ///
    /// Visibility is uniform: a region is visible when the state contains its
    /// `requiredState` (`.expanded` needs both side bits, a side needs its own).
    func update(state: NotchState) {

        for widget in widgets {

            let required   = widget.preferredRegion.requiredState
            let isVisible  = state.contains(required)
            let wasVisible = liveState.contains(required)
            let id         = type(of: widget).identifier

            if isVisible, !wasVisible {
                let context = WidgetContext(state: state) { [weak self] in
                    self?.onContentChanged?()
                }
                contexts[id] = context
                widget.activate(in: context)

            } else if !isVisible, wasVisible {
                widget.suspend()
                contexts[id] = nil

            } else if isVisible {
                contexts[id]?.update(state: state)
            }
        }

        liveState = state
    }

    /// Build the content shown inside the open notch: leading widgets on the
    /// left, expanded in the middle, trailing on the right. Only currently
    /// visible regions contribute.
    func makeContentView() -> AnyView {

        let leading  = visibleWidgets(in: .leading)
        let expanded = visibleWidgets(in: .expanded)
        let trailing = visibleWidgets(in: .trailing)

        return AnyView(
            HStack(spacing: 12) {

                ForEach(leading.indices, id: \.self) { index in
                    leading[index].makeContentView()
                }

                if !expanded.isEmpty {
                    Spacer(minLength: 0)

                    ForEach(expanded.indices, id: \.self) { index in
                        expanded[index].makeContentView()
                    }

                    Spacer(minLength: 0)
                }

                ForEach(trailing.indices, id: \.self) { index in
                    trailing[index].makeContentView()
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    private func visibleWidgets(in region: NotchRegion) -> [NotchWidget] {

        guard liveState.contains(region.requiredState) else {
            return []
        }

        return widgets.filter { $0.preferredRegion == region }
    }
}
