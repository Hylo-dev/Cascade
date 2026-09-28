//
//  FileShelfDragSource.swift
//  Cascade
//

import AppKit
import CascadeRuntime
import SwiftUI

/// FileShelfDragSource is the app-only native interaction wrapper. A click
/// activates the DTO action; crossing the drag threshold starts one file
/// promise per prepared item.
@MainActor
struct FileShelfDragSource: NSViewRepresentable {

    let content          : AnyView
    let files            : [PreparedFile]
    let accessibilityName: String
    let expandsOnScroll  : Bool
    var scrollNavigation : FileShelfScrollNavigation?
    let activate         : @MainActor () -> Void
    var interaction      : (@MainActor (FileShelfEntryInteraction) -> Void)?
    var resolveDragFiles : (@MainActor () -> [PreparedFile])?
    var navigateByScroll : @MainActor (FileShelfScrollDirection) -> Void
    let copy             : @Sendable (PreparedFile, URL) async throws -> Void

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
        self.content           = content
        self.files             = files
        self.accessibilityName = accessibilityName
        self.expandsOnScroll   = expandsOnScroll
        self.scrollNavigation  = scrollNavigation
        self.activate          = activate
        self.interaction       = interaction
        self.resolveDragFiles  = resolveDragFiles
        self.navigateByScroll  = navigateByScroll
        self.copy              = copy
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

    func updateNSView(
        _ view : FileShelfDragView,
        context: Context
    ) {
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
