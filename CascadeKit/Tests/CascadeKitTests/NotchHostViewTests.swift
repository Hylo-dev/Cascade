//
//  NotchHostViewTests.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

@MainActor
struct NotchHostViewTests {
    @Test
    func fileDestinationIsUnregisteredUntilTheShelfEnablesIt() throws {
        let host = makeHost()
        host.setFileDropEnabled(false)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let drag = HostDraggingInfo(
            pasteboard: makePasteboard(items: [source]),
            location: CGPoint(x: 100, y: 100),
            sequenceNumber: 0
        )

        #expect(host.registeredDraggedTypes.isEmpty)
        #expect(host.draggingEntered(drag).isEmpty)
    }

    @Test
    func fileDestinationAcceptsOneBoundedRegularBatchAndDeliversItOnce() throws {
        let host = makeHost()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let pasteboard = makePasteboard(items: [source])
        let drag = HostDraggingInfo(
            pasteboard: pasteboard,
            location: CGPoint(x: 100, y: 100),
            sequenceNumber: 7
        )
        var hovered: [[URL]?] = []
        var dropped: [[URL]] = []
        host.onFileDragHoverChanged = { hovered.append($0) }
        host.onFileDrop = { dropped.append($0); return true }

        #expect(host.draggingEntered(drag) == .copy)
        #expect(host.draggingUpdated(drag) == .copy)
        #expect(host.performDragOperation(drag))
        #expect(hovered == [[source], nil])
        #expect(dropped == [[source]])
    }

    @Test
    func activeSpaceReceiverTranslatesAndForwardsTheCompleteNativeDropLifecycle() throws {
        let host = makeHost()
        let visualPanel = NotchPanel(contentView: host)
        visualPanel.setFrame(
            CGRect(x: 300, y: 400, width: 400, height: 200),
            display: false
        )
        let receiver = NotchFileDropReceiverPanel()
        let receiverFrame = CGRect(x: 250, y: 350, width: 360, height: 180)
        receiver.setFileDropDestination(host, enabled: true)
        receiver.activate(frame: receiverFrame)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let drag = HostDraggingInfo(
            pasteboard: makePasteboard(items: [source]),
            location: CGPoint(x: 150, y: 150),
            sequenceNumber: 11,
            destinationWindow: receiver
        )
        let outside = HostDraggingInfo(
            pasteboard: drag.draggingPasteboard,
            location: CGPoint(x: 60, y: 60),
            sequenceNumber: 12,
            destinationWindow: receiver
        )
        var dropped: [[URL]] = []
        host.onFileDrop = { dropped.append($0); return true }

        #expect(receiver.fileDropDestinationTypeCount == 3)
        #expect(receiver.responds(to: #selector(NSDraggingDestination.draggingEntered(_:))))
        #expect(receiver.draggingEntered(outside).isEmpty)
        #expect(receiver.prepareForDragOperation(outside) == false)
        #expect(receiver.performDragOperation(outside) == false)
        receiver.activate(frame: receiverFrame)
        #expect(receiver.draggingEntered(drag) == .copy)
        #expect(receiver.draggingUpdated(drag) == .copy)
        receiver.draggingExited(drag)
        #expect(receiver.ignoresMouseEvents == false)
        #expect(receiver.draggingEntered(drag) == .copy)
        #expect(receiver.prepareForDragOperation(drag))
        #expect(receiver.performDragOperation(drag))
        receiver.concludeDragOperation(drag)
        #expect(dropped == [[source]])
        #expect(receiver.ignoresMouseEvents)

        host.setFileDropEnabled(false)
        receiver.setFileDropDestination(nil, enabled: false)
        #expect(receiver.fileDropDestinationTypeCount == 0)
        #expect(receiver.draggingEntered(drag).isEmpty)
        #expect(receiver.prepareForDragOperation(drag) == false)
        #expect(receiver.performDragOperation(drag) == false)
    }

