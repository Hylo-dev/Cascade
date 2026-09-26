//
//  FileWorkspacePresentationTests.swift
//  Cascade
//

import CascadeContracts
import CascadePresentation
import AppKit
import Foundation
import SwiftUI
import Testing

@Suite
struct FileWorkspacePresentationTests {
    @Test
    func deckUsesFourStableCardsAndTotalCountOverflow() {
        let transforms = FileWorkspaceLayout.cardTransforms(
            count       : 40,
            reduceMotion: false
        )
        #expect(transforms.count == 4)
        #expect(transforms.map(\.index) == [0, 1, 2, 3])
        #expect(transforms[0].rotationDegrees > 0)
        #expect(transforms.dropFirst().allSatisfy { $0.rotationDegrees < 0 })
        #expect(FileWorkspaceLayout.overflowCount(totalCount: 40) == 36)
        #expect(FileWorkspaceLayout.overflowCount(totalCount: 4) == 0)
    }

    @Test
    func reducedMotionKeepsIdentityAndRemovesRotation() {
        let animated = FileWorkspaceLayout.cardTransforms(
            count       : 4,
            reduceMotion: false
        )
        let reduced = FileWorkspaceLayout.cardTransforms(
            count       : 4,
            reduceMotion: true
        )
        #expect(animated.map(\.index) == reduced.map(\.index))
        #expect(reduced.allSatisfy { $0.rotationDegrees == 0 && $0.yOffset == 0 })
        #expect(Set(reduced.map(\.xOffset)).count == 4)
    }

    @Test(arguments: [CGSize(width: 420, height: 180), CGSize(width: 680, height: 260)])
    func conversionArrowStaysCenteredBetweenNonoverlappingGroups(_ size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        let frames = FileWorkspaceLayout.conversionFrames(in: bounds)
        let gapMidX = (frames.inputs.maxX + frames.results.minX) / 2

        #expect(abs(frames.arrow.midX - gapMidX) < 0.001)
        #expect(abs(frames.arrow.midY - bounds.midY) < 0.001)
        #expect(!frames.inputs.intersects(frames.arrow))
        #expect(!frames.arrow.intersects(frames.results))
        #expect(!frames.selector.intersects(frames.arrow))
        #expect(!frames.controls.intersects(frames.arrow))
    }

    @Test
    func routingReturnsThePublishedDescriptorUnchanged() throws {
        let entryID = UUID()
        let descriptor = try ActionDescriptor(
            id     : "select-entry",
            label  : "Select file",
            payload: Data([1, 4, 9])
        )
        let presentation = try workspace(
            totalCount: 1,
            actions: [
                FileWorkspaceActionBinding(
                    role      : .select,
                    entryID   : entryID,
                    descriptor: descriptor
                ),
            ],
            entryID: entryID
        )

        #expect(presentation.action(for: .select, entryID: entryID) == descriptor)
        #expect(presentation.action(for: .remove, entryID: entryID) == nil)
    }

    @Test
    @MainActor
    func optionalHostHooksDecorateEntriesWithoutChangingDefaultCallers() throws {
        let presentation = try workspace(totalCount: 4, mode: .deck)
        var thumbnails: Set<UUID> = []
        var wrapped: Set<UUID> = []
        let view = try CascadeFileWorkspace(
            presentation,
            assets  : PreviewAssets(),
            dispatch: { _ in },
            thumbnail: { entry in
                thumbnails.insert(entry.id)
                return Image(systemName: "doc.text.fill")
            },
            wrapEntry: { entry, _, content in
                wrapped.insert(entry.id)
                return content
            },
            conversionUnavailableExplanation: "Conversione non ancora disponibile"
        )

        _ = try render(
            view.frame(width: 420, height: 190),
            size: CGSize(width: 420, height: 190)
        )

        #expect(thumbnails == Set(presentation.snapshot.entries.map(\.id)))
        #expect(wrapped == Set(presentation.snapshot.entries.map(\.id)))
    }

