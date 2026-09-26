import AppKit
import CascadeContracts
import CascadeKit
import CascadePresentation
import CascadeRuntime
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// App-owned adapter between the durable local host and the shared shelf renderer.
@MainActor
final class FileShelfController: NotchContextualPage {
    let id = "cascade.file-shelf"
    let contentHeight: CGFloat = 187
    let accessibilityLabel = "Ripiano"

    private(set) var contentRevision: UInt64 = 0
    private(set) var isOccupied = false
    private(set) var statusMessage: String?
    private(set) var preparedFiles: [UUID: PreparedFile] = [:]
    private(set) var presentation: FileWorkspacePresentation

    private let host: FileWorkspaceHost?
    private var contentChanged: @MainActor (Bool) -> Void
    private let preview = FileShelfPreviewController()
    private var snapshot: FileWorkspaceSnapshot
    private var mode: FileWorkspaceMode = .deck
    private var selectedIDs: [UUID] = []
    private var actions: [String: LocalAction] = [:]
    private var hoverURLs: [URL]?
    private var hoverIDs: [URL: UUID] = [:]
    private var admissionInFlight = false
    private var deliveryFailureMessage: String?
    private var started = false
    private var lifecycleGeneration: UInt64 = 0
    private var isStarting = false
    private var loadGeneration: UInt64 = 0
    private var admissionTask: Task<Void, Never>?
    private var deliveryRefreshTask: Task<Void, Never>?

    private enum LocalAction {
        case openList
        case closeList
        case nextPage(String)
        case select(UUID)
        case remove(UUID)
        case relink(UUID)
        case preview(UUID)
        case reveal(UUID)
    }

    init(
        host             : FileWorkspaceHost,
        preferenceChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.host = host
        contentChanged = preferenceChanged
        snapshot = Self.emptySnapshot
        presentation = Self.emptyPresentation
    }

    init(
        startupError     : any Error,
        preferenceChanged: @escaping @MainActor (Bool) -> Void
    ) {
        host = nil
        contentChanged = preferenceChanged
        snapshot = Self.emptySnapshot
        presentation = Self.emptyPresentation
        statusMessage = Self.message(for: startupError)
    }

    func start() async {
        guard !started, !isStarting else { return }
        guard let host else {
            rebuildPresentation()
            return
        }
        isStarting = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        do {
            try await host.restore()
            guard generation == lifecycleGeneration, isStarting else {
                try? await host.close()
                return
            }
            isStarting = false
            started = true
            await reload(cursor: nil, mode: .deck, clearsStatus: true)
        } catch {
            guard generation == lifecycleGeneration, isStarting else { return }
            isStarting = false
            statusMessage = message(for: error)
            rebuildPresentation()
        }
    }

    func stop() {
        lifecycleGeneration &+= 1
        loadGeneration &+= 1
        isStarting = false
        started = false
        admissionTask?.cancel()
        admissionTask = nil
        admissionInFlight = false
        hoverURLs = nil
        hoverIDs.removeAll()
        deliveryRefreshTask?.cancel()
        deliveryRefreshTask = nil
        preview.close()
        if let host { Task { try? await host.close() } }
    }

    func setContentChanged(_ callback: @escaping @MainActor (Bool) -> Void) {
        contentChanged = callback
    }

    func showHover(_ urls: [URL]?) {
        if let urls {
            clearDeliveryFailure()
            let bounded = Array(urls.prefix(32))
            guard hoverURLs != bounded else { return }
            hoverURLs = bounded
            hoverIDs = bounded.reduce(into: [:]) { result, url in
                result[url] = hoverIDs[url] ?? UUID()
            }
            statusMessage = "Rilascia per aggiungere"
            rebuildPresentation()
        } else {
            guard !admissionInFlight, hoverURLs != nil else { return }
            hoverURLs = nil
            hoverIDs.removeAll()
            statusMessage = nil
            rebuildPresentation()
        }
    }

    func showUnsupportedDrop() {
        guard !admissionInFlight else { return }
        clearDeliveryFailure()
        hoverURLs = nil
        hoverIDs.removeAll()
        statusMessage = "Sono accettati solo file locali regolari, non cartelle o file promessi."
        rebuildPresentation()
    }

    func acceptDrop(_ urls: [URL]) -> Bool {
        guard started, !admissionInFlight, !urls.isEmpty, urls.count <= 32 else { return false }
        clearDeliveryFailure()
        admissionInFlight = true
        if hoverURLs != urls {
            hoverIDs = urls.reduce(into: [:]) { result, url in result[url] = UUID() }
        }
        hoverURLs = urls
        statusMessage = "Aggiunta in corso…"
        rebuildPresentation()
        admissionTask = Task { [weak self] in await self?.acceptRegularFiles(urls) }
        return true
    }

