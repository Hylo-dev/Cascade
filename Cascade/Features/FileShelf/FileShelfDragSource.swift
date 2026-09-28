import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum FileShelfScrollDirection: Equatable {
    case horizontalPositive
    case horizontalNegative
    case verticalPositive
    case verticalNegative

    static let conventionalBack = Self.horizontalPositive

    var inverse: Self {
        switch self {
        case .horizontalPositive: .horizontalNegative
        case .horizontalNegative: .horizontalPositive
        case .verticalPositive: .verticalNegative
        case .verticalNegative: .verticalPositive
        }
    }

    var isHorizontal: Bool {
        switch self {
        case .horizontalPositive, .horizontalNegative: true
        case .verticalPositive, .verticalNegative: false
        }
    }
}

nonisolated enum FileShelfScrollNavigation: Equatable {
    case open
    case close(expectedDirection: FileShelfScrollDirection)
}

nonisolated enum FileShelfEntryInteraction: Equatable {
    case click(modifiers: NSEvent.ModifierFlags)
    case prepareDrag
    case moveFocus(offset: Int, extendSelection: Bool)
    case delete
    case selectAll
}

nonisolated struct FileShelfScrollGesturePolicy {
    private static let threshold: CGFloat = 4
    private var distance = CGSize.zero
    private var isTracking = false
    private var didNavigate = false

    static func exceedsIntentThreshold(_ distance: CGSize) -> Bool {
        hypot(distance.width, distance.height) >= threshold
    }

    mutating func navigation(
        delta                    : CGSize,
        phase                    : NSEvent.Phase,
        momentumPhase            : NSEvent.Phase,
        behavior                 : FileShelfScrollNavigation,
        isAtHorizontalLeadingEdge _: Bool
    ) -> FileShelfScrollDirection? {
        guard momentumPhase.isEmpty else { return nil }
        if phase.contains(.cancelled) {
            reset()
            return nil
        }
        if phase.contains(.began) {
            reset()
            isTracking = true
        } else if phase.isEmpty {
            if !isTracking { isTracking = true }
        } else if !isTracking {
            // A renderer replacement can receive the tail of the gesture that
            // opened it. Wait for fresh fingers instead of closing immediately.
            return nil
        }

        defer {
            if phase.contains(.ended) { reset() }
        }
        guard !didNavigate else { return nil }
        distance.width += delta.width
        distance.height += delta.height
        guard Self.exceedsIntentThreshold(distance) else { return nil }

        let direction: FileShelfScrollDirection
        if abs(distance.width) >= abs(distance.height) {
            direction = distance.width >= 0 ? .horizontalPositive : .horizontalNegative
        } else {
            direction = distance.height >= 0 ? .verticalPositive : .verticalNegative
        }
        switch behavior {
        case .open:
            break
        case .close(let expectedDirection):
            // Horizontal gestures browse one item at a time. The controller
            // decides whether a backward gesture at the first item closes.
            guard direction.isHorizontal || direction == expectedDirection else { return nil }
        }
        didNavigate = true
        return direction
    }

    private mutating func reset() {
        distance = .zero
        isTracking = false
        didNavigate = false
    }
}

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
    var scrollNavigation: FileShelfScrollNavigation?
    let activate: @MainActor () -> Void
    var interaction: (@MainActor (FileShelfEntryInteraction) -> Void)?
    var resolveDragFiles: (@MainActor () -> [PreparedFile])?
    var navigateByScroll: @MainActor (FileShelfScrollDirection) -> Void
    let copy: @Sendable (PreparedFile, URL) async throws -> Void

    init(
        content          : AnyView,
        files            : [PreparedFile],
        accessibilityName: String,
        expandsOnScroll  : Bool = false,
        scrollNavigation : FileShelfScrollNavigation? = nil,
        activate         : @escaping @MainActor () -> Void,
        interaction      : (@MainActor (FileShelfEntryInteraction) -> Void)? = nil,
        resolveDragFiles : (@MainActor () -> [PreparedFile])? = nil,
        navigateByScroll : @escaping @MainActor (FileShelfScrollDirection) -> Void = { _ in },
        copy             : @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        self.content = content
        self.files = files
        self.accessibilityName = accessibilityName
        self.expandsOnScroll = expandsOnScroll
        self.scrollNavigation = scrollNavigation
        self.activate = activate
        self.interaction = interaction
        self.resolveDragFiles = resolveDragFiles
        self.navigateByScroll = navigateByScroll
        self.copy = copy
    }

    func makeNSView(context: Context) -> FileShelfDragView {
        FileShelfDragView(
            content          : content,
            files            : files,
            accessibilityName: accessibilityName,
            expandsOnScroll  : expandsOnScroll,
            scrollNavigation : scrollNavigation,
            activate         : activate,
            interaction      : interaction,
            resolveDragFiles : resolveDragFiles,
            navigateByScroll : navigateByScroll,
            copy             : copy
        )
    }

    func updateNSView(_ view: FileShelfDragView, context: Context) {
        view.update(
            content          : content,
            files            : files,
            accessibilityName: accessibilityName,
            expandsOnScroll  : expandsOnScroll,
            scrollNavigation : scrollNavigation,
            activate         : activate,
            interaction      : interaction,
            resolveDragFiles : resolveDragFiles,
            navigateByScroll : navigateByScroll,
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
struct FileShelfKeyboardContainer: NSViewRepresentable {
    let content: AnyView
    let interaction: @MainActor (FileShelfEntryInteraction) -> Void

    func makeNSView(context: Context) -> FileShelfKeyboardView {
        FileShelfKeyboardView(content: content, interaction: interaction)
    }

    func updateNSView(_ view: FileShelfKeyboardView, context: Context) {
        view.update(content: content, interaction: interaction)
    }
}

@MainActor
final class FileShelfKeyboardView: NSView, NotchKeyboardFocusTarget {
    private let hosting: NSHostingView<AnyView>
    private var interaction: @MainActor (FileShelfEntryInteraction) -> Void

    init(content: AnyView, interaction: @escaping @MainActor (FileShelfEntryInteraction) -> Void) {
        hosting = NSHostingView(rootView: content)
        self.interaction = interaction
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    func update(
        content: AnyView,
        interaction: @escaping @MainActor (FileShelfEntryInteraction) -> Void
    ) {
        hosting.rootView = content
        self.interaction = interaction
    }

    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123, 126: interaction(.moveFocus(offset: -1, extendSelection: extend))
        case 124, 125: interaction(.moveFocus(offset: 1, extendSelection: extend))
        case 51, 117: interaction(.delete)
        case 0 where event.modifierFlags.contains(.command): interaction(.selectAll)
        default: super.keyDown(with: event)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let window, window.firstResponder === self, window.isKeyWindow {
            window.resignKey()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

@MainActor
final class FileShelfDragView: NSView, NSDraggingSource, NotchKeyboardFocusTarget {
    private static let dragThreshold: CGFloat = 4

    private let hosting: NSHostingView<AnyView>
    private var files: [PreparedFile]
    private var expandsOnScroll: Bool
    private var scrollNavigation: FileShelfScrollNavigation?
    private var activate: @MainActor () -> Void
    private var interaction: (@MainActor (FileShelfEntryInteraction) -> Void)?
    private var resolveDragFiles: (@MainActor () -> [PreparedFile])?
    private var navigateByScroll: @MainActor (FileShelfScrollDirection) -> Void
    private var copy: @Sendable (PreparedFile, URL) async throws -> Void
    private var downLocation: NSPoint?
    private var beganDrag = false
    private var scrollPolicy = FileShelfScrollGesturePolicy()

    init(
        content          : AnyView,
        files            : [PreparedFile],
        accessibilityName: String,
        expandsOnScroll  : Bool = false,
        scrollNavigation : FileShelfScrollNavigation? = nil,
        activate         : @escaping @MainActor () -> Void,
        interaction      : (@MainActor (FileShelfEntryInteraction) -> Void)? = nil,
        resolveDragFiles : (@MainActor () -> [PreparedFile])? = nil,
        navigateByScroll : @escaping @MainActor (FileShelfScrollDirection) -> Void = { _ in },
        copy             : @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        hosting = NSHostingView(rootView: content)
        self.files = files
        self.expandsOnScroll = expandsOnScroll
        self.scrollNavigation = scrollNavigation
        self.activate = activate
        self.interaction = interaction
        self.resolveDragFiles = resolveDragFiles
        self.navigateByScroll = navigateByScroll
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
        scrollNavigation : FileShelfScrollNavigation?,
        activate         : @escaping @MainActor () -> Void,
        interaction      : (@MainActor (FileShelfEntryInteraction) -> Void)?,
        resolveDragFiles : (@MainActor () -> [PreparedFile])?,
        navigateByScroll : @escaping @MainActor (FileShelfScrollDirection) -> Void,
        copy             : @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        hosting.rootView = content
        self.files = files
        self.expandsOnScroll = expandsOnScroll
        self.scrollNavigation = scrollNavigation
        self.activate = activate
        self.interaction = interaction
        self.resolveDragFiles = resolveDragFiles
        self.navigateByScroll = navigateByScroll
        self.copy = copy
        setAccessibilityLabel(accessibilityName)
    }

    override func mouseDown(with event: NSEvent) {
        let responder = keyboardContainer ?? self
        window?.makeFirstResponder(responder)
        window?.makeKey()
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
        interaction?(.prepareDrag)
        let dragFiles = resolveDragFiles?() ?? files
        guard !dragFiles.isEmpty else { return }
        let items = dragFiles.enumerated().map { index, file -> NSDraggingItem in
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
        if shouldActivate {
            if let interaction { interaction(.click(modifiers: event.modifierFlags)) }
            else { activate() }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let responder = keyboardContainer ?? self
        window?.makeFirstResponder(responder)
        window?.makeKey()
        let behavior = scrollNavigation ?? (expandsOnScroll ? .open : nil)
        guard let behavior, event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }
        let direction = scrollPolicy.navigation(
            delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            behavior: behavior,
            isAtHorizontalLeadingEdge: isAtHorizontalLeadingEdge
        )
        if let direction {
            if scrollNavigation == nil { activate() }
            else { navigateByScroll(direction) }
        }
    }

    nonisolated static func shouldExpand(for distance: CGSize) -> Bool {
        FileShelfScrollGesturePolicy.exceedsIntentThreshold(distance)
    }

    private var isAtHorizontalLeadingEdge: Bool {
        guard let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView else { return true }
        return scrollView.documentVisibleRect.minX <= documentView.bounds.minX + 1
    }

    private var keyboardContainer: FileShelfKeyboardView? {
        var ancestor = superview
        while let view = ancestor {
            if let container = view as? FileShelfKeyboardView { return container }
            ancestor = view.superview
        }
        return nil
    }

    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123, 126:
            interaction?(.moveFocus(offset: -1, extendSelection: extend))
        case 124, 125:
            interaction?(.moveFocus(offset: 1, extendSelection: extend))
        case 51, 117:
            interaction?(.delete)
        case 0 where event.modifierFlags.contains(.command):
            interaction?(.selectAll)
        case 36, 49:
            activate()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let window, window.firstResponder === self, window.isKeyWindow {
            window.resignKey()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
