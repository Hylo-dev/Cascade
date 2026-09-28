//
//  LiveActivityContext.swift
//  CascadeKit
//

/// LiveActivityContext lets visible content declare a real data change.
/// A revoked context becomes inert, including when a late asynchronous result
/// reaches an activity after another activity has taken its place.
@MainActor
public final class LiveActivityContext {

    private var onInvalidate: (() -> Void)?

    init(onInvalidate: @escaping () -> Void) {
        self.onInvalidate = onInvalidate
    }

    public func invalidate() {
        onInvalidate?()
    }

    func revoke() {
        onInvalidate = nil
    }
}
