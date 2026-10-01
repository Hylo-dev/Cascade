//
//  HostDraggingInfo.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

@MainActor
final class HostDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {

    let draggingPasteboard         : NSPasteboard
    let draggingLocation           : NSPoint
    let draggingSequenceNumber     : Int
    let draggingDestinationWindow  : NSWindow?
    let draggingSourceOperationMask: NSDragOperation
    let draggedImageLocation       : NSPoint = .zero
    let draggedImage               : NSImage? = nil
    let draggingSource             : Any? = nil

    var draggingFormation        : NSDraggingFormation = .default
    var animatesToDestination     = false
    var numberOfValidItemsForDrop = 0

    let springLoadingHighlight: NSSpringLoadingHighlight = .none

    init(
        pasteboard       : NSPasteboard,
        location         : NSPoint,
        sequenceNumber   : Int,
        operationMask    : NSDragOperation = .copy,
        destinationWindow: NSWindow? = nil
    ) {
        draggingPasteboard          = pasteboard
        draggingLocation            = location
        draggingSequenceNumber      = sequenceNumber
        draggingSourceOperationMask = operationMask
        draggingDestinationWindow   = destinationWindow
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }

    func enumerateDraggingItems(
        options enumOpts  : NSDraggingItemEnumerationOptions = [],
        for view          : NSView?,
        classes classArray: [AnyClass],
        searchOptions     : [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block       : @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}
