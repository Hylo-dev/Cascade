//
//  FileShelfDesignPreview.swift
//  Cascade
//

#if DEBUG
import AppKit
import CascadeContracts
import CascadePresentation
import SwiftUI
import UniformTypeIdentifiers

/// In-memory Xcode canvas for adjusting the real shelf renderer at notch size.
@MainActor
private struct FileShelfDesignPreview: View {

    @State
    private var fileCount = 4

    @State
    private var mode: FileWorkspaceMode = .deck

    @State
    private var selectedIDs: [UUID] = []

    @State
    private var focusedID: UUID?

    @State
    private var selectionAnchorID: UUID?

    @State
    private var renameHint = false

    @State
    private var removedIDs: Set<UUID> = []

    @State
    private var renamedNames: [UUID: String] = [:]

    @State
    private var admissionSequence: UInt64 = 0

    @State
    private var reduceMotion = false

    @State
    private var scrollCloseDirection = FileShelfScrollDirection.conventionalBack

    private static let samples: [FileWorkspaceEntry] = [
        ("Relazione.pdf",  "com.adobe.pdf"),
        ("Fotografia.png", "public.png"),
        ("Demo.mp3",       "public.mp3"),
        ("Archivio.zip",   "public.zip"),
        ("Filmato.mov",    "public.movie"),
        ("Appunti.txt",    "public.plain-text"),
        ("Documento.doc",  "com.microsoft.word.doc"),
        ("Paesaggio.jpg",  "public.jpeg"),
    ].enumerated().map { index, sample in
        try! FileWorkspaceEntry(
            id              : UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            name            : sample.0,
            typeIdentifier  : sample.1,
            availability    : .available,
            ownership       : .externalReference,
            thumbnailAssetID: nil
        )
    }

    private var entries: [FileWorkspaceEntry] {
        Self.samples.prefix(fileCount).filter { !removedIDs.contains($0.id) }.map { entry in
            guard let name = renamedNames[entry.id] else { return entry }

            return try! FileWorkspaceEntry(
                id              : entry.id,
                name            : name,
                typeIdentifier  : entry.typeIdentifier,
                availability    : entry.availability,
                ownership       : entry.ownership,
                thumbnailAssetID: nil
            )
        }
    }

