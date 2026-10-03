//
//  AddonWidgetDetailChecks.swift
//  Cascade
//

#if DEBUG
import AppKit
import CascadeContracts
import CascadeKit

/// AddonWidgetDetailChecks drives the compiled app's accessibility controls and
/// public host APIs. Finite waits allow native transitions to finish; this is
/// programmatic app evidence, never a claim of physical mouse or keyboard input.
@MainActor
enum AddonWidgetDetailChecks {

    struct Failure: Error, CustomStringConvertible {

        let reason: String
        var description: String { reason }
    }

    static func run(_ fixture: AddonWidgetDetailFixture, keepOpen: Bool) async throws {
        try await settle()
        try require(fixture.engine.expandedDisplayID != nil, "No expanded display; visible source unavailable")
        let initialHosts = visibleHostingViewCount()
        let initialBrightness = fixture.brightness
        try press(label: "Mock brightness \(Int(initialBrightness * 100))% +")
        try require(fixture.brightness > initialBrightness, "Independent compact brightness action did not run")
        try require(fixture.active == nil, "Compact brightness action opened detail")
        try await settle()
        print("CHECK: compact brightness changes fixture data without opening detail")

        try press(label: "Mock display options ›")
        let first = try binding(fixture.active, "Title action did not open detail through onWidgetAction")
        try require(first.origin.isValid, "Exact host-captured opening origin invalid")
        try await settle()
        try require(backButton() != nil, "Native Back button is absent")
        reportHost(fixture, state: "detail")

        try press(label: "Refresh mock source")
        let refreshed = try binding(fixture.active, "Same-lease refresh dismissed detail")
        try require(refreshed.request.leaseID == first.request.leaseID, "Refresh replaced lease")
        try require(refreshed.origin === first.origin, "Refresh reconstructed host origin")
        try require(refreshed.request.actionRequestID == first.request.actionRequestID, "Refresh replaced initial action binding")
        try require(refreshed.generation == first.generation, "Refresh replaced generation")
        try require(refreshed.expiresAt == first.expiresAt, "Refresh extended initial expiry")
        try require(refreshed.request.observedRevision > first.request.observedRevision, "Source revision did not advance")
        try await settle()
        try press(label: "Dim mock brightness")
        try require(fixture.brightness == 0.25, "Retained detail action did not use current source")
        try await settle()
        print("CHECK: retained detail actions and refresh preserve exact origin, initial binding and expiry")

        try pressBack()
        try require(fixture.active == nil && !first.origin.isValid, "Native Back retained authority")
        try require(!fixture.accept(first), "Dismissed reply reopened detail")
        try await settle()
        try require(visibleHostingViewCount() == initialHosts, "Back accumulated visible native hosts")
        print("CHECK: native Back dismisses and rejects late reply")

        fixture.defersOpening = true
        try press(label: "Mock display options ›")
        let pendingA = try binding(fixture.pending, "Pending A missing")
        try press(label: "Mock display options ›")
        let pendingB = try binding(fixture.pending, "Pending B missing")
        try require(!pendingA.origin.isValid && pendingB.origin.isValid, "Latest pending click did not revoke A")
        try require(!fixture.accept(pendingA), "Delayed A reply opened")
        try require(fixture.accept(pendingB), "Latest pending B reply rejected")
        fixture.dismiss(first)
        try require(fixture.active?.origin === pendingB.origin, "Obsolete exact-origin dismissal affected B")
        try await settle()
        try pressBack()
        try require(!fixture.accept(pendingA) && !fixture.accept(pendingB), "Back allowed pending reply to reopen")
        fixture.defersOpening = false
        try await settle()
        print("CHECK: actual compact clicks A/B select latest origin; Back rejects both replies")

        try press(label: "Mock display options ›")
        let beforeSourceChange = try binding(fixture.active, "Detail missing before stale-source check")
        try await settle()
        let obsoleteControl = try button(label: "Dim mock brightness")
        try fixture.refreshSource(refreshDetail: false)
        let unchangedBrightness = fixture.brightness
        _ = obsoleteControl.accessibilityPerformPress()
        try require(fixture.brightness == unchangedBrightness, "Copied stale detail control changed data")
        try require(!fixture.accept(beforeSourceChange), "Stale source revision accepted")
        try require(fixture.active?.origin === beforeSourceChange.origin, "Revision invalidation changed selection")
        try fixture.refreshDetailDocument()
        try await settle()
        print("CHECK: source revision disables old controls and rejects stale document")

        // Interrupt native transitions before their finite completion, then
        // inspect the settled AppKit hierarchy for visible-host accumulation.
        for _ in 0..<3 {
            try pressBack()
            try press(label: "Mock display options ›")
        }
        try await settle()
        try require(fixture.active?.origin.isValid == true, "Rapid Back/open lost current detail")
        try require(visibleHostingViewCount() == initialHosts, "Rapid transitions accumulated visible native hosts")
        print("CHECK: three rapid native Back/open retargets retain only settled visible hosts")

        let withdrawn = try binding(fixture.active, "Detail missing before withdrawal")
        try press(label: "Withdraw mock widget")
        try require(fixture.active == nil && !withdrawn.origin.isValid, "Withdrawal retained detail authority")
        try require(!fixture.accept(withdrawn), "Withdrawn source reopened")
        try await settle()
        try require(backButton() == nil, "Withdrawal retained native Back")
        try require(
            fixture.engine.captureOptionsOrigin(publicationID: fixture.publicationID, observedRevision: fixture.revision) == nil,
            "Withdrawn source minted an origin"
        )
        print("CHECK: withdrawal clears detail and source authority")

        if keepOpen {
            try fixture.replaceWithdrawnSource()
            try await settle()
            try press(label: "Mock display options ›")
            try await settle()
            try require(fixture.active?.origin.isValid == true && backButton() != nil, "Final detail unavailable for idle measurement")
            reportHost(fixture, state: "final-detail-open")
        }
        try require(fixture.lastFailure == nil, "Fixture callback failed: \(fixture.lastFailure ?? "unknown")")
    }

