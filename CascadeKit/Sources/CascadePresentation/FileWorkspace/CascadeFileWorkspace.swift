//
//  CascadeFileWorkspace.swift
//  Cascade
//

import CascadeContracts
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// CascadeFileWorkspace renders one validated file shelf presentation with native controls.
@MainActor
public struct CascadeFileWorkspace: View {
    private let presentation: FileWorkspacePresentation
    private let assets      : any ContentAssetResolving
    private let dispatch    : @MainActor (ActionDescriptor) -> Void
    private let reduceMotionOverride: Bool?
    private let thumbnailOverride: (@MainActor (FileWorkspaceEntry) -> Image?)?
    private let wrapEntry: (@MainActor (FileWorkspaceEntry, ActionDescriptor?, AnyView) -> AnyView)?
    private let conversionUnavailableExplanation: String?

    @Environment(\.accessibilityReduceMotion)
    private var systemReduceMotion

    @Namespace
    private var fileIdentity

    @State
    private var listIsVisible = false

    @State
    private var deckHasArrived = false

    public init(
        _ presentation: FileWorkspacePresentation,
        assets        : any ContentAssetResolving,
        dispatch      : @escaping @MainActor (ActionDescriptor) -> Void,
        reduceMotion  : Bool? = nil,
        thumbnail     : (@MainActor (FileWorkspaceEntry) -> Image?)? = nil,
        wrapEntry     : (@MainActor (FileWorkspaceEntry, ActionDescriptor?, AnyView) -> AnyView)? = nil,
        conversionUnavailableExplanation: String? = nil
    ) throws {
        try presentation.validate()
        self.presentation = presentation
        self.assets       = assets
        self.dispatch     = dispatch
        reduceMotionOverride = reduceMotion
        thumbnailOverride = thumbnail
        self.wrapEntry = wrapEntry
        self.conversionUnavailableExplanation = conversionUnavailableExplanation
    }

    public var body: some View {
        Group {
            switch presentation.mode {
            case .deck: deck
            case .list: list
            case .conversion: conversion
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78), value: presentation.mode)
        .onAppear { animateDeckArrival() }
        .onChange(of: deckEntryIDs) { _, _ in animateDeckArrival() }
    }