    @Test
    @MainActor
    func rendersRepresentativeWorkspacePreviews() throws {
        let fixtures: [(String, FileWorkspaceMode, Int, CGSize, Bool, Bool)] = [
            ("deck-1", .deck, 1, CGSize(width: 360, height: 180), false, false),
            ("deck-4", .deck, 4, CGSize(width: 420, height: 190), false, false),
            ("deck-5", .deck, 5, CGSize(width: 420, height: 190), false, false),
            ("list-40", .list, 40, CGSize(width: 560, height: 280), false, false),
            ("conversion-compact", .conversion, 4, CGSize(width: 440, height: 190), false, false),
            ("conversion-running-compact", .conversion, 5, CGSize(width: 440, height: 190), false, true),
            ("conversion-long-labels", .conversion, 4, CGSize(width: 680, height: 260), true, false),
            ("deck-reduced-motion", .deck, 4, CGSize(width: 420, height: 190), false, false),
        ]
        for fixture in fixtures {
            let presentation = try workspace(
                totalCount      : fixture.2,
                mode            : fixture.1,
                completedResults: fixture.4,
                runningJob      : fixture.5
            )
            let view = try CascadeFileWorkspace(
                presentation,
                assets  : PreviewAssets(),
                dispatch: { _ in Issue.record("Preview must not dispatch") },
                reduceMotion: fixture.0 == "deck-reduced-motion"
            )
            let image = try render(
                view
                    .frame(width: fixture.3.width, height: fixture.3.height)
                    .background(.black)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark),
                size: fixture.3
            )
            #expect(image.size.width > 0 && image.size.height > 0)
            if let directory = ProcessInfo.processInfo.environment["CASCADE_FILE_WORKSPACE_PREVIEW_DIR"],
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let data = bitmap.representation(using: .png, properties: [:]) {
                let destination = URL(fileURLWithPath: directory)
                    .appendingPathComponent(fixture.0)
                    .appendingPathExtension("png")
                try data.write(to: destination)
            }
        }
    }

    @MainActor
    private func render<Content: View>(
        _ content: Content,
        size     : CGSize
    ) throws -> NSImage {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask : [.borderless],
            backing   : .buffered,
            defer     : false
        )
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        window.orderOut(nil)
        return image
    }

    private func workspace(
        totalCount: Int,
        actions   : [FileWorkspaceActionBinding] = [],
        entryID   : UUID = UUID(),
        mode      : FileWorkspaceMode? = nil,
        completedResults: Bool = false,
        runningJob: Bool = false
    ) throws -> FileWorkspacePresentation {
        let visibleCount = min(totalCount, 32)
        let entries = try (0..<visibleCount).map { index in
            try FileWorkspaceEntry(
                id              : index == 0 ? entryID : UUID(),
                name            : index == 0
                    ? "A very long quarterly report filename that must truncate without changing layout.pdf"
                    : "File \(index + 1).png",
                typeIdentifier  : index == 0 ? "com.adobe.pdf" : "public.png",
                availability    : .available,
                ownership       : .externalReference,
                thumbnailAssetID: nil
            )
        }
        let format = try FileConversionFormat(
            id                  : "portable-network-graphics",
            label               : "Portable Network Graphics",
            outputTypeIdentifier: "public.png"
        )
        let resolvedMode = mode ?? (totalCount == 40 ? .list : (totalCount == 4 ? .conversion : .deck))
        let jobs: [FileConversionJobSnapshot]
        if runningJob {
            jobs = [try FileConversionJobSnapshot(
                id       : UUID(),
                state    : .running,
                progress : 0.42,
                resultIDs: []
            )]
        } else if completedResults, let resultID = entries.last?.id {
            jobs = [try FileConversionJobSnapshot(
                id       : UUID(),
                state    : .completed,
                progress : 1,
                resultIDs: [resultID]
            )]
        } else {
            jobs = []
        }
        let representativeActions: [FileWorkspaceActionBinding]
        if actions.isEmpty {
            var built: [FileWorkspaceActionBinding] = []
            if resolvedMode == .deck {
                built.append(try FileWorkspaceActionBinding(
                    role      : .openList,
                    descriptor: ActionDescriptor(id: "open-list", label: "Open file list")
                ))
                built.append(try FileWorkspaceActionBinding(
                    role      : .convert,
                    descriptor: ActionDescriptor(id: "convert", label: "Convert files")
                ))
            }
            if resolvedMode == .list {
                built.append(try FileWorkspaceActionBinding(
                    role      : .closeList,
                    descriptor: ActionDescriptor(id: "close-list", label: "Close file list")
                ))
                if totalCount > 32 {
                    built.append(try FileWorkspaceActionBinding(
                        role      : .nextPage,
                        descriptor: ActionDescriptor(id: "next-page", label: "Load more files")
                    ))
                }
                built.append(try FileWorkspaceActionBinding(
                    role      : .convert,
                    descriptor: ActionDescriptor(id: "convert", label: "Convert files")
                ))
                for (index, entry) in entries.enumerated() {
                    built.append(try FileWorkspaceActionBinding(
                        role      : .select,
                        entryID   : entry.id,
                        descriptor: ActionDescriptor(id: "select-\(index)", label: "Select \(entry.name)")
                    ))
                }
                if let first = entries.first {
                    built.append(try FileWorkspaceActionBinding(
                        role      : .remove,
                        entryID   : first.id,
                        descriptor: ActionDescriptor(id: "remove-selected", label: "Remove selected file")
                    ))
                }
            }
            if resolvedMode == .conversion {
                built.append(try FileWorkspaceActionBinding(
                    role      : .selectFormat,
                    formatID  : format.id,
                    descriptor: ActionDescriptor(id: "select-format", label: "Select PNG")
                ))
                built.append(try FileWorkspaceActionBinding(
                    role      : .start,
                    descriptor: ActionDescriptor(id: "start", label: "Start conversion")
                ))
            }
            representativeActions = built
        } else {
            representativeActions = actions
        }
        return try FileWorkspacePresentation(
            snapshot: FileWorkspaceSnapshot(
                revision  : 1,
                entries   : entries,
                totalCount: totalCount,
                nextCursor: totalCount > 32 ? "next-page" : nil,
                jobs      : jobs
            ),
            mode            : resolvedMode,
            selectedEntryIDs: runningJob ? Array(entries.prefix(4).map(\.id)) : entries.first.map { [$0.id] } ?? [],
            formats         : [format],
            selectedFormatID: resolvedMode == .conversion ? format.id : nil,
            actions         : representativeActions
        )
    }

    @MainActor
    private struct PreviewAssets: ContentAssetResolving {
        func image(for assetID: String) -> Image? { Image(systemName: "doc.fill") }
    }
}