    func acceptRegularFiles(_ urls: [URL]) async {
        guard let host else { return }
        guard started, !urls.isEmpty, urls.count <= 32 else {
            if started { showUnsupportedDrop() }
            return
        }
        clearDeliveryFailure()
        admissionInFlight = true
        if hoverURLs == nil {
            hoverURLs = urls
            hoverIDs = urls.reduce(into: [:]) { result, url in result[url] = UUID() }
        }
        do {
            _ = try await host.addOriginals(urls)
            guard started else { return }
            hoverURLs = nil
            hoverIDs.removeAll()
            admissionInFlight = false
            await reload(cursor: nil, mode: .deck, clearsStatus: true)
        } catch {
            guard started else { return }
            hoverURLs = nil
            hoverIDs.removeAll()
            admissionInFlight = false
            statusMessage = message(for: error)
            rebuildPresentation()
        }
        admissionTask = nil
    }

    func perform(_ descriptor: ActionDescriptor) async {
        guard let action = actions[descriptor.id] else { return }
        if clearDeliveryFailure() { rebuildPresentation() }
        switch action {
        case .openList:
            mode = .list
            rebuildPresentation()
        case .closeList:
            selectedIDs = []
            await reload(cursor: nil, mode: .deck, clearsStatus: false)
        case .nextPage(let cursor):
            selectedIDs = []
            await reload(cursor: cursor, mode: .list, clearsStatus: false)
        case .select(let id):
            if let index = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: index) }
            else if selectedIDs.count < 12 { selectedIDs.append(id) }
            rebuildPresentation()
        case .remove(let id):
            await remove(id)
        case .relink(let id):
            await relink(id)
        case .preview(let id):
            await showPreview(id)
        case .reveal(let id):
            await reveal(id)
        }
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        let workspace = try? CascadeFileWorkspace(
            presentation,
            assets  : EmptyShelfAssets(),
            dispatch: { [weak self] descriptor in
                Task { await self?.perform(descriptor) }
            },
            thumbnail: { entry in
                guard let type = UTType(entry.typeIdentifier) else { return nil }
                return Image(nsImage: NSWorkspace.shared.icon(for: type))
            },
            wrapEntry: { [weak self] entry, action, content in
                guard let self else { return content }
                return AnyView(FileShelfDragSource(
                    content          : content,
                    files            : self.filesForDrag(from: entry.id),
                    accessibilityName: entry.name,
                    activate         : { [weak self] in
                        guard let self, let action else { return }
                        Task { await self.perform(action) }
                    },
                    copy: { [weak self, host] prepared, destination in
                        guard let host else { throw FileWorkspaceError.ioFailure }
                        do {
                            try await host.copy(prepared, to: destination)
                            await self?.deliveryCompleted(error: nil)
                        } catch {
                            await self?.deliveryCompleted(error: error)
                            throw error
                        }
                    }
                ))
            },
            conversionUnavailableExplanation: "Conversione non ancora disponibile"
        )
        return AnyView(
            VStack(spacing: 3) {
                if presentation.snapshot.entries.isEmpty {
                    Label("Trascina qui i file", systemImage: "tray.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHint("Rilascia file locali regolari per aggiungerli al ripiano")
                } else if let workspace {
                    workspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(statusMessage == "Rilascia per aggiungere" ? Color.secondary : Color.orange)
                        .lineLimit(1)
                        .help(statusMessage)
                        .accessibilityLabel(statusMessage)
                }
            }
            .frame(
                width : context.availableSize.width,
                height: min(contentHeight, context.availableSize.height)
            )
        )
    }

    private func reload(
        cursor      : String?,
        mode        : FileWorkspaceMode,
        clearsStatus: Bool
    ) async {
        guard host != nil else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        do {
            let loaded = try await loadPage(cursor: cursor)
            guard generation == loadGeneration else { return }
            snapshot = loaded.snapshot
            preparedFiles = loaded.prepared
            self.mode = mode
            selectedIDs = selectedIDs.filter { loaded.prepared[$0] != nil }
            if clearsStatus { statusMessage = nil }
            let occupied = snapshot.totalCount > 0
            isOccupied = occupied
            rebuildPresentation()
        } catch {
            guard generation == loadGeneration else { return }
            statusMessage = message(for: error)
            rebuildPresentation()
        }
    }

    private func loadPage(
        cursor: String?
    ) async throws -> (snapshot: FileWorkspaceSnapshot, prepared: [UUID: PreparedFile]) {
        guard let host else { throw FileWorkspaceError.ioFailure }
        var lastError: (any Error)?
        for _ in 0..<2 {
            let snapshot = try await host.snapshot(cursor: cursor)
            do {
                let prepared = snapshot.entries.isEmpty
                    ? [] : try await host.prepareItems(ids: snapshot.entries.map(\.id))
                return (snapshot, Dictionary(uniqueKeysWithValues: prepared.map { ($0.itemID, $0) }))
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FileWorkspaceError.ioFailure
    }

    private func rebuildPresentation() {
        let displayed = hoverURLs.flatMap(makeHoverSnapshot) ?? snapshot
        let displayedMode: FileWorkspaceMode = hoverURLs == nil ? mode : .deck
        let displayedSelection = hoverURLs == nil
            ? selectedIDs.filter { id in displayed.entries.contains(where: { $0.id == id }) }
            : []
        var bindings: [FileWorkspaceActionBinding] = []
        var local: [String: LocalAction] = [:]
        if hoverURLs == nil {
            if displayedMode == .deck, !displayed.entries.isEmpty {
                append(.openList, label: "Apri elenco file", local: .openList, to: &bindings, map: &local)
            } else if displayedMode == .list {
                append(.closeList, label: "Chiudi elenco", local: .closeList, to: &bindings, map: &local)
                if let cursor = displayed.nextCursor {
                    append(.nextPage, label: "Pagina successiva", local: .nextPage(cursor), to: &bindings, map: &local)
                }
                for entry in displayed.entries {
                    append(.select, entry: entry, label: "Seleziona \(entry.name)", local: .select(entry.id), to: &bindings, map: &local)
                    if entry.ownership == .externalReference {
                        append(.remove, entry: entry, label: "Rimuovi \(entry.name)", local: .remove(entry.id), to: &bindings, map: &local)
                    }
                    if entry.availability == .available {
                        append(.preview, entry: entry, label: "Anteprima \(entry.name)", local: .preview(entry.id), to: &bindings, map: &local)
                        append(.reveal, entry: entry, label: "Mostra \(entry.name) nel Finder", local: .reveal(entry.id), to: &bindings, map: &local)
                    } else if entry.ownership == .externalReference {
                        append(.relink, entry: entry, label: "Ricollega \(entry.name)", local: .relink(entry.id), to: &bindings, map: &local)
                    }
                }
            }
        }
        do {
            presentation = try FileWorkspacePresentation(
                snapshot        : displayed,
                mode            : displayedMode,
                selectedEntryIDs: displayedSelection,
                formats         : [],
                selectedFormatID: nil,
                actions         : bindings
            )
            actions = local
        } catch {
            statusMessage = "Il ripiano non può essere mostrato."
        }
        contentRevision &+= 1
        contentChanged(isOccupied)
    }

    private func append(
        _ role : FileWorkspaceActionBinding.Role,
        entry  : FileWorkspaceEntry? = nil,
        label  : String,
        local  : LocalAction,
        to bindings: inout [FileWorkspaceActionBinding],
        map    : inout [String: LocalAction]
    ) {
        let suffix = entry?.id.uuidString.lowercased() ?? String(bindings.count)
        let id = "shelf.\(role.rawValue).\(suffix)"
        guard let descriptor = try? ActionDescriptor(id: id, label: label),
              let binding = try? FileWorkspaceActionBinding(
                role      : role,
                entryID   : entry?.id,
                descriptor: descriptor
              ) else { return }
        bindings.append(binding)
        map[id] = local
    }

    private func makeHoverSnapshot(_ urls: [URL]) -> FileWorkspaceSnapshot? {
        let entries = urls.compactMap { url -> FileWorkspaceEntry? in
            let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
            return try? FileWorkspaceEntry(
                id              : hoverIDs[url] ?? UUID(),
                name            : url.lastPathComponent,
                typeIdentifier  : type,
                availability    : .receiving,
                ownership       : .externalReference,
                thumbnailAssetID: nil
            )
        }
        return try? FileWorkspaceSnapshot(
            revision  : 0,
            entries   : entries,
            totalCount: entries.count,
            nextCursor: nil,
            jobs      : []
        )
    }

    private func filesForDrag(from entryID: UUID) -> [PreparedFile] {
        let ids = selectedIDs.contains(entryID) ? selectedIDs : [entryID]
        return snapshot.entries.compactMap { entry in
            ids.contains(entry.id) ? preparedFiles[entry.id] : nil
        }
    }

    private func remove(_ id: UUID) async {
        guard let host else { return }
        guard let entry = snapshot.entries.first(where: { $0.id == id }),
              entry.ownership == .externalReference else { return }
        do {
            try await host.removeExternalReference(id: id, revision: snapshot.revision)
            selectedIDs.removeAll { $0 == id }
            await reload(cursor: nil, mode: mode, clearsStatus: true)
        } catch {
            statusMessage = message(for: error)
            await reload(cursor: nil, mode: mode, clearsStatus: false)
        }
    }

    private func relink(_ id: UUID) async {
        guard let host else { return }
        guard snapshot.entries.contains(where: {
            $0.id == id && $0.ownership == .externalReference
        }) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Scegli il file da ricollegare"
        guard await panel.begin() == .OK, let url = panel.url else { return }
        do {
            try await host.relinkExternalReference(id: id, to: url, revision: snapshot.revision)
            await reload(cursor: nil, mode: mode, clearsStatus: true)
        } catch {
            statusMessage = message(for: error)
            await reload(cursor: nil, mode: mode, clearsStatus: false)
        }
    }

    private func showPreview(_ id: UUID) async {
        guard let host else { return }
        guard let prepared = preparedFiles[id] else { return }
        do {
            try await host.withCheckedURL(for: prepared) { [preview] url in
                try await preview.present(url)
            }
        } catch {
            statusMessage = message(for: error)
            rebuildPresentation()
        }
    }

    private func reveal(_ id: UUID) async {
        guard let host else { return }
        guard let prepared = preparedFiles[id] else { return }
        do {
            try await host.withCheckedURL(for: prepared) { url in
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        } catch {
            statusMessage = message(for: error)
            rebuildPresentation()
        }
    }

    private func deliveryCompleted(error: (any Error)?) {
        if let error {
            let failure = message(for: error)
            deliveryFailureMessage = failure
            statusMessage = failure
            rebuildPresentation()
        }
        deliveryRefreshTask?.cancel()
        deliveryRefreshTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await self.reload(
                cursor      : nil,
                mode        : self.mode,
                clearsStatus: self.deliveryFailureMessage == nil
            )
        }
    }

    @discardableResult
    private func clearDeliveryFailure() -> Bool {
        guard let deliveryFailureMessage else { return false }
        if statusMessage == deliveryFailureMessage { statusMessage = nil }
        self.deliveryFailureMessage = nil
        return true
    }

    private func message(for error: any Error) -> String { Self.message(for: error) }

    private static func message(for error: any Error) -> String {
        switch error as? FileWorkspaceError {
        case .unsupported: "Il file non è supportato."
        case .unavailable: "Il file non è disponibile. Puoi ricollegarlo o rimuoverlo."
        case .permissionDenied: "Cascade non dispone più del permesso per questo file."
        case .quotaExceeded: "Il ripiano non dispone di spazio sufficiente."
        case .staleRevision: "Il ripiano è cambiato. Riprova."
        case .interrupted: "L’operazione è stata interrotta."
        case .ioFailure, .none: "Impossibile completare l’operazione sul file."
        }
    }

    private static let emptySnapshot = try! FileWorkspaceSnapshot(
        revision  : 0,
        entries   : [],
        totalCount: 0,
        nextCursor: nil,
        jobs      : []
    )

    private static let emptyPresentation = try! FileWorkspacePresentation(
        snapshot        : emptySnapshot,
        mode            : .deck,
        selectedEntryIDs: [],
        formats         : [],
        selectedFormatID: nil,
        actions         : []
    )
}

@MainActor
private struct EmptyShelfAssets: ContentAssetResolving {
    func image(for assetID: String) -> Image? { nil }
}

@MainActor
final class FileShelfUnsupportedNotice: NotchTransientNotice {
    let id = "cascade.file-shelf.unsupported"
    let sourceID = "cascade.file-shelf"
    let contentRevision: UInt64
    let displayDuration: TimeInterval = 4
    let privacy: NotchActivityPrivacy = .standard
    let compactPreferredSideWidth: CGFloat? = 148
    let accessibilityLabel = "Solo file locali. Cartelle e file promessi non sono supportati."

    init(revision: UInt64) { contentRevision = revision }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            Label("Solo file locali", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height)
                .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            Text("Cartelle e file promessi non supportati")
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height)
                .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height)
                .accessibilityLabel(accessibilityLabel)
        )
    }
}

/// Owns the Quick Look window for exactly as long as the host keeps its checked lease open.
@MainActor
private final class FileShelfPreviewController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<Void, Never>?

    func present(_ url: URL) async throws {
        close()
        guard let preview = QLPreviewView(
            frame: CGRect(x: 0, y: 0, width: 720, height: 520),
            style: .normal
        ) else {
            throw FileWorkspaceError.ioFailure
        }
        preview.previewItem = url as NSURL
        preview.autostarts = true
        let panel = NSPanel(
            contentRect: preview.frame,
            styleMask : [.titled, .closable, .resizable],
            backing   : .buffered,
            defer     : false
        )
        panel.title = url.lastPathComponent
        panel.contentView = preview
        panel.delegate = self
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        await withCheckedContinuation { continuation = $0 }
    }

    func close() {
        panel?.close()
        finish()
    }

    func windowWillClose(_ notification: Notification) { finish() }

    private func finish() {
        panel?.delegate = nil
        panel = nil
        continuation?.resume()
        continuation = nil
    }
}
