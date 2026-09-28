//
//  NativeFileDragOfferHint.swift
//  CascadeKit
//

import AppKit
import Foundation

/// NativeFileDragOfferHint takes a best-effort look at the global drag
/// pasteboard for early UI routing.
///
/// This hint never authorizes a drop. The destination must still validate the
/// `NSDraggingInfo` pasteboard delivered by AppKit before accepting any files.
@MainActor
enum NativeFileDragOfferHint {

    private static let maximumItemCount = 32
    private static let promiseTypes    : Set<NSPasteboard.PasteboardType> = [
        .init("com.apple.pasteboard.promised-file-url"),
        .init("com.apple.pasteboard.promised-file-content-type")
    ]

    static func validates(
        _ pasteboard                   : NSPasteboard,
        changeCount expectedChangeCount: Int
    ) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount,
              let items = pasteboard.pasteboardItems,
              (1...maximumItemCount).contains(items.count)
        else { return false }

        for item in items {
            guard promiseTypes.isDisjoint(with: item.types),
                  item.types.contains(.fileURL),
                  let value = item.string(forType: .fileURL),
                  let url = URL(string: value),
                  url.isFileURL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return false }
        }

        // Fail closed if the global drag pasteboard changed while metadata was read.
        return pasteboard.changeCount == expectedChangeCount
    }
}
