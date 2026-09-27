import AppKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

/// Creates one native promise provider whose weak delegate is retained by userInfo.
enum FileShelfPromiseProvider {
    @MainActor
    static func make(
        file: PreparedFile,
        copy: @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) -> NSFilePromiseProvider {
        let delegate = FileShelfPromiseDelegate(file: file, copy: copy)
        let provider = NSFilePromiseProvider(
            fileType: file.typeIdentifier,
            delegate: delegate
        )
        provider.userInfo = delegate
        return provider
    }
}

private final class FileShelfPromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let file: PreparedFile
    private let copy: @Sendable (PreparedFile, URL) async throws -> Void

    init(
        file: PreparedFile,
        copy: @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        self.file = file
        self.copy = copy
    }

    @MainActor
    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        file.name
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        let file = file
        let copy = copy
        let completion = FilePromiseCompletion(completionHandler)
        Task {
            do {
                try await copy(file, url)
                completion.call(nil)
            } catch {
                completion.call(error)
            }
        }
    }
}

private nonisolated final class FilePromiseCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (((any Error)?) -> Void)?

    init(_ completion: @escaping ((any Error)?) -> Void) {
        self.completion = completion
    }

    func call(_ error: (any Error)?) {
        lock.lock()
        let completion = completion
        self.completion = nil
        lock.unlock()
        completion?(error)
    }
}

/// App-only native interaction wrapper. A click activates the DTO action;
/// crossing the drag threshold starts one file promise per prepared item.
@MainActor
struct FileShelfDragSource: NSViewRepresentable {
    let content: AnyView
    let files: [PreparedFile]
    let accessibilityName: String
    let expandsOnScroll: Bool
    let activate: @MainActor () -> Void
    let copy: @Sendable (PreparedFile, URL) async throws -> Void

    func makeNSView(context: Context) -> FileShelfDragView {
        FileShelfDragView(
            content          : content,
            files            : files,
            accessibilityName: accessibilityName,
            expandsOnScroll  : expandsOnScroll,
            activate         : activate,
            copy             : copy
        )
    }

    func updateNSView(_ view: FileShelfDragView, context: Context) {
        view.update(
            content          : content,
            files            : files,
            accessibilityName: accessibilityName,
            expandsOnScroll  : expandsOnScroll,
            activate         : activate,
            copy             : copy
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView    : FileShelfDragView,
        context   : Context
    ) -> CGSize? {
        let fitting = nsView.fittingSize
        return CGSize(
            width : proposal.width ?? fitting.width,
            height: proposal.height ?? fitting.height
        )
    }
}

@MainActor
final class FileShelfDragView: NSView, NSDraggingSource {
    private static let dragThreshold: CGFloat = 4

    private let hosting: NSHostingView<AnyView>
    private var files: [PreparedFile]
    private var expandsOnScroll: Bool
    private var activate: @MainActor () -> Void
    private var copy: @Sendable (PreparedFile, URL) async throws -> Void
    private var downLocation: NSPoint?
    private var beganDrag = false
    private var scrollDistance = CGSize.zero
    private var activatedByScroll = false

    init(
        content          : AnyView,
        files            : [PreparedFile],
        accessibilityName: String,
        expandsOnScroll  : Bool = false,
        activate         : @escaping @MainActor () -> Void,
        copy             : @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        hosting = NSHostingView(rootView: content)
        self.files = files
        self.expandsOnScroll = expandsOnScroll
        self.activate = activate
        self.copy = copy
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    func update(
        content          : AnyView,
        files            : [PreparedFile],
        accessibilityName: String,
        expandsOnScroll  : Bool,
        activate         : @escaping @MainActor () -> Void,
        copy             : @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        hosting.rootView = content
        self.files = files
        if self.expandsOnScroll != expandsOnScroll {
            scrollDistance = .zero
            activatedByScroll = false
        }
        self.expandsOnScroll = expandsOnScroll
        self.activate = activate
        self.copy = copy
        setAccessibilityLabel(accessibilityName)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        downLocation = convert(event.locationInWindow, from: nil)
        beganDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !beganDrag, let downLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - downLocation.x, current.y - downLocation.y) >= Self.dragThreshold else {
            return
        }
        beganDrag = true
        self.downLocation = nil
        guard !files.isEmpty else { return }
        let items = files.enumerated().map { index, file -> NSDraggingItem in
            let provider = FileShelfPromiseProvider.make(file: file, copy: copy)
            let item = NSDraggingItem(pasteboardWriter: provider)
            let offset = CGFloat(index) * 3
            let frame = CGRect(
                x     : current.x - 26 + offset,
                y     : current.y - 20 - offset,
                width : min(max(bounds.width, 52), 118),
                height: min(max(bounds.height, 40), 106)
            )
            let icon = UTType(file.typeIdentifier).map { NSWorkspace.shared.icon(for: $0) }
            item.setDraggingFrame(frame, contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        let releaseLocation = convert(event.locationInWindow, from: nil)
        let shouldActivate = downLocation != nil && !beganDrag && bounds.contains(releaseLocation)
        downLocation = nil
        beganDrag = false
        if shouldActivate { activate() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard expandsOnScroll else {
            super.scrollWheel(with: event)
            return
        }
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase == .began {
            scrollDistance = .zero
            activatedByScroll = false
        }
        scrollDistance.width += event.scrollingDeltaX
        scrollDistance.height += event.scrollingDeltaY
        if !activatedByScroll, Self.shouldExpand(for: scrollDistance) {
            activatedByScroll = true
            activate()
        }
        if event.phase == .ended || event.phase == .cancelled {
            scrollDistance = .zero
            activatedByScroll = false
        }
    }

    nonisolated static func shouldExpand(for distance: CGSize) -> Bool {
        hypot(distance.width, distance.height) >= 4
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 36 {
            activate()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
