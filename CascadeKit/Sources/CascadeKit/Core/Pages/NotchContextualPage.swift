import CoreGraphics
import SwiftUI

public nonisolated struct NotchContextualPageContext: Sendable {
    public let availableSize: CGSize
    /// Physical camera/sensor area in SwiftUI page coordinates (top-left origin).
    /// Content may use the top shoulders while keeping this center clear.
    public let centerObstructionFrame: CGRect

    public init(
        availableSize: CGSize,
        centerObstructionFrame: CGRect = .zero
    ) {
        self.availableSize = availableSize
        self.centerObstructionFrame = centerObstructionFrame
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
    var keepsExpandedPresentation: Bool { get }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView
}

public extension NotchContextualPage {
    var accessibilityLabel: String { id }
    var keepsExpandedPresentation: Bool { false }
}