    private var presentation: FileWorkspacePresentation {
        let entries = entries
        var actions: [FileWorkspaceActionBinding] = []
        if !entries.isEmpty {
            actions.append(
                try! FileWorkspaceActionBinding(
                    role      : .openList,
                    descriptor: ActionDescriptor(id: "preview.open", label: "Apri elenco file")
                )
            )
        }

        actions.append(
            try! FileWorkspaceActionBinding(
                role      : .closeList,
                descriptor: ActionDescriptor(id: "preview.back", label: "Torna al ripiano")
            )
        )

        for entry in entries {
            actions.append(
                try! FileWorkspaceActionBinding(
                    role      : .select,
                    entryID   : entry.id,
                    descriptor: ActionDescriptor(
                        id   : "preview.select.\(entry.id.uuidString)",
                        label: "Seleziona \(entry.name)"
                    )
                )
            )
            actions.append(
                try! FileWorkspaceActionBinding(
                    role      : .remove,
                    entryID   : entry.id,
                    descriptor: ActionDescriptor(
                        id   : "preview.remove.\(entry.id.uuidString)",
                        label: "Rimuovi \(entry.name)"
                    )
                )
            )
        }

        return try! FileWorkspacePresentation(
            snapshot        : FileWorkspaceSnapshot(
                revision  : 1,
                entries   : entries,
                totalCount: entries.count,
                nextCursor: nil,
                jobs      : []
            ),
            mode            : mode,
            selectedEntryIDs: selectedIDs.filter { id in entries.contains(where: { $0.id == id }) },
            formats         : [],
            selectedFormatID: nil,
            actions         : actions
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            Text("Anteprima ripiano · dati di esempio")
                .font(.headline)

            HStack(spacing: 16) {

                Picker("File", selection: $fileCount) {

                    Text("0")
                        .tag(0)

                    Text("1")
                        .tag(1)

                    Text("4")
                        .tag(4)

                    Text("8")
                        .tag(8)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: fileCount) { _, _ in
                    removedIDs        = []
                    renamedNames      = [:]
                    selectedIDs       = []
                    focusedID         = nil
                    selectionAnchorID = nil
                    renameHint        = false
                    mode              = .deck
                }

                Button("Rigioca ingresso") {
                    mode = .deck
                    admissionSequence &+= 1
                }

                Toggle("Riduci movimento", isOn: $reduceMotion)
            }
            .controlSize(.small)

            ZStack(alignment: .top) {

                RoundedRectangle(cornerRadius: 24)
                    .fill(.black.opacity(0.88))

                if let workspace = makeWorkspace() {
                    workspace
                        .frame(width: 400, height: 124)
                        .foregroundStyle(.white)
                        .environment(\.colorScheme, .dark)
                        .padding(.top, 4)
                }

                RoundedRectangle(cornerRadius: 9)
                    .fill(.black)
                    .frame(width: 184, height: 28)
            }
            .frame(width: 440, height: 144)
            .accessibilityLabel("Anteprima del ripiano nella tacca")

            Text(
                renameHint
                    ? "Seleziona un file da rinominare"
                    : "Clic sulle icone per aprire l’elenco. Prova il gesto di ritorno e la freccia nel ripiano."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 620)
    }

    private func makeWorkspace() -> CascadeFileWorkspace? {
        try? CascadeFileWorkspace(
            presentation,
            assets                          : PreviewAssets(),
            dispatch                        : perform,
            reduceMotion                    : reduceMotion,
            thumbnail                       : { entry in
                guard let type = UTType(entry.typeIdentifier) else { return nil }
                return Image(nsImage: NSWorkspace.shared.icon(for: type))
            },
            wrapEntry                       : { entry, action, content in
                AnyView(
                    FileShelfDragSource(
                        content          : content,
                        files            : [],
                        accessibilityName: entry.name,
                        expandsOnScroll  : mode == .deck,
                        scrollNavigation : mode == .deck
                            ? .open : .close(expectedDirection: scrollCloseDirection),
                        activate         : { if let action { perform(action) } },
                        interaction      : { event in handle(event, for: entry.id) },
                        navigateByScroll : navigateByScroll,
                        copy             : { _, _ in throw FileWorkspaceError.unsupported }
                    )
                )
            },
            conversionUnavailableExplanation: "Conversione non ancora disponibile",
            clearAll                        : {
                fileCount         = 0
                mode              = .deck
                selectedIDs       = []
                focusedID         = nil
                selectionAnchorID = nil
                renameHint        = false
            },
            focusedEntryID                  : focusedID,
            rename                          : requestRename,
            renameDisabled                  : mode == .list && selectedIDs.count > 1,
            admissionSequence               : admissionSequence,
            centerObstructionFrame          : CGRect(
                x     : 108,
                y     : 0,
                width : 184,
                height: 28
            )
        )
    }

    private func perform(_ action: ActionDescriptor) {
        switch action.id {
            case "preview.open":
                scrollCloseDirection = .conventionalBack
                mode                 = .list
                focusedID            = focusedID ?? entries.first?.id

            case "preview.back":
                closeList()

            default:
                let parts = action.id.split(separator: ".")
                guard parts.count == 3, let id = UUID(uuidString: String(parts[2])) else { return }

                switch parts[1] {
                    case "select": select(id, extendingRange: false)
                    case "remove": remove([id])
                    default: break
                }
        }
    }

    private func handle(
        _ event: FileShelfEntryInteraction,
        for id : UUID
    ) {
        guard mode == .list else {
            if case .click = event {
                scrollCloseDirection = .conventionalBack
                mode                 = .list
                focusedID            = focusedID ?? entries.first?.id
            }
            return
        }

        guard entries.contains(where: { $0.id == id }) else { return }

        renameHint = false
        switch event {
            case .click(let modifiers):
                select(id, extendingRange: modifiers.contains(.shift))

            case .prepareDrag:
                if !selectedIDs.contains(id) {
                    selectedIDs       = [id]
                    focusedID         = id
                    selectionAnchorID = id
                }

            case .moveFocus(let offset, let extendSelection):
                moveFocus(offset: offset, extendSelection: extendSelection)

            case .delete:
                remove(selectedIDs.isEmpty ? [focusedID ?? id] : selectedIDs)

            case .selectAll:
                selectedIDs       = entries.map(\.id)
                focusedID         = focusedID ?? selectedIDs.first
                selectionAnchorID = selectedIDs.first
        }
    }

    private func select(
        _ id          : UUID,
        extendingRange: Bool
    ) {
        focusedID = id
        let visible = entries
        if extendingRange,
           let anchorID = selectionAnchorID,
           let anchor = visible.firstIndex(where: { $0.id == anchorID }),
           let target = visible.firstIndex(where: { $0.id == id }) {
            selectedIDs = Array(visible[min(anchor, target)...max(anchor, target)].map(\.id))
        } else {
            if let index = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: index) }
            else { selectedIDs.append(id) }
            selectionAnchorID = id
        }
    }

    private func moveFocus(
        offset         : Int,
        extendSelection: Bool
    ) {
        let visible = entries
        guard !visible.isEmpty else { return }

        let current = focusedID.flatMap { id in visible.firstIndex(where: { $0.id == id }) }
            ?? (offset < 0 ? visible.count : -1)
        let next = min(max(current + offset, 0), visible.count - 1)
        let id   = visible[next].id
        focusedID = id
        if extendSelection {
            let anchorID = selectionAnchorID ?? visible[min(max(current, 0), visible.count - 1)].id
            selectionAnchorID = anchorID
            if let anchor = visible.firstIndex(where: { $0.id == anchorID }) {
                selectedIDs = Array(visible[min(anchor, next)...max(anchor, next)].map(\.id))
            }
        } else {
            selectedIDs       = [id]
            selectionAnchorID = id
        }
    }

    private func navigateByScroll(_ direction: FileShelfScrollDirection) {
        guard !entries.isEmpty else { return }

        if mode == .deck {
            scrollCloseDirection = direction.inverse
            mode                 = .list
            focusedID            = focusedID ?? entries.first?.id
        } else if direction.isHorizontal {
            let offset = direction == .horizontalPositive ? -1 : 1
            if offset < 0, focusedID == entries.first?.id,
               direction == scrollCloseDirection {
                closeList()
            } else {
                moveFocus(offset: offset, extendSelection: false)
            }
        } else if direction == scrollCloseDirection {
            closeList()
        }
    }

    private func closeList() {
        mode              = .deck
        selectedIDs       = []
        focusedID         = nil
        selectionAnchorID = nil
        renameHint        = false
    }

    private func remove(_ ids: [UUID]) {
        removedIDs.formUnion(ids)
        selectedIDs.removeAll { ids.contains($0) }

        if let focusedID, ids.contains(focusedID) {
            self.focusedID = entries.first?.id
        }

        if let selectionAnchorID, ids.contains(selectionAnchorID) {
            self.selectionAnchorID = self.focusedID
        }
    }

    private func requestRename() {
        if mode == .deck {
            mode       = .list
            focusedID  = entries.first?.id
            renameHint = true
            return
        }

        guard selectedIDs.count <= 1 else { return }
        guard let id = selectedIDs.first ?? focusedID,
              let entry = entries.first(where: { $0.id == id })
        else { return }

        let path   = entry.name as NSString
        let suffix = path.pathExtension.isEmpty ? "" : ".\(path.pathExtension)"
        renamedNames[id] = "\(path.deletingPathExtension) rinominato\(suffix)"
        renameHint       = false
    }
}

@MainActor
private struct PreviewAssets: ContentAssetResolving {

    func image(for assetID: String) -> Image? { nil }
}

#Preview("Ripiano") {
    FileShelfDesignPreview()
}

#endif