    private static func settle() async throws {
        try await Task.sleep(for: .milliseconds(450))
        try Task.checkCancellation()
    }

    private static func binding(
        _ value: AddonWidgetDetailFixture.Binding?,
        _ reason: String
    ) throws -> AddonWidgetDetailFixture.Binding {
        guard let value else { throw Failure(reason: reason) }
        return value
    }

    private static func require(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw Failure(reason: reason) }
    }

    private static func press(label: String) throws {
        let control = try button(label: label)
        try require(control.accessibilityPerformPress(), "Accessibility press rejected: \(label)")
    }

    private static func button(label: String) throws -> any NSAccessibilityProtocol {
        let candidates = NSApp.windows.filter(\.isVisible).compactMap(\.contentView)
        for root in candidates {
            if let control = findButton(root, label: label, remaining: 512) { return control }
        }
        throw Failure(reason: "Visible accessibility button unavailable: \(label); source may be hidden or screen locked")
    }

    private static func findButton(
        _ value: Any,
        label: String,
        remaining: Int
    ) -> (any NSAccessibilityProtocol)? {
        guard remaining > 0, let element = value as? any NSAccessibilityProtocol else { return nil }
        if element.accessibilityRole() == .button,
           element.accessibilityLabel() == label,
           element.isAccessibilityEnabled() {
            return element
        }
        for child in element.accessibilityChildren() ?? [] {
            if let control = findButton(child, label: label, remaining: remaining - 1) { return control }
        }
        return nil
    }

    private static func backButton() -> NSButton? {
        for window in NSApp.windows where window.isVisible {
            guard let root = window.contentView else { continue }
            if let button = nativeBack(in: root) { return button }
        }
        return nil
    }

    private static func nativeBack(in view: NSView) -> NSButton? {
        guard !view.isHidden else { return nil }
        if let button = view as? NSButton, button.accessibilityIdentifier() == "notch.options.back" {
            return button
        }
        for child in view.subviews {
            if let button = nativeBack(in: child) { return button }
        }
        return nil
    }

    private static func pressBack() throws {
        guard let button = backButton() else { throw Failure(reason: "Visible native Back unavailable") }
        button.performClick(nil)
    }

    private static func visibleHostingViewCount() -> Int {
        func count(_ view: NSView) -> Int {
            guard !view.isHidden else { return 0 }
            let ownCount = NSStringFromClass(type(of: view)).contains("NSHostingView") ? 1 : 0
            return ownCount + view.subviews.reduce(0) { $0 + count($1) }
        }
        return NSApp.windows.filter(\.isVisible).compactMap(\.contentView).reduce(0) { $0 + count($1) }
    }

    private static func reportHost(_ fixture: AddonWidgetDetailFixture, state: String) {
        let frame = fixture.engine.expandedFrame.map(NSStringFromRect) ?? "none"
        let display = fixture.engine.expandedDisplayID.map(String.init) ?? "none"
        print("HOST: state=\(state) display=\(display) frame=\(frame) visibleNativeHostingViews=\(visibleHostingViewCount())")
    }
}
#endif