    @Test
    func fileDestinationCanResolveAfterTheDragEntersOutsideItsLiveShape() throws {
        let host = makeHost()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let pasteboard = makePasteboard(items: [source])
        let outside = HostDraggingInfo(
            pasteboard: pasteboard,
            location: CGPoint(x: 10, y: 10),
            sequenceNumber: 8
        )
        let inside = HostDraggingInfo(
            pasteboard: pasteboard,
            location: CGPoint(x: 100, y: 100),
            sequenceNumber: 8
        )
        var hovered: [[URL]?] = []
        host.onFileDragHoverChanged = { hovered.append($0) }
        host.onFileDrop = { _ in true }

        #expect(host.draggingEntered(outside).isEmpty)
        #expect(host.draggingUpdated(inside) == .copy)
        #expect(host.performDragOperation(inside))
        #expect(hovered == [[source], nil])
    }

    @Test
    func performDropRevalidatesAPasteboardChangedDuringTheSameGesture() throws {
        let host = makeHost()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.txt")
        let replacement = directory.appendingPathComponent("replacement.txt")
        try Data("first".utf8).write(to: first)
        try Data("replacement".utf8).write(to: replacement)
        let pasteboard = makePasteboard(items: [first])
        let drag = HostDraggingInfo(
            pasteboard: pasteboard,
            location: CGPoint(x: 100, y: 100),
            sequenceNumber: 10
        )
        var dropped: [[URL]] = []
        host.onFileDrop = { dropped.append($0); return true }

        #expect(host.draggingEntered(drag) == .copy)
        pasteboard.clearContents()
        pasteboard.writeObjects([replacement as NSURL])
        #expect(host.performDragOperation(drag))
        #expect(dropped == [[replacement]])
    }

    @Test
    func fileDestinationRejectsASourceThatDoesNotOfferCopy() throws {
        let host = makeHost()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let drag = HostDraggingInfo(
            pasteboard: makePasteboard(items: [source]),
            location: CGPoint(x: 100, y: 100),
            sequenceNumber: 9,
            operationMask: .move
        )

        #expect(host.draggingEntered(drag).isEmpty)
        #expect(host.performDragOperation(drag) == false)
    }

