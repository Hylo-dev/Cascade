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
    private let focusedEntryID: UUID?
    private let rename: (@MainActor () -> Void)?
    private let renameDisabled: Bool
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

    @State
    private var renderedEntries: [FileWorkspaceEntry]

    @State
    private var renderedTotalCount: Int

    @State
    private var removingEntryIDs: Set<UUID> = []

    @State
    private var removalTask: Task<Void, Never>?

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
        focusedEntryID: UUID? = nil,
        rename        : (@MainActor () -> Void)? = nil,
        renameDisabled: Bool = false,
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
        self.focusedEntryID = focusedEntryID
        self.rename = rename
        self.renameDisabled = renameDisabled
        self.admissionSequence = admissionSequence
        self.onAdmissionAnimationConsumed = onAdmissionAnimationConsumed
        self.centerObstructionFrame = centerObstructionFrame
        _renderedEntries = State(initialValue: presentation.snapshot.entries)
        _renderedTotalCount = State(initialValue: presentation.snapshot.totalCount)
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
        .onChange(of: presentation.snapshot) { _, _ in
            synchronizeRenderedEntries()
        }
        .onChange(of: reduceMotion) { _, isReduced in
            guard isReduced else { return }
            frontHasMoved = true
            deckHasFanned = true
            cancelAndConsumePendingAdmission()
        }
        .onDisappear {
            cancelAndConsumePendingAdmission()
            removalTask?.cancel()
        }
    }

    private var deck: some View {
        let transforms = FileWorkspaceLayout.cardTransforms(
            count       : renderedEntries.count,
            reduceMotion: reduceMotion
        )
        return GeometryReader { geometry in
            let stackCenterX: CGFloat = 14 + 103
            let arrivalOffset = geometry.size.width / 2 - stackCenterX
            let deckHeight = min(96, max(82, geometry.size.height - obstructionDepth))
            ZStack(alignment: .bottomLeading) {
                VStack(spacing: 0) {
                    deckStack(
                        transforms,
                        arrivalOffset: arrivalOffset,
                        deckHeight: deckHeight - 17
                    )
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apri elenco file")
                    let overflow = FileWorkspaceLayout.overflowCount(
                        totalCount: presentation.snapshot.totalCount
                    )
                    if overflow > 0 {
                        Text("+\(overflow)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Altri \(overflow) file")
                            .opacity(deckHasFanned || reduceMotion ? 1 : 0)
                    }
                }
                .frame(width: 206, alignment: .bottom)
                .padding(.leading, 14)
                workspaceActions(iconOnly: false)
                    .frame(height: deckHeight)
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
                if renderedEntries.indices.contains(transform.index) {
                    let entry = renderedEntries[transform.index]
                    wrappedEntry(
                        entry,
                        action : action,
                        content: AnyView(card(entry, showsName: false))
                    )
                    .modifier(removalModifier(for: entry.id))
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
        ZStack(alignment: .top) {
            HStack {
                actionButton(
                    presentation.action(for: .closeList),
                    label : "Torna al ripiano",
                    symbol: "chevron.left"
                )
                Spacer()
                workspaceActions(iconOnly: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(renderedEntries.enumerated()), id: \.element.id) { index, entry in
                            horizontalEntry(entry)
                                .id(entry.id)
                                .matchedGeometryEffect(id: entry.id, in: fileIdentity)
                                .opacity(reduceMotion || listIsVisible ? 1 : 0)
                                .offset(x: reduceMotion || listIsVisible ? 0 : 12)
                                .animation(
                                    reduceMotion ? nil : .easeOut(duration: 0.18).delay(Double(min(index, 5)) * 0.025),
                                    value: listIsVisible
                                )
                                .modifier(removalModifier(for: entry.id))
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
                .onAppear { scrollToFocusedEntry(using: proxy, animated: false) }
                .onChange(of: focusedEntryID) { _, _ in
                    scrollToFocusedEntry(using: proxy, animated: !reduceMotion)
                }
            }
            .padding(.top, 28)
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(entryHighlight(entry.id))
        )
    }

    private func card(
        _ entry : FileWorkspaceEntry,
        showsName: Bool
    ) -> some View {
        let iconSide: CGFloat = showsName ? 60 : 68
        return VStack(spacing: showsName ? 4 : 0) {
            ZStack(alignment: .bottomTrailing) {
                thumbnail(entry)
                    .frame(width: iconSide, height: iconSide)
                    .id(showsName ? "\(entry.id)-\(admissionSequence)" : entry.id.uuidString)
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
        .frame(width: showsName ? 78 : 72, height: showsName ? 82 : 72)
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
    private func conversionButton(iconOnly: Bool) -> some View {
        if let action = presentation.action(for: .convert) {
            workspaceButton(label: "converti", symbol: "arrow.triangle.2.circlepath", tint: .blue, iconOnly: iconOnly) {
                dispatch(action)
            }
        } else if let explanation = conversionUnavailableExplanation {
            workspaceButton(label: "converti", symbol: "arrow.triangle.2.circlepath", tint: .blue, iconOnly: iconOnly) {}
                .disabled(true)
                .help(explanation)
                .accessibilityHint(explanation)
        }
    }

    private func workspaceActions(iconOnly: Bool) -> some View {
        HStack(spacing: iconOnly ? 5 : 6) {
            workspaceActionButtons(iconOnly: iconOnly)
        }
    }

    @ViewBuilder
    private func workspaceActionButtons(iconOnly: Bool) -> some View {
        conversionButton(iconOnly: iconOnly)
            .matchedGeometryEffect(id: "file-workspace-convert", in: fileIdentity)
        if let rename {
            workspaceButton(label: "rename", symbol: "pencil", tint: .orange, iconOnly: iconOnly, action: rename)
                .disabled(renameDisabled)
                .help("Rinomina il file selezionato")
                .matchedGeometryEffect(id: "file-workspace-rename", in: fileIdentity)
        }
        if let clearAll {
            workspaceButton(label: "svuota", symbol: "trash", tint: .red, iconOnly: iconOnly, action: clearAll)
                .disabled(clearAllDisabled)
                .help("Rimuovi tutti i file dal ripiano")
                .accessibilityHint("I file originali restano al loro posto")
                .matchedGeometryEffect(id: "file-workspace-clear", in: fileIdentity)
        }
    }

    private func workspaceButton(
        label: String,
        symbol: String,
        tint: Color,
        iconOnly: Bool,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: iconOnly ? 14 : 22, weight: .medium))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.55), radius: iconOnly ? 5 : 8)
                    .frame(width: iconOnly ? 24 : 36, height: iconOnly ? 24 : 36)
                    .accessibilityHidden(true)

                if !iconOnly {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .frame(width: iconOnly ? 24 : 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func entryHighlight(_ id: UUID) -> Color {
        if focusedEntryID == id { return Color.accentColor.opacity(0.32) }
        if presentation.selectedEntryIDs.contains(id) { return Color.accentColor.opacity(0.16) }
        return .clear
    }

    private func scrollToFocusedEntry(using proxy: ScrollViewProxy, animated: Bool) {
        guard let focusedEntryID else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(focusedEntryID, anchor: .center)
            }
        } else {
            proxy.scrollTo(focusedEntryID, anchor: .center)
        }
    }

    private func removalModifier(for id: UUID) -> FileRemovalModifier {
        FileRemovalModifier(progress: removingEntryIDs.contains(id) ? 1 : 0, reduceMotion: reduceMotion)
    }

    private func synchronizeRenderedEntries() {
        let currentIDs = Set(presentation.snapshot.entries.map(\.id))
        let removedIDs = Set(renderedEntries.map(\.id)).subtracting(currentIDs)
        let isRemoval = presentation.snapshot.totalCount < renderedTotalCount
        renderedTotalCount = presentation.snapshot.totalCount
        removalTask?.cancel()
        guard isRemoval, !removedIDs.isEmpty else {
            renderedEntries = presentation.snapshot.entries
            removingEntryIDs.removeAll()
            return
        }
        let currentByID = Dictionary(uniqueKeysWithValues: presentation.snapshot.entries.map { ($0.id, $0) })
        renderedEntries = renderedEntries.map { currentByID[$0.id] ?? $0 }
        let additions = presentation.snapshot.entries.filter { entry in
            !renderedEntries.contains(where: { $0.id == entry.id })
        }
        renderedEntries.append(contentsOf: additions)
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) { removingEntryIDs = removedIDs }
        } else {
            withAnimation(.easeOut(duration: 0.24)) { removingEntryIDs = removedIDs }
        }
        removalTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 130 : 260)) } catch { return }
            renderedEntries = presentation.snapshot.entries
            removingEntryIDs.removeAll()
            renderedTotalCount = presentation.snapshot.totalCount
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

private struct FileRemovalModifier: AnimatableModifier {
    nonisolated var progress: CGFloat
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.08)
            .offset(y: reduceMotion ? 0 : -progress * 7)
            .mask {
                if reduceMotion || progress <= 0 {
                    Rectangle()
                } else {
                    FileDissolveMask(progress: progress)
                }
            }
    }
}

/// FileDissolveMask breaks a removed file into 8×8 cells that drop away at
/// staggered thresholds. It is a Shape, one path rebuilt per animation frame:
/// as a Canvas it rendered on the GPU and held ~56 MB of transient graphics
/// memory through every removal, at ~2.5× the CPU.
private struct FileDissolveMask: Shape {
    let progress: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = 8
        let rows = 8
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = rect.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let threshold = CGFloat((column * 17 + row * 11) % 64) / 64
                guard progress < threshold else { continue }
                path.addRect(CGRect(
                    x: rect.minX + CGFloat(column) * cellWidth,
                    y: rect.minY + CGFloat(row) * cellHeight - progress * CGFloat(4 + (column + row) % 7),
                    width: cellWidth + 0.5,
                    height: cellHeight + 0.5
                ))
            }
        }
        return path
    }
}
