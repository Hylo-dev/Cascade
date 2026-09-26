import CoreGraphics
import SwiftUI

public nonisolated struct NotchContextualPageContext: Sendable {
    public let availableSize: CGSize

    public init(availableSize: CGSize) {
        self.availableSize = availableSize
    }
}

/// One app-owned page that may temporarily replace the ordinary expanded
/// activity/widget surface. It is deliberately a single slot, not a pager.
@MainActor
public protocol NotchContextualPage: AnyObject {
    var id: String { get }
    var contentRevision: UInt64 { get }
    var contentHeight: CGFloat { get }
    var accessibilityLabel: String { get }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView
}

public extension NotchContextualPage {
    var accessibilityLabel: String { id }
}