    @Test
    func fileDestinationRejectsPromiseMixedOversizedAndPhysicalCutoutOffers() throws {
        let host = makeHost()
        host.setFileDropExclusionFrame(CGRect(x: 180, y: 160, width: 40, height: 40))
        var unsupportedCount = 0
        host.onUnsupportedFileDrop = { unsupportedCount += 1 }

        let promiseBoard = NSPasteboard(name: .init("test.promise.\(UUID())"))
        promiseBoard.clearContents()
        let promise = NSPasteboardItem()
        promise.setString("public.text", forType: .init("com.apple.pasteboard.promised-file-content-type"))
        promiseBoard.writeObjects([promise])
        #expect(host.draggingEntered(HostDraggingInfo(
            pasteboard: promiseBoard,
            location: CGPoint(x: 100, y: 100),
            sequenceNumber: 1
        )).isEmpty)

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let mixedBoard = makePasteboard(items: [source], appendText: true)
        #expect(host.draggingEntered(HostDraggingInfo(
            pasteboard: mixedBoard,
            location: CGPoint(x: 100, y: 100),
            sequenceNumber: 2
        )).isEmpty)

        let oversized = makePasteboard(items: Array(repeating: source, count: 33))
        #expect(host.draggingEntered(HostDraggingInfo(
            pasteboard: oversized,
            location: CGPoint(x: 100, y: 100),
            sequenceNumber: 3
        )).isEmpty)

        let valid = makePasteboard(items: [source])
        #expect(host.draggingEntered(HostDraggingInfo(
            pasteboard: valid,
            location: CGPoint(x: 200, y: 180),
            sequenceNumber: 4
        )).isEmpty)
        #expect(unsupportedCount == 3)
    }

    @Test
    func activeFileIntakeAcceptsARegularFileOverThePhysicalCutout() throws {
        let host = makeHost()
        let cutout = CGRect(x: 180, y: 160, width: 40, height: 40)
        host.setFileDropExclusionFrame(cutout)
        host.setFileDropIntakeFrame(CGRect(x: 80, y: 20, width: 240, height: 180))
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let drag = HostDraggingInfo(
            pasteboard: makePasteboard(items: [source]),
            location: CGPoint(x: 200, y: 180),
            sequenceNumber: 5
        )
        var dropped: [[URL]] = []
        host.onFileDrop = { dropped.append($0); return true }

        #expect(host.draggingEntered(drag) == .copy)
        #expect(host.performDragOperation(drag))
        #expect(dropped == [[source]])
    }

    @Test
    func activeFileIntakeOwnsWideHitTestingAndEndedCancelsItsHover() throws {
        let host = makeHost()
        let intake = CGRect(x: 20, y: 20, width: 360, height: 180)
        host.setFileDropIntakeFrame(intake)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let drag = HostDraggingInfo(
            pasteboard: makePasteboard(items: [source]),
            location: CGPoint(x: 40, y: 30),
            sequenceNumber: 6
        )
        var hovered: [[URL]?] = []
        host.onFileDragHoverChanged = { hovered.append($0) }

        #expect(!host.containsInteractivePoint(CGPoint(x: 40, y: 30)))
        #expect(host.hitTest(CGPoint(x: 40, y: 30)) === host)
        #expect(host.draggingEntered(drag) == .copy)
        host.draggingEnded(drag)

        #expect(hovered == [[source], nil])
    }
    @Test
    func glassHasNoOpaqueBackingBlockingTheDesktop() throws {
        guard #available(macOS 26, *),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return }
        let host = makeHost()
        let backing = try #require(host.layer?.sublayers?.first as? CAShapeLayer)
        #expect(backing.isHidden)
        #expect(host.containsInteractivePoint(CGPoint(x: 200, y: 100)))
    }

    @Test
    func restingChromeReleasesGlassAndPreservesItsOpaqueSilhouette() throws {
        let host = makeHost()
        host.apply(
            geometry        : NotchGeometry(leftExtent: 90, rightExtent: 90, height: 33, bottomCornerRadius: 14, topCornerRadius: 4),
            centerX         : 200,
            topY            : 200,
            isChromeVisible : true,
            borderOpacity   : 0,
            materialProgress: 0
        )
        let backing = try #require(host.layer?.sublayers?.first as? CAShapeLayer)
        #expect(!backing.isHidden)
        #expect(host.containsInteractivePoint(CGPoint(x: 200, y: 180)))
        #expect(!host.containsInteractivePoint(CGPoint(x: 200, y: 160)))
    }

    @Test
    func glassBodyCoversTheNotchBodyAndRoundsOnlyItsBottomCorners() {
        let body = NotchGlassBody(
            geometry: NotchGeometry(leftExtent: 100, rightExtent: 60, height: 80, bottomCornerRadius: 30, topCornerRadius: 12),
            centerX : 200,
            topY    : 200
        )
        // Asymmetric sides, and one radius above the top edge.
        #expect(body.rect == CGRect(x: 100, y: 120, width: 160, height: 110))
        #expect(body.cornerRadius == 30)
    }

    @Test
    func glassTransformMapsTheLaidOutBodyOntoTheCurrentOne() {
        let reference = NotchGlassBody(rect: CGRect(x: 60, y: 40, width: 280, height: 180), cornerRadius: 44)
        let current   = NotchGlassBody(rect: CGRect(x: 110, y: 150, width: 180, height: 60), cornerRadius: 18)
        for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)] {
            let transform = current.transform(from: reference, anchor: anchor)
            // A layer renders local p at origin + A + T(p − A).
            func rendered(_ p: CGPoint) -> CGPoint {
                let a = CGPoint(x: anchor.x * reference.rect.width, y: anchor.y * reference.rect.height)
                let moved = CGPoint(x: p.x - a.x, y: p.y - a.y).applying(transform)
                return CGPoint(x: reference.rect.minX + a.x + moved.x, y: reference.rect.minY + a.y + moved.y)
            }
            let bottomLeft = rendered(.zero)
            let topRight = rendered(CGPoint(x: reference.rect.width, y: reference.rect.height))
            #expect(abs(bottomLeft.x - current.rect.minX) < 0.001 && abs(bottomLeft.y - current.rect.minY) < 0.001)
            #expect(abs(topRight.x - current.rect.maxX) < 0.001 && abs(topRight.y - current.rect.maxY) < 0.001)
        }
        #expect(reference.transform(from: reference, anchor: .zero).isIdentity)
    }

    @Test
    func nativeContrastUsesTheCompositorAndLeavesControlsInteractive() throws {
        let host = makeHost()
        let effect = try #require(host.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView)
        #expect(effect.blendingMode == .behindWindow)
        #expect(effect.state == .active)
        #expect(!effect.isHidden)
        #expect(effect.hitTest(CGPoint(x: 200, y: 100)) == nil)
        #expect(host.containsInteractivePoint(CGPoint(x: 200, y: 61)))
        #expect(!host.containsInteractivePoint(CGPoint(x: 200, y: 59)))
    }

    @Test
    func hidingChromeDeactivatesTheNativeContrastEffect() throws {
        let host = makeHost()
        let effect = try #require(host.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView)
        host.apply(
            geometry: NotchGeometry(leftExtent: 90, rightExtent: 90, height: 33, bottomCornerRadius: 14, topCornerRadius: 4),
            centerX: 200,
            topY: 200,
            isChromeVisible: true,
            borderOpacity: 0
        )
        #expect(effect.isHidden)
        #expect(effect.state == .inactive)
    }

    @Test
    func nativeMaterialCoversTheBottomRimAndHaloAtFullExpansion() throws {
        let host = makeHost()
        host.apply(
            geometry: NotchGeometry(leftExtent: 140, rightExtent: 140, height: 200, bottomCornerRadius: 22, topCornerRadius: 8),
            centerX: 200,
            topY: 200,
            isChromeVisible: true
        )
        let effect = try #require(host.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView)
        let shape = try #require(host.layer?.sublayers?.first as? CAShapeLayer)
        let outline = try #require(shape.path?.boundingBoxOfPath)
        #expect(effect.frame.contains(outline.insetBy(dx: 0, dy: -NotchBorderRenderer.visualOutset)))
    }

    @Test
    func hitTestingDeliversClicksToControlsInsideTheShape() {
        let host = makeHost()
        let button = NSButton(frame: CGRect(x: 100, y: 100, width: 60, height: 30))
        host.addSubview(button)
        #expect(host.hitTest(CGPoint(x: 120, y: 115)) === button)
    }

    @Test
    func roundedCornerDoesNotConsumeTheUnderlyingMenuClick() {
        let host = makeHost()
        #expect(host.hitTest(CGPoint(x: 60, y: 61)) == nil)
        #expect(host.hitTest(CGPoint(x: 20, y: 115)) == nil)
    }

    @Test
    func haloGutterDoesNotShiftTheInteractiveOutline() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 212))
        let host = makeHost()
        root.addSubview(host)
        host.setFrameOrigin(CGPoint(x: 0, y: 12))

        // AppKit supplies superview coordinates: y=71 is below the path's
        // actual lower edge at 72, despite lying inside its unshifted bounds.
        #expect(host.hitTest(CGPoint(x: 200, y: 71)) == nil)
        #expect(host.hitTest(CGPoint(x: 200, y: 73)) != nil)
    }

    private func makeHost() -> NotchHostView {
        let host = NotchHostView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        host.setFileDropEnabled(true)
        host.apply(
            geometry: NotchGeometry(
                leftExtent: 140,
                rightExtent: 140,
                height: 140,
                bottomCornerRadius: 22,
                topCornerRadius: 8
            ),
            centerX: 200,
            topY: 200,
            isChromeVisible: true
        )
        return host
    }

    private func makePasteboard(items: [URL], appendText: Bool = false) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("test.files.\(UUID())"))
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = items as [NSURL]
        if appendText { objects.append("unsupported" as NSString) }
        pasteboard.writeObjects(objects)
        return pasteboard
    }
}