    private var deck: some View {
        let transforms = FileWorkspaceLayout.cardTransforms(
            count       : presentation.snapshot.entries.count,
            reduceMotion: reduceMotion
        )
        return HStack(spacing: 16) {
            deckStack(transforms)
            .buttonStyle(.plain)
            .accessibilityLabel("Apri elenco file")

            let overflow = FileWorkspaceLayout.overflowCount(
                totalCount: presentation.snapshot.totalCount
            )
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Altri \(overflow) file")
            }
            conversionButton
        }
        .padding(14)
    }

    @ViewBuilder
    private func deckStack(_ transforms: [FileCardTransform]) -> some View {
        let action = presentation.action(for: .openList)
        if wrapEntry == nil {
            actionControl(action) { deckCards(transforms, action: nil) }
        } else {
            deckCards(transforms, action: action)
        }
    }

    private func deckCards(
        _ transforms: [FileCardTransform],
        action          : ActionDescriptor?
    ) -> some View {
        ZStack(alignment: .trailing) {
            ForEach(Array(transforms.reversed()), id: \.index) { transform in
                if presentation.snapshot.entries.indices.contains(transform.index) {
                    let entry = presentation.snapshot.entries[transform.index]
                    wrappedEntry(
                        entry,
                        action : action,
                        content: AnyView(card(entry, showsName: transform.index == 0))
                    )
                    .matchedGeometryEffect(id: entry.id, in: fileIdentity)
                    .rotationEffect(.degrees(
                        deckHasArrived || reduceMotion ? transform.rotationDegrees : 0
                    ))
                    .offset(
                        x: deckHasArrived || reduceMotion ? transform.xOffset : 54,
                        y: deckHasArrived || reduceMotion ? transform.yOffset : 0
                    )
                    .scaleEffect(deckHasArrived || reduceMotion ? transform.scale : 0.96)
                }
            }
        }
        .frame(width: 190, height: 118)
    }

    private var list: some View {
        VStack(spacing: 8) {
            HStack {
                Text("File")
                    .font(.headline)
                Spacer()
                conversionButton
                actionButton(
                    presentation.action(for: .closeList),
                    label : "Chiudi elenco",
                    symbol: "rectangle.stack"
                )
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(presentation.snapshot.entries.enumerated()), id: \.element.id) { index, entry in
                        row(entry)
                            .matchedGeometryEffect(id: entry.id, in: fileIdentity)
                            .opacity(reduceMotion || listIsVisible ? 1 : 0)
                            .offset(x: reduceMotion || listIsVisible ? 0 : -12)
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.18).delay(Double(index) * 0.025),
                                value: listIsVisible
                            )
                    }
                }
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity)
            }
            if presentation.snapshot.nextCursor != nil {
                actionButton(
                    presentation.action(for: .nextPage),
                    label : "Pagina successiva",
                    symbol: "chevron.down"
                )
            }
        }
        .padding(12)
        .onAppear { listIsVisible = true }
        .onDisappear { listIsVisible = false }
    }

    private var conversion: some View {
        GeometryReader { geometry in
            let frames = FileWorkspaceLayout.conversionFrames(
                in: CGRect(origin: .zero, size: geometry.size)
            )
            inputGroup
                .frame(width: frames.inputs.width, height: frames.inputs.height)
                .clipped()
                .position(x: frames.inputs.midX, y: frames.inputs.midY)
            Image(systemName: "arrow.right")
                .font(.title2.weight(.semibold))
                .scaleEffect(isConversionWorking && !reduceMotion ? 1.08 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.2),
                    value: isConversionWorking
                )
                .frame(width: frames.arrow.width, height: frames.arrow.height)
                .position(x: frames.arrow.midX, y: frames.arrow.midY)
                .accessibilityHidden(true)
            formatSelector
                .frame(width: frames.selector.width, height: frames.selector.height)
                .position(x: frames.selector.midX, y: frames.selector.midY)
            conversionControls
                .frame(width: frames.controls.width, height: frames.controls.height)
                .position(x: frames.controls.midX, y: frames.controls.midY)
            resultGroup
                .frame(width: frames.results.width, height: frames.results.height)
                .clipped()
                .position(x: frames.results.midX, y: frames.results.midY)
        }
        .padding(.vertical, 2)
    }

    private var inputGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            Spacer(minLength: 0)
            Text("Inputs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(inputEntries.prefix(3), id: \.id) { entry in
                compactCard(entry)
                    .matchedGeometryEffect(id: entry.id, in: fileIdentity)
            }
            if inputEntries.count > 3 {
                Text("+\(inputEntries.count - 3) more inputs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private var resultGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            Spacer(minLength: 0)
            Text(resultCount > 0 || presentation.selectedFormatID == nil ? "Results" : "Preview results")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(resultEntries.prefix(2), id: \.id) { entry in
                compactCard(entry)
            }
            if resultEntries.count > 2 {
                Text("+\(resultEntries.count - 2) more results")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if resultEntries.isEmpty {
                if resultCount > 0 {
                    Text("\(resultCount) results available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let selectedFormat = presentation.formats.first(where: {
                    $0.id == presentation.selectedFormatID
                }) {
                    Label(selectedFormat.label, systemImage: "doc.badge.arrow.up")
                        .lineLimit(2)
                        .help(selectedFormat.label)
                        .accessibilityLabel("Preview result format: \(selectedFormat.label)")
                } else {
                    Text("Choose a format")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            forEachVisibleJob
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    @ViewBuilder
    private var formatSelector: some View {
        if presentation.formats.isEmpty {
            Text("No formats")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Menu {
                ForEach(presentation.formats, id: \.id) { format in
                    if let action = presentation.action(for: .selectFormat, formatID: format.id) {
                        Button(format.label) { dispatch(action) }
                    }
                }
            } label: {
                Text(selectedFormatLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .help(selectedFormatLabel)
        }
    }

    @ViewBuilder
    private var conversionControls: some View {
        if let runningJob = presentation.snapshot.jobs.first(where: {
            $0.state == .queued || $0.state == .running
        }) {
            if let cancel = presentation.action(for: .cancel, jobID: runningJob.id) {
                Button("Cancel") { dispatch(cancel) }
            }
        } else if presentation.selectedFormatID != nil,
                  let start = presentation.action(for: .start) {
            Button("Start") { dispatch(start) }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var forEachVisibleJob: some View {
        if let job = presentation.snapshot.jobs.first(where: {
            $0.state == .queued || $0.state == .running
        }) {
            if let progress = job.progress {
                ProgressView(value: progress)
                    .accessibilityLabel("Conversion progress")
                    .accessibilityValue(progress.formatted(.percent))
            } else if job.state == .queued || job.state == .running {
                ProgressView()
                    .accessibilityLabel("Conversion in progress")
            }
        }
    }

    private func row(_ entry: FileWorkspaceEntry) -> some View {
        HStack(spacing: 9) {
            wrappedEntry(
                entry,
                action : presentation.action(for: .select, entryID: entry.id),
                content: AnyView(
                    HStack(spacing: 9) {
                        thumbnail(entry)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .lineLimit(1)
                            Text(friendlyType(entry.typeIdentifier))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if entry.availability != .available {
                                Text(availabilityLabel(entry.availability))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 4)
                        if presentation.selectedEntryIDs.contains(entry.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Selezionato")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
            )
            .buttonStyle(.plain)
            .help(entry.name)
            if let remove = presentation.action(for: .remove, entryID: entry.id) {
                Button("Rimuovi", systemImage: "xmark") { dispatch(remove) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            entryMenu(entry)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            presentation.selectedEntryIDs.contains(entry.id)
                ? Color.accentColor.opacity(0.18)
                : Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .opacity(entry.availability == .available ? 1 : 0.55)
    }

    private func card(
        _ entry : FileWorkspaceEntry,
        showsName: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            thumbnail(entry)
                .frame(height: 68)
            if showsName {
                Text(entry.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .help(entry.name)
                if entry.availability != .available {
                    Text(availabilityLabel(entry.availability))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(9)
        .frame(width: 118, height: 106)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func compactCard(_ entry: FileWorkspaceEntry) -> some View {
        HStack(spacing: 6) {
            thumbnail(entry)
                .frame(width: 24, height: 24)
            Text(entry.name)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.name)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func thumbnail(_ entry: FileWorkspaceEntry) -> some View {
        if let image = thumbnailOverride?(entry) {
            image
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else if let assetID = entry.thumbnailAssetID,
           let image = assets.image(for: assetID) {
            image
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "doc.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(5)
                .accessibilityHidden(true)
        }
    }

    private func wrappedEntry(
        _ entry : FileWorkspaceEntry,
        action  : ActionDescriptor?,
        content : AnyView
    ) -> AnyView {
        if let wrapEntry { return wrapEntry(entry, action, content) }
        guard let action else { return content }
        return AnyView(Button(action: { dispatch(action) }) { content })
    }

    @ViewBuilder
    private func actionControl<Label: View>(
        _ action: ActionDescriptor?,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if let action {
            Button(action: { dispatch(action) }, label: label)
        } else {
            label()
        }
    }

    @ViewBuilder
    private func actionButton(
        _ action: ActionDescriptor?,
        label   : String,
        symbol  : String,
        iconOnly: Bool = true
    ) -> some View {
        if let action {
            if iconOnly {
                Button(label, systemImage: symbol) { dispatch(action) }
                    .labelStyle(.iconOnly)
                    .help(label)
            } else {
                Button(label, systemImage: symbol) { dispatch(action) }
                    .labelStyle(.titleAndIcon)
                    .help(label)
            }
        }
    }

    @ViewBuilder
    private var conversionButton: some View {
        if let action = presentation.action(for: .convert) {
            actionButton(
                action,
                label   : "Converti",
                symbol  : "arrow.triangle.2.circlepath",
                iconOnly: false
            )
        } else if let explanation = conversionUnavailableExplanation {
            Button("Converti", systemImage: "arrow.triangle.2.circlepath") {}
                .labelStyle(.titleAndIcon)
                .disabled(true)
                .help(explanation)
                .accessibilityHint(explanation)
        }
    }

    @ViewBuilder
    private func entryMenu(_ entry: FileWorkspaceEntry) -> some View {
        let relink = presentation.action(for: .relink, entryID: entry.id)
        let preview = presentation.action(for: .preview, entryID: entry.id)
        let reveal = presentation.action(for: .reveal, entryID: entry.id)
        if relink != nil || preview != nil || reveal != nil {
            Menu("Altre azioni", systemImage: "ellipsis") {
                if let relink { Button("Ricollega") { dispatch(relink) } }
                if let preview { Button("Anteprima") { dispatch(preview) } }
                if let reveal { Button("Mostra nel Finder") { dispatch(reveal) } }
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
        }
    }

    private var inputEntries: [FileWorkspaceEntry] {
        let selected = Set(presentation.selectedEntryIDs)
        let results = Set(presentation.snapshot.jobs.flatMap(\.resultIDs))
        return presentation.snapshot.entries.filter {
            selected.contains($0.id) && !results.contains($0.id)
        }
    }

    private var resultEntries: [FileWorkspaceEntry] {
        let results = Set(presentation.snapshot.jobs.flatMap(\.resultIDs))
        return presentation.snapshot.entries.filter { results.contains($0.id) }
    }

    private var resultCount: Int {
        Set(presentation.snapshot.jobs.flatMap(\.resultIDs)).count
    }

    private var isConversionWorking: Bool {
        presentation.snapshot.jobs.contains { $0.state == .queued || $0.state == .running }
    }

    private func availabilityLabel(_ availability: FileAvailability) -> String {
        switch availability {
        case .available: "Disponibile"
        case .unavailable: "Non disponibile"
        case .receiving: "In ricezione"
        }
    }

    private func friendlyType(_ identifier: String) -> String {
        UTType(identifier)?.localizedDescription ?? identifier
    }

    private var selectedFormatLabel: String {
        presentation.formats.first(where: { $0.id == presentation.selectedFormatID })?.label
            ?? "Choose format"
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var deckEntryIDs: [UUID] {
        Array(presentation.snapshot.entries.prefix(FileWorkspaceLayout.maximumVisibleCards).map(\.id))
    }

    private func animateDeckArrival() {
        guard !reduceMotion, presentation.mode == .deck, !deckEntryIDs.isEmpty else {
            deckHasArrived = true
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { deckHasArrived = false }
        Task { @MainActor in
            await Task.yield()
            guard !reduceMotion, presentation.mode == .deck else {
                deckHasArrived = true
                return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                deckHasArrived = true
            }
        }
    }
}
