//
//  CascadeFileWorkspace.swift
//  Cascade
//

import CascadeContracts
import AppKit
import SwiftUI

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
    private let clearAll: (@MainActor () -> Void)?
    private let clearAllDisabled: Bool
    private let admissionSequence: UInt64
    private let onAdmissionAnimationConsumed: (@MainActor (UInt64) -> Void)?
    private let centerObstructionFrame: CGRect?

    @Environment(\.accessibilityReduceMotion)
    private var systemReduceMotion

    @Namespace
    private var fileIdentity

    @State
    private var listIsVisible = false

    @State
    private var frontHasMoved = false

    @State
    private var deckHasFanned = false

    @State
    private var arrivalTask: Task<Void, Never>?

    @State
    private var consumedAdmissionSequence: UInt64 = 0

    public init(
        _ presentation: FileWorkspacePresentation,
        assets        : any ContentAssetResolving,
        dispatch      : @escaping @MainActor (ActionDescriptor) -> Void,
        reduceMotion  : Bool? = nil,
        thumbnail     : (@MainActor (FileWorkspaceEntry) -> Image?)? = nil,
        wrapEntry     : (@MainActor (FileWorkspaceEntry, ActionDescriptor?, AnyView) -> AnyView)? = nil,
        conversionUnavailableExplanation: String? = nil,
        clearAll      : (@MainActor () -> Void)? = nil,
        clearAllDisabled: Bool = false,
        admissionSequence: UInt64 = 0,
        onAdmissionAnimationConsumed: (@MainActor (UInt64) -> Void)? = nil,
        centerObstructionFrame: CGRect? = nil
    ) throws {
        try presentation.validate()
        self.presentation = presentation
        self.assets       = assets
        self.dispatch     = dispatch
        reduceMotionOverride = reduceMotion
        thumbnailOverride = thumbnail
        self.wrapEntry = wrapEntry
        self.conversionUnavailableExplanation = conversionUnavailableExplanation
        self.clearAll = clearAll
        self.clearAllDisabled = clearAllDisabled
        self.admissionSequence = admissionSequence
        self.onAdmissionAnimationConsumed = onAdmissionAnimationConsumed
        self.centerObstructionFrame = centerObstructionFrame
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
        .onAppear {
            if admissionSequence > 0 {
                animateDeckArrival()
            } else {
                frontHasMoved = true
                deckHasFanned = true
            }
        }
        .onChange(of: admissionSequence) { _, sequence in
            guard sequence > 0 else { return }
            animateDeckArrival()
        }
        .onChange(of: presentation.mode) { _, mode in
            guard mode != .deck else { return }
            cancelAndConsumePendingAdmission()
        }
        .onChange(of: reduceMotion) { _, isReduced in
            guard isReduced else { return }
            frontHasMoved = true
            deckHasFanned = true
            cancelAndConsumePendingAdmission()
        }
        .onDisappear { cancelAndConsumePendingAdmission() }
    }

    private var deck: some View {
        let transforms = FileWorkspaceLayout.cardTransforms(
            count       : presentation.snapshot.entries.count,
            reduceMotion: reduceMotion
        )
        return GeometryReader { geometry in
            let stackCenterX: CGFloat = 14 + 103
            let arrivalOffset = geometry.size.width / 2 - stackCenterX
            let deckHeight = min(96, max(82, geometry.size.height - obstructionDepth))
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    deckStack(
                        transforms,
                        arrivalOffset: arrivalOffset,
                        deckHeight: deckHeight
                    )
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
                            .opacity(deckHasFanned || reduceMotion ? 1 : 0)
                    }
                }
                .padding(.leading, 14)
                deckActions
                    .frame(maxWidth: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .bottomLeading
            )
        }
    }

    @ViewBuilder
    private func deckStack(
        _ transforms: [FileCardTransform],
        arrivalOffset: CGFloat,
        deckHeight: CGFloat
    ) -> some View {
        let action = presentation.action(for: .openList)
        if wrapEntry == nil {
            actionControl(action) {
                deckCards(
                    transforms,
                    action: nil,
                    arrivalOffset: arrivalOffset,
                    deckHeight: deckHeight
                )
            }
        } else {
            deckCards(
                transforms,
                action: action,
                arrivalOffset: arrivalOffset,
                deckHeight: deckHeight
            )
        }
    }

    private func deckCards(
        _ transforms: [FileCardTransform],
        action          : ActionDescriptor?,
        arrivalOffset   : CGFloat,
        deckHeight      : CGFloat
    ) -> some View {
        ZStack {
            ForEach(Array(transforms.reversed()), id: \.index) { transform in
                if presentation.snapshot.entries.indices.contains(transform.index) {
                    let entry = presentation.snapshot.entries[transform.index]
                    wrappedEntry(
                        entry,
                        action : action,
                        content: AnyView(card(entry, showsName: transform.index == 0))
                    )
                    .matchedGeometryEffect(id: entry.id, in: fileIdentity)
                    .rotationEffect(.degrees(cardHasArrived(transform) ? transform.rotationDegrees : 0))
                    .offset(
                        x: cardHasArrived(transform) ? transform.xOffset : arrivalOffset,
                        y: cardHasArrived(transform) ? transform.yOffset : 0
                    )
                    .scaleEffect(cardHasArrived(transform) ? transform.scale : 0.96)
                    .opacity(transform.index == 0 || deckHasFanned || reduceMotion ? 1 : 0)
                }
            }
        }
        .frame(width: 206, height: deckHeight, alignment: .bottom)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            actionButton(
                presentation.action(for: .closeList),
                label : "Torna al ripiano",
                symbol: "chevron.left"
            )
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(presentation.snapshot.entries.enumerated()), id: \.element.id) { index, entry in
                        horizontalEntry(entry)
                            .matchedGeometryEffect(id: entry.id, in: fileIdentity)
                            .opacity(reduceMotion || listIsVisible ? 1 : 0)
                            .offset(x: reduceMotion || listIsVisible ? 0 : 12)
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.18).delay(Double(min(index, 5)) * 0.025),
                                value: listIsVisible
                            )
                    }
                    if presentation.snapshot.nextCursor != nil {
                        actionButton(
                            presentation.action(for: .nextPage),
                            label : "Carica altri file",
                            symbol: "chevron.right"
                        )
                        .frame(width: 42, height: 82)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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

    private func horizontalEntry(_ entry: FileWorkspaceEntry) -> some View {
        wrappedEntry(
            entry,
            action : presentation.action(for: .select, entryID: entry.id),
            content: AnyView(card(entry, showsName: true))
        )
        .buttonStyle(.plain)
        .help(entry.name)
        .opacity(entry.availability == .available ? 1 : 0.55)
        .contextMenu { entryContextActions(entry) }
    }

    private func card(
        _ entry : FileWorkspaceEntry,
        showsName: Bool
    ) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                thumbnail(entry)
                    .frame(width: 54, height: 54)
                    .id(showsName ? "\(entry.id)-\(admissionSequence)" : entry.id.uuidString)
                    .contentTransition(symbolReplacement)
                if presentation.selectedEntryIDs.contains(entry.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .accessibilityLabel("Selezionato")
                }
            }
            if showsName {
                Text(entry.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 76, alignment: .center)
                    .help(entry.name)
                if entry.availability != .available {
                    Text(availabilityLabel(entry.availability))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 78, height: 82)
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

    private var deckActions: some View {
        VStack(spacing: 6) {
            conversionButton
            if let clearAll {
                Button("Svuota", systemImage: "trash") { clearAll() }
                    .labelStyle(.titleAndIcon)
                    .disabled(clearAllDisabled)
                    .help("Rimuovi tutti i file dal ripiano")
                    .accessibilityHint("I file originali restano al loro posto")
            }
        }
    }

    @ViewBuilder
    private func entryContextActions(_ entry: FileWorkspaceEntry) -> some View {
        if let preview = presentation.action(for: .preview, entryID: entry.id) {
            Button("Anteprima") { dispatch(preview) }
        }
        if let reveal = presentation.action(for: .reveal, entryID: entry.id) {
            Button("Mostra nel Finder") { dispatch(reveal) }
        }
        if let relink = presentation.action(for: .relink, entryID: entry.id) {
            Button("Ricollega") { dispatch(relink) }
        }
        if let remove = presentation.action(for: .remove, entryID: entry.id) {
            Divider()
            Button("Rimuovi") { dispatch(remove) }
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

    private var selectedFormatLabel: String {
        presentation.formats.first(where: { $0.id == presentation.selectedFormatID })?.label
            ?? "Choose format"
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var obstructionDepth: CGFloat {
        max(0, centerObstructionFrame?.maxY ?? 0)
    }

    private var symbolReplacement: ContentTransition {
        guard !reduceMotion else { return .identity }
        if #available(macOS 15.0, *) {
            return .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating)
        }
        return .symbolEffect(.replace.downUp.byLayer, options: .nonRepeating)
    }

    private func animateDeckArrival() {
        arrivalTask?.cancel()
        guard !reduceMotion, presentation.mode == .deck, !presentation.snapshot.entries.isEmpty else {
            frontHasMoved = true
            deckHasFanned = true
            consumeAdmission(admissionSequence)
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            frontHasMoved = false
            deckHasFanned = false
        }
        let sequence = admissionSequence
        arrivalTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard !reduceMotion, presentation.mode == .deck else {
                frontHasMoved = true
                deckHasFanned = true
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                frontHasMoved = true
            }
            do { try await Task.sleep(for: .milliseconds(110)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                deckHasFanned = true
            }
            do { try await Task.sleep(for: .milliseconds(210)) } catch { return }
            guard !Task.isCancelled else { return }
            consumeAdmission(sequence)
        }
    }

    private func cardHasArrived(_ transform: FileCardTransform) -> Bool {
        reduceMotion || (transform.index == 0 ? frontHasMoved : deckHasFanned)
    }

    private func cancelAndConsumePendingAdmission() {
        arrivalTask?.cancel()
        arrivalTask = nil
        frontHasMoved = true
        deckHasFanned = true
        consumeAdmission(admissionSequence)
    }

    private func consumeAdmission(_ sequence: UInt64) {
        guard sequence > 0, consumedAdmissionSequence != sequence else { return }
        consumedAdmissionSequence = sequence
        onAdmissionAnimationConsumed?(sequence)
    }
}
