//
//  CaffeinateOptionsCheck.swift
//  Cascade
//

#if DEBUG
import AppKit
import CascadeContracts
import CascadeKit

/// CaffeinateOptionsCheck selects the real bundled plugin for an isolated preview.
/// The normal broker, native assertion owner and notch container remain in use;
/// temporary arrangements keep this probe from changing the user's saved grid.
@MainActor
enum CaffeinateOptionsCheck {

    static var isRequested: Bool {
        CommandLine.arguments.contains("--preview-caffeinate-options") || shouldRun
    }

    static var shouldRun: Bool {
        CommandLine.arguments.contains("--check-caffeinate-options")
    }

    private static let preferenceSuite = "com.cascade.caffeinate-options-check." + UUID().uuidString

    static func isolatedPreferences() -> UserDefaults? {
        UserDefaults(suiteName: preferenceSuite)
    }

    static func removePreferences() {
        UserDefaults(suiteName: preferenceSuite)?.removePersistentDomain(forName: preferenceSuite)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// run drives real rendered controls; it never manufactures broker acceptance
    /// or a host origin. Missing native accessibility keeps this check unqualified.
    static func run(
        controller: CaffeinateController,
        engine    : NotchEngine
    ) async throws {
        try await Task.sleep(for: .seconds(2))
        try require(engine.expandedDisplayID != nil, "No expanded Caffeinate display")
        try require(!controller.source.state.isActive, "Preview started with an active session")

        try press { label in
            label.contains("Caffeinate") && label != "Caffeinate options"
        }
        try await settled(controller)
        try require(controller.source.state.isActive, "Cup did not start the native session")
        try require(backButton() == nil, "Cup opened the options page")
        print("CHECK: cup starts the native session independently")

        try press { $0 == "Caffeinate options" }
        try await Task.sleep(for: .milliseconds(450))
        try require(backButton() != nil, "Options did not open through the broker")
        try press { $0 == "Duration: 15 min" }
        try await settled(controller)
        try require(controller.minutes == 15, "Duration selection was not applied")
        guard let deadline = controller.source.state.until else {
            throw Failure(description: "Finite duration has no deadline")
        }
        let displayWasAwake = controller.keepDisplayAwake
        try press { $0 == "Keep display awake" }
        try await settled(controller)
        try require(controller.keepDisplayAwake != displayWasAwake, "Display option did not change")
        try require(controller.source.state.until == deadline, "Display option moved the deadline")
        print("CHECK: duration and display controls update the native owner")

        try press { $0 == "Stop Caffeinate" }
        try await settled(controller)
        try require(!controller.source.state.isActive, "Stop retained the active session")
        try press { $0 == "Caffeinate credits" }
        try await settled(controller)
        try require(controller.source.state.showsCredits, "Credits did not appear")
        guard let back = backButton() else { throw Failure(description: "Native Back is absent") }
        back.performClick(nil)
        try await Task.sleep(for: .milliseconds(450))
        try require(backButton() == nil, "Back retained the options page")
        print("CHECK: Stop, credits and native Back passed")
    }

    private static func settled(_ controller: CaffeinateController) async throws {
        for _ in 0..<25 {
            try await Task.sleep(for: .milliseconds(100))
            if !controller.source.state.isBusy { return }
        }
        throw Failure(description: "Native Caffeinate operation did not settle within 2.5 seconds")
    }

    private static func require(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw Failure(description: reason) }
    }

    private static func press(matching matches: (String) -> Bool) throws {
        var remaining = 512
        var visited = Set<ObjectIdentifier>()
        for root in NSApp.windows.filter(\.isVisible).compactMap(\.contentView) {
            if let control = findControl(root, depth: 0, remaining: &remaining, visited: &visited, matches: matches) {
                try require(control.accessibilityPerformPress(), "Native accessibility press rejected")
                return
            }
        }
        throw Failure(description: "No enabled rendered Caffeinate AX control; native UI check unqualified")
    }

    private static func findControl(
        _ value : Any,
        depth   : Int,
        remaining: inout Int,
        visited : inout Set<ObjectIdentifier>,
        matches : (String) -> Bool
    ) -> (any NSAccessibilityProtocol)? {
        guard remaining > 0, depth <= 12 else { return nil }
        remaining -= 1
        if let object = value as? NSObject {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
        }
        guard let element = value as? any NSAccessibilityProtocol else { return nil }
        if let role = element.accessibilityRole(), [.button, .checkBox].contains(role),
           element.isAccessibilityEnabled(), matches(element.accessibilityLabel() ?? "") {
            return element
        }
        let children = element.accessibilityChildren() ?? []
        for child in children {
            if let control = findControl(child, depth: depth + 1, remaining: &remaining, visited: &visited, matches: matches) { return control }
        }
        return nil
    }

    private static func backButton() -> NSButton? {
        var pending = NSApp.windows.filter(\.isVisible).compactMap(\.contentView)
        var remaining = 512
        while let view = pending.popLast(), remaining > 0 {
            remaining -= 1
            guard !view.isHidden else { continue }
            if let button = view as? NSButton,
               button.accessibilityIdentifier() == "notch.options.back" { return button }
            pending.append(contentsOf: view.subviews)
        }
        return nil
    }
}
#endif
