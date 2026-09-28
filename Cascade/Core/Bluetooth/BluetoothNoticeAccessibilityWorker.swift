//
//  BluetoothNoticeAccessibilityWorker.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import os

/// BluetoothNoticeAccessibilityWorker bounds remote work and keeps it away from the UI thread.
actor BluetoothNoticeAccessibilityWorker {

    private var session             : BluetoothNoticeObservationSession?
    private var hints               : [BluetoothNoticeConnectionHint] = []
    private var connectedLabels     : Set<String>                     = []
    private var expiryTask          : Task<Void, Never>?
    private var inspectionDeadline   = Date.distantPast
    private var lastDiagnosticReason: String?

    private let logger = Logger(subsystem: "hylo.Cascade", category: "BluetoothNotice")

    /// start registers AX observers on each notice host process. The macOS 27 banner identifiers are
    /// verified in SystemBannerUI; live AX exposure remains OS-dependent.
    func start(processes: [String: pid_t]) throws -> BluetoothNoticeObservationSession {
        connectedLabels = loadConnectionLabels()
        guard !connectedLabels.isEmpty else {
            throw BluetoothNoticeAccessibilityError.unsupported("The system connection labels are unavailable.")
        }

        let signal = BluetoothNoticeObservationSignal()
        var hosts: [BluetoothNoticeAccessibilityHostSession] = []
        for (bundleID, processID) in processes.sorted(by: { $0.key < $1.key }) {
            let application = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(application, 0.1)

            var observer: AXObserver?
            let result = AXObserverCreate(processID, { _, _, _, context in
                guard let context else { return }

                let signal = Unmanaged<BluetoothNoticeObservationSignal>.fromOpaque(context).takeUnretainedValue()
                signal.continuation.yield(())
            }, &observer)
            guard result == .success, let observer else {
                logger.error("AX observer unavailable for host \(bundleID, privacy: .public): \(result.rawValue)")
                continue
            }

            let requested = [
                kAXWindowCreatedNotification,
                kAXLayoutChangedNotification,
                kAXFocusedWindowChangedNotification
            ]
            let registered = requested.filter { notification in
                AXObserverAddNotification(
                    observer,
                    application,
                    notification as CFString,
                    Unmanaged.passUnretained(signal).toOpaque()
                ) == .success
            }
            guard registered.contains(kAXWindowCreatedNotification)
                  || registered.contains(kAXLayoutChangedNotification)
            else {
                for notification in registered {
                    AXObserverRemoveNotification(observer, application, notification as CFString)
                }
                logger.error("AX banner events unavailable for host \(bundleID, privacy: .public)")
                continue
            }

            hosts.append(BluetoothNoticeAccessibilityHostSession(
                bundleID     : bundleID,
                observer     : observer,
                application  : application,
                notifications: registered
            ))
        }

        guard !hosts.isEmpty else {
            throw BluetoothNoticeAccessibilityError.unsupported("The system does not expose Bluetooth banner events.")
        }

        let newSession = BluetoothNoticeObservationSession(hosts: hosts, signal: signal)
        session = newSession

        // A real hint may arrive while asynchronous registration is pending.
        if !hints.isEmpty { signal.continuation.yield(()) }
        logger.info("Observing Bluetooth banner events on \(hosts.count) system hosts")

        return newSession
    }

    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        hints.removeAll()

        guard let session else { return }

        for host in session.hosts {
            for notification in host.notifications {
                AXObserverRemoveNotification(host.observer, host.application, notification as CFString)
            }
        }
        session.signal.cancel()
        self.session = nil
    }

    /// expectConnection also inspects once to handle a banner arriving just before the device callback.
    func expectConnection(deviceName: String) -> BluetoothNoticeSuppressionStatus? {
        guard !deviceName.isEmpty else { return nil }

        let now = Date()
        lastDiagnosticReason = nil
        hints.removeAll { $0.expiresAt <= now || $0.deviceName == deviceName }
        hints.append(BluetoothNoticeConnectionHint(
            deviceName: deviceName,
            expiresAt : now.addingTimeInterval(6)
        ))
        if hints.count > 8 { hints.removeFirst(hints.count - 8) }

        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            await self?.expireHints()
        }

        return inspectExpectedNotice()
    }

    private func expireHints() {
        hints.removeAll { $0.expiresAt <= Date() }
        expiryTask = nil
    }

    /// inspectExpectedNotice performs a bounded inspection only after a real connection or
    /// routing hint.
    /// Shared host windows are search roots only; they can never become a dismissal target.
    func inspectExpectedNotice() -> BluetoothNoticeSuppressionStatus? {
        hints.removeAll { $0.expiresAt <= Date() }
        guard !hints.isEmpty, let session, !session.signal.isCancelled else { return nil }
        guard AXIsProcessTrusted() else { return .permissionRequired }

        inspectionDeadline = Date().addingTimeInterval(0.35)
        var searchBudget             = 96
        var identifiedButUnsupported = false
        for host in session.hosts where Date() < inspectionDeadline {
            let windows = attribute(host.application, kAXWindowsAttribute) as? [AXUIElement] ?? []
            // Hosted SwiftUI content may be an application child instead of a separate AXWindow.
            let roots = windows.isEmpty
                ? (attribute(host.application, kAXChildrenAttribute) as? [AXUIElement] ?? [])
                : windows

            for root in roots.prefix(4) where Date() < inspectionDeadline {
                let search = systemBannerCandidates(
                    in           : root,
                    ownerBundleID: host.bundleID,
                    budget       : &searchBudget
                )
                identifiedButUnsupported = identifiedButUnsupported || search.unsupported

                for candidate in search.candidates {
                    if let result = dismissIfMatching(candidate, session: session) { return result }
                }

                if host.bundleID == "com.apple.controlcenter",
                   let candidate = legacySnapshot(window: root, deadline: inspectionDeadline),
                   let result = dismissIfMatching(candidate, session: session) {
                    return result
                }
            }
        }

        if identifiedButUnsupported {
            logDiagnostic("identified_subtree_not_safely_dismissible")
            return .unsupported("The system Bluetooth banner does not expose a safe dismiss action.")
        }

        logDiagnostic(searchBudget == 0 ? "inspection_budget_exhausted" : "no_matching_connection_subtree")
        return nil
    }

    private typealias Candidate = (snapshot: BluetoothNoticeSnapshot, closeButton: AXUIElement)

    private func dismissIfMatching(
        _ candidate: Candidate,
        session    : BluetoothNoticeObservationSession
    ) -> BluetoothNoticeSuppressionStatus? {
        guard let name = BluetoothNoticeMatchPolicy.matchingDevice(
            in             : candidate.snapshot,
            hints          : hints,
            connectedLabels: connectedLabels,
            now            : Date()
        ),
        !session.signal.isCancelled,
        Date() < inspectionDeadline
        else { return nil }

        let result = AXUIElementPerformAction(candidate.closeButton, kAXPressAction as CFString)
        guard result == .success else {
            logger.error("Matching Bluetooth banner rejected AXPress: \(result.rawValue)")
            return .failure("The matching Bluetooth banner could not be dismissed (\(result.rawValue)).")
        }

        hints.removeAll { $0.deviceName == name }
        logger.info("System Bluetooth banner accepted a selective dismiss action")

        // Action acceptance is not proof of disappearance or prevention of the first frame.
        return .observing
    }

    private func logDiagnostic(_ reason: String) {
        guard lastDiagnosticReason != reason else { return }

        lastDiagnosticReason = reason
        logger.debug("Bluetooth banner inspection: \(reason, privacy: .public)")
    }

    /// systemBannerCandidates searches only for Apple's exact banner identifier. Unknown ancestor
    /// content is never acted on.
    private func systemBannerCandidates(
        in root      : AXUIElement,
        ownerBundleID: String,
        budget       : inout Int
    ) -> (candidates: [Candidate], unsupported: Bool) {
        var pending     = [(root, false)]
        var candidates : [Candidate] = []
        var unsupported = false

        while let (element, ancestorModal) = pending.popLast() {
            guard budget > 0, Date() < inspectionDeadline else { break }

            budget -= 1
            let isModal = ancestorModal || (attribute(element, kAXModalAttribute) as? Bool) == true
            if string(element, kAXIdentifierAttribute) == "smart-routing-system-banner" {
                if let candidate = systemBannerSnapshot(
                    element,
                    ownerBundleID: ownerBundleID,
                    isModal      : isModal
                ) {
                    candidates.append(candidate)
                } else {
                    unsupported = true
                }
                continue
            }

            guard !isModal,
                  let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement]
            else { continue }

            // Do not traverse an unbounded settings/menu tree to hunt for matching text.
            guard children.count + pending.count <= budget else { continue }

            pending.append(contentsOf: children.map { ($0, isModal) })
        }

        return (candidates, unsupported)
    }

    /// systemBannerSnapshot classifies the entire identified subtree. A generic close control or
    /// extra button is rejected.
    private func systemBannerSnapshot(
        _ root       : AXUIElement,
        ownerBundleID: String,
        isModal      : Bool
    ) -> Candidate? {
        guard !isModal,
              let size = size(of: root),
              size.width > 0,
              size.width <= 600,
              size.height > 0,
              size.height <= 240
        else { return nil }

        var pending        = [root]
        var texts         : [String]      = []
        var dismissButtons: [AXUIElement] = []
        var visited        = 0

        while let element = pending.popLast() {
            guard visited < 40, Date() < inspectionDeadline else { return nil }

            visited += 1
            guard let role = string(element, kAXRoleAttribute),
                  (attribute(element, kAXModalAttribute) as? Bool) != true
            else { return nil }

            if role == kAXButtonRole {
                guard string(element, kAXIdentifierAttribute) == "com.apple.controlcenter.dismiss"
                else { return nil }

                dismissButtons.append(element)
            } else if role == kAXStaticTextRole {
                guard let text = string(element, kAXValueAttribute) ?? string(element, kAXTitleAttribute)
                else { return nil }

                texts.append(text)
            } else if ![kAXGroupRole, kAXWindowRole, kAXImageRole].contains(role) {
                return nil
            }
            if role == kAXImageRole, let title = string(element, kAXTitleAttribute), !title.isEmpty {
                texts.append(title)
            }
            guard Date() < inspectionDeadline else { return nil }

            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            if result == .success {
                guard let children = value as? [AXUIElement],
                      children.count + pending.count + visited <= 40
                else { return nil }

                pending.append(contentsOf: children)
            } else if result != .attributeUnsupported && result != .noValue {
                return nil
            }
        }

        guard dismissButtons.count == 1, let dismissButton = dismissButtons.first else { return nil }

        return (BluetoothNoticeSnapshot(
            ownerBundleID          : ownerBundleID,
            texts                  : texts,
            isModal                : false,
            hasInteractiveControls : false,
            closeButtonCount       : 1,
            isComplete             : true,
            isFloatingWindow       : false,
            width                  : size.width,
            height                 : size.height,
            bannerIdentifier       : "smart-routing-system-banner",
            dismissButtonIdentifier: "com.apple.controlcenter.dismiss"
        ), dismissButton)
    }

    private func size(of element: AXUIElement) -> CGSize? {
        guard let value = attribute(element, kAXSizeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) else { return nil }

        return size
    }

    /// legacySnapshot rejects any tree it cannot completely classify within its node and time budgets.
    private func legacySnapshot(
        window  : AXUIElement,
        deadline: Date
    ) -> (snapshot: BluetoothNoticeSnapshot, closeButton: AXUIElement)? {
        guard string(window, kAXIdentifierAttribute) != "smart-routing-system-banner",
              string(window, kAXSubroleAttribute) == kAXFloatingWindowSubrole,
              (attribute(window, kAXModalAttribute) as? Bool) == false,
              let rawSize = attribute(window, kAXSizeAttribute),
              CFGetTypeID(rawSize) == AXValueGetTypeID()
        else { return nil }

        var size = CGSize.zero
        // Core Foundation has no conditional cast for opaque AXValue handles. The type ID above
        // establishes the cast's contract before bridging the value returned by the system.
        let sizeValue = unsafeDowncast(rawSize, to: AXValue.self)
        guard AXValueGetValue(sizeValue, .cgSize, &size),
              size.width <= 600,
              size.height <= 240
        else { return nil }

        var pending      = [window]
        var texts       : [String]      = []
        var closeButtons: [AXUIElement] = []
        var visited      = 0

        while let element = pending.popLast() {
            guard visited < 40, Date() < deadline else { return nil }

            visited += 1
            guard let role = string(element, kAXRoleAttribute) else { return nil }

            if role == kAXButtonRole {
                guard string(element, kAXSubroleAttribute) == kAXCloseButtonSubrole else { return nil }
                closeButtons.append(element)
            } else if role == kAXStaticTextRole {
                guard let text = string(element, kAXValueAttribute) ?? string(element, kAXTitleAttribute)
                else { return nil }

                texts.append(text)
            } else if ![kAXWindowRole, kAXGroupRole, kAXImageRole].contains(role) {
                return nil
            }
            if role == kAXImageRole {
                if let title = string(element, kAXTitleAttribute), !title.isEmpty { texts.append(title) }
            }
            guard Date() < deadline else { return nil }

            var childrenValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
            if result == .success {
                guard let children = childrenValue as? [AXUIElement],
                      pending.count + children.count + visited <= 40
                else { return nil }

                pending.append(contentsOf: children)
            } else if result != .attributeUnsupported && result != .noValue {
                return nil
            }
        }

        guard closeButtons.count == 1, let closeButton = closeButtons.first else { return nil }

        return (BluetoothNoticeSnapshot(
            ownerBundleID         : "com.apple.controlcenter",
            texts                 : texts,
            isModal               : false,
            hasInteractiveControls: false,
            closeButtonCount      : closeButtons.count,
            isComplete            : true,
            isFloatingWindow      : true,
            width                 : size.width,
            height                : size.height
        ), closeButton)
    }

    private func attribute(
        _ element: AXUIElement,
        _ name   : String
    ) -> CFTypeRef? {
        guard Date() < inspectionDeadline else { return nil }

        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }

        return value
    }

    private func string(
        _ element: AXUIElement,
        _ name   : String
    ) -> String? {
        attribute(element, name) as? String
    }

    /// loadConnectionLabels reads exact strings from Apple's resources, without guessing translations.
    private func loadConnectionLabels() -> Set<String> {
        var labels   : Set<String> = []
        let resources = "/System/Library/CoreServices/ControlCenter.app/Contents/Resources/"

        for (table, key) in [("Sound", "HEADPHONES_CONNECTED"), ("Bluetooth", "HID_DEVICE_CONNECTED")] {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: resources + table + ".loctable")),
                  let dictionary = try? PropertyListSerialization.propertyList(
                      from  : data,
                      format: nil
                  ) as? [String: [String: Any]]
            else { continue }

            for translations in dictionary.values {
                if let label = translations[key] as? String { labels.insert(label) }
            }
        }

        return labels
    }
}
