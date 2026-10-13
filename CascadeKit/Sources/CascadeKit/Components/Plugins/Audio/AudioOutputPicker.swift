//
//  AudioOutputPicker.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// AudioOutputPicker is the output selector: a header with the "Several outputs" switch, then one
/// row per output the system can play to. It owns no state; the mode and the selection live in
/// the mixer model, and the picker only reads them and reports the user's choice.
///
/// In single mode a choice makes that output the system output and closes the picker. In several
/// mode a choice joins or leaves the multi-output and the picker stays open, so the user can
/// build the set in one visit. Closing is the owner's business: the picker only says when.
///
/// Given an `app`, it is that app's selector instead: "Follow system" comes first, the choices
/// are the app's own outputs and the system's output is left alone. The same switch decides
/// between one output and several. If the app stops playing while the picker is open, there is
/// nothing left to choose for, and it draws nothing.
///
/// It fills the mixer's apps area, which is short: rows are 22 pt, and they sit in a vertical
/// scroll view, so more than four outputs scroll instead of growing the page.
struct AudioOutputPicker: View {

    private static let rowHeight: CGFloat = 22

    let model  : AudioMixerModel
    let app    : AudioAppIdentity?
    let onClose: () -> Void

    init(
        model  : AudioMixerModel,
        app    : AudioAppIdentity? = nil,
        onClose: @escaping () -> Void
    ) {
        self.model   = model
        self.app     = app
        self.onClose = onClose
    }

    var body: some View {
        if let system = model.system, let rows = rows(system: system) {
            panel(rows: rows)
        } else {
            Color.clear
        }
    }

    /// rows are the lines to draw, or nil when the picker is an app's and the app is gone.
    private func rows(system: SystemAudioState) -> [AudioOutputPickerRow]? {
        guard let app else {
            return AudioOutputPickerRow.rows(
                for                 : system,
                allowsSeveralOutputs: model.allowsSeveralOutputs
            )
        }
        guard let state = model.apps.first(where: { $0.identity == app }) else { return nil }

        return AudioOutputPickerRow.rows(
            for                 : system,
            app                 : state,
            allowsSeveralOutputs: model.allowsSeveralOutputs
        )
    }

    private func panel(rows: [AudioOutputPickerRow]) -> some View {
        VStack(spacing: 2) {
            header

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Audio output", bundle: .module))
    }

    private var header: some View {
        HStack {
            Text(String(localized: "Several outputs", bundle: .module))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Spacer(minLength: 8)

            Toggle(
                String(localized: "Several outputs", bundle: .module),
                isOn: Bindable(model).allowsSeveralOutputs
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .frame(height: Self.rowHeight)
        .padding(.horizontal, 6)
    }

    private func rowView(_ row: AudioOutputPickerRow) -> some View {
        Button {
            select(row)
        } label: {
            HStack(spacing: 8) {
                AudioOutputIconView(icon: row.icon)
                    .font(.system(size: 12))
                    .frame(width: 18, height: 18)

                Text(row.name)
                    .font(.system(size: 12, weight: row.isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 4)

                marker(row.marker)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: Self.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(row.isSelected ? Color.white.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func marker(_ marker: AudioOutputPickerRow.Marker) -> some View {
        switch marker {
            case .none:
                EmptyView()

            case .checkmark:
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))

            case .checked:
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 13))

            case .unchecked:
                Image(systemName: "square")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func select(_ row: AudioOutputPickerRow) {
        if let app {
            Self.choose(
                row.uid,
                for    : app,
                in     : model,
                onClose: onClose
            )
        } else if let uid = row.uid {
            Self.choose(
                uid,
                in     : model,
                onClose: onClose
            )
        }
    }

    /// choose forwards a tap to the model and closes the picker when the choice was final: a
    /// single-mode choice is, a several-mode one is a step toward a set. The mode is read after
    /// the model acts, but `choose` never changes it, so the order does not matter.
    static func choose(
        _ outputUID: String,
        in model   : AudioMixerModel,
        onClose    : () -> Void
    ) {
        model.choose(outputUID: outputUID)
        if !model.allowsSeveralOutputs {
            onClose()
        }
    }

    /// choose(_:for:in:onClose:) forwards a tap in an app's picker. The same rule closes it: a
    /// single-mode choice is final, a several-mode one is a step toward a set.
    static func choose(
        _ outputUID: String?,
        for app    : AudioAppIdentity,
        in model   : AudioMixerModel,
        onClose    : () -> Void
    ) {
        model.choose(outputUID: outputUID, for: app)
        if !model.allowsSeveralOutputs {
            onClose()
        }
    }
}
