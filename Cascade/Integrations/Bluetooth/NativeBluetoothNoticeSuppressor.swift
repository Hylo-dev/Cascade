//
//  NativeBluetoothNoticeSuppressor.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// BluetoothNoticeSuppressionStatus distinguishes observation from verified prevention.
nonisolated enum BluetoothNoticeSuppressionStatus: Equatable, Sendable {
    case stopped
    case permissionRequired
    case observing
    case unsupported(String)
    case failure(String)
}

/// BluetoothNoticeSuppressing closes a matching native notice after presentation, if supported.
@MainActor
protocol BluetoothNoticeSuppressing: AnyObject {
    var status: BluetoothNoticeSuppressionStatus { get }
    func start()
    func stop()
    func expectConnection(deviceName: String)
}

/// Observes identified SystemBannerUI subtrees plus the legacy Control Center floating notice.
/// AX delivers an already-presented view: this is selective dismissal, not pre-presentation prevention.
/// No shared MenuBarAgent window or system notification preference is ever changed.
@Observable
@MainActor
final class AccessibilityBluetoothNoticeSuppressor: BluetoothNoticeSuppressing {
    private(set) var status: BluetoothNoticeSuppressionStatus = .stopped

    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var worker: BluetoothNoticeAccessibilityWorker?
    @ObservationIgnored private var session: BluetoothNoticeObservationSession?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var observedProcesses: [String: pid_t] = [:]
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var permissionToken: NSObjectProtocol?

    private var supportedHosts: [String] {
        if #available(macOS 27.0, *) { ["com.apple.controlcenter", "com.apple.MenuBarAgent"] }
        else { ["com.apple.controlcenter"] }
    }

    /// Reuses a healthy observer; host restarts and permission events recreate only the AX session.
    func start() {
        isEnabled = true
        installLifecycleObservers()
        guard AXIsProcessTrusted() else {
            resetSession()
            status = .permissionRequired
            return
        }
        var processes: [String: pid_t] = [:]
        for bundleID in supportedHosts {
            if let process = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                processes[bundleID] = process.processIdentifier
            }
        }
        guard !processes.isEmpty else {
            resetSession()
            status = .unsupported("The system Bluetooth banner host is not running.")
            return
        }
        if worker != nil, observationTask != nil, observedProcesses == processes { return }
        resetSession()
        let currentGeneration = generation
        let newWorker = BluetoothNoticeAccessibilityWorker()
        worker = newWorker
        observedProcesses = processes
        observationTask = Task { [weak self] in
            do {
                let newSession = try await newWorker.start(processes: processes)
                guard !Task.isCancelled, self?.generation == currentGeneration else {
                    await newWorker.stop()
                    return
                }
                self?.session = newSession
                self?.observedProcesses = processes
                for host in newSession.hosts {
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(host.observer), .commonModes)
                }
                self?.status = .observing
                for await _ in newSession.signal.events {
                    guard !Task.isCancelled else { break }
                    let result = await newWorker.inspectExpectedNotice()
                    guard self?.generation == currentGeneration else { break }
                    if let result { self?.status = result }
                }
            } catch let error as BluetoothNoticeAccessibilityError {
                guard let self, self.generation == currentGeneration else { return }
                self.resetSession()
                self.status = error.status
            } catch {
                guard let self, self.generation == currentGeneration else { return }
                self.resetSession()
                self.status = .failure(error.localizedDescription)
            }
        }
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        start()
    }

    func stop() {
        isEnabled = false
        resetSession()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        if let permissionToken { DistributedNotificationCenter.default().removeObserver(permissionToken) }
        permissionToken = nil
        status = .stopped
    }

    private func resetSession() {
        generation += 1
        observationTask?.cancel()
        observationTask = nil
        if let session {
            session.signal.cancel()
            for host in session.hosts {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(host.observer), .commonModes)
            }
        }
        session = nil
        observedProcesses.removeAll()
        if let worker { Task { await worker.stop() } }
        worker = nil
    }

    /// These observers are idle between real lifecycle events; no process or permission polling.
    private func installLifecycleObservers() {
        guard workspaceTokens.isEmpty else { return }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didDeactivateApplicationNotification] {
            workspaceTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                let isSettingsDeparture = name == NSWorkspace.didDeactivateApplicationNotification
                    && bundleID == "com.apple.systempreferences"
                let isBannerHost = name != NSWorkspace.didDeactivateApplicationNotification
                    && ["com.apple.controlcenter", "com.apple.MenuBarAgent"].contains(bundleID)
                guard isSettingsDeparture || isBannerHost else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.isEnabled else { return }
                    self.start()
                }
            })
        }
        permissionToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                    guard let self, self.isEnabled else { return }
                    self.start()
                }
        }
    }

    func expectConnection(deviceName: String) {
        guard let worker else { return }
        let currentGeneration = generation
        Task { [weak self] in
            let result = await worker.expectConnection(deviceName: deviceName)
            guard let self, self.generation == currentGeneration else { return }
            if let result { self.status = result }
        }
    }

    isolated deinit {
        observationTask?.cancel()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        if let permissionToken { DistributedNotificationCenter.default().removeObserver(permissionToken) }
        if let session {
            session.signal.cancel()
            for host in session.hosts {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(host.observer), .commonModes)
            }
        }
        if let worker { Task { await worker.stop() } }
    }
}

/// BluetoothNoticeAccessibilityError preserves the difference between absent AX support and failure.
nonisolated private enum BluetoothNoticeAccessibilityError: Error {
    case unsupported(String)
    case failure(Int32)

    var status: BluetoothNoticeSuppressionStatus {
        switch self {
        case .unsupported(let reason): .unsupported(reason)
        case .failure(let code): .failure("Accessibility error \(code).")
        }
    }
}

/// BluetoothNoticeObservationSignal bridges the C callback to one coalesced asynchronous event.
nonisolated private final class BluetoothNoticeObservationSignal: @unchecked Sendable {
    // Cancellation is the only mutable state crossing actors. The lock is never held during AX work.
    private let cancellationLock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        cancellationLock.withLock { cancelled }
    }

    func cancel() {
        cancellationLock.withLock { cancelled = true }
        continuation.finish()
    }

    let events       : AsyncStream<Void>
    let continuation : AsyncStream<Void>.Continuation

    init() {
        let stream = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = stream.stream
        continuation = stream.continuation
    }
}

/// Immutable host handles are messaged only by the worker; the main actor manages run-loop sources.
nonisolated private final class BluetoothNoticeAccessibilityHostSession: @unchecked Sendable {
    let bundleID: String
    let observer: AXObserver
    let application: AXUIElement
    let notifications: [String]

    init(bundleID: String, observer: AXObserver, application: AXUIElement, notifications: [String]) {
        self.bundleID = bundleID
        self.observer = observer
        self.application = application
        self.notifications = notifications
    }
}

/// The shared signal outlives every observer callback and is cancelled before unregistering hosts.
nonisolated private final class BluetoothNoticeObservationSession: @unchecked Sendable {
    let hosts: [BluetoothNoticeAccessibilityHostSession]
    let signal: BluetoothNoticeObservationSignal

    init(hosts: [BluetoothNoticeAccessibilityHostSession], signal: BluetoothNoticeObservationSignal) {
        self.hosts = hosts
        self.signal = signal
    }
}

/// BluetoothNoticeAccessibilityWorker bounds remote work and keeps it away from the UI thread.
private actor BluetoothNoticeAccessibilityWorker {
    private var session: BluetoothNoticeObservationSession?
    private var hints: [BluetoothNoticeConnectionHint] = []
    private var connectedLabels: Set<String> = []
    private var expiryTask: Task<Void, Never>?
    private var inspectionDeadline = Date.distantPast
    private var lastDiagnosticReason: String?

    private let logger = Logger(subsystem: "hylo.Cascade", category: "BluetoothNotice")

    /// The macOS 27 identifiers are verified in SystemBannerUI; live AX exposure remains OS-dependent.
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
            let requested = [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXFocusedWindowChangedNotification]
            let registered = requested.filter { notification in
                AXObserverAddNotification(observer, application, notification as CFString,
                    Unmanaged.passUnretained(signal).toOpaque()) == .success
            }
            guard registered.contains(kAXWindowCreatedNotification) || registered.contains(kAXLayoutChangedNotification) else {
                for notification in registered { AXObserverRemoveNotification(observer, application, notification as CFString) }
                logger.error("AX banner events unavailable for host \(bundleID, privacy: .public)")
                continue
            }
            hosts.append(BluetoothNoticeAccessibilityHostSession(
                bundleID: bundleID, observer: observer, application: application, notifications: registered
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
            deviceName : deviceName,
            expiresAt  : now.addingTimeInterval(6)
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

    /// Performs a bounded inspection only after a real connection or routing hint.
    /// Shared host windows are search roots only; they can never become a dismissal target.
    func inspectExpectedNotice() -> BluetoothNoticeSuppressionStatus? {
        hints.removeAll { $0.expiresAt <= Date() }
        guard !hints.isEmpty, let session, !session.signal.isCancelled else { return nil }
        guard AXIsProcessTrusted() else { return .permissionRequired }
        inspectionDeadline = Date().addingTimeInterval(0.35)
        var searchBudget = 96
        var identifiedButUnsupported = false
        for host in session.hosts where Date() < inspectionDeadline {
            let windows = attribute(host.application, kAXWindowsAttribute) as? [AXUIElement] ?? []
            // Hosted SwiftUI content may be an application child instead of a separate AXWindow.
            let roots = windows.isEmpty
                ? (attribute(host.application, kAXChildrenAttribute) as? [AXUIElement] ?? [])
                : windows
            for root in roots.prefix(4) where Date() < inspectionDeadline {
                let search = systemBannerCandidates(in: root, ownerBundleID: host.bundleID, budget: &searchBudget)
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
        session: BluetoothNoticeObservationSession
    ) -> BluetoothNoticeSuppressionStatus? {
        guard let name = BluetoothNoticeMatchPolicy.matchingDevice(
            in: candidate.snapshot, hints: hints, connectedLabels: connectedLabels, now: Date()
        ), !session.signal.isCancelled, Date() < inspectionDeadline else { return nil }
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

    /// Searches only for Apple's exact banner identifier. Unknown ancestor content is never acted on.
    private func systemBannerCandidates(
        in root: AXUIElement,
        ownerBundleID: String,
        budget: inout Int
    ) -> (candidates: [Candidate], unsupported: Bool) {
        var pending = [(root, false)]
        var candidates: [Candidate] = []
        var unsupported = false
        while let (element, ancestorModal) = pending.popLast() {
            guard budget > 0, Date() < inspectionDeadline else { break }
            budget -= 1
            let isModal = ancestorModal || (attribute(element, kAXModalAttribute) as? Bool) == true
            if string(element, kAXIdentifierAttribute) == "smart-routing-system-banner" {
                if let candidate = systemBannerSnapshot(element, ownerBundleID: ownerBundleID, isModal: isModal) {
                    candidates.append(candidate)
                } else { unsupported = true }
                continue
            }
            guard !isModal,
                  let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            // Do not traverse an unbounded settings/menu tree to hunt for matching text.
            guard children.count + pending.count <= budget else { continue }
            pending.append(contentsOf: children.map { ($0, isModal) })
        }
        return (candidates, unsupported)
    }

    /// Classifies the entire identified subtree. A generic close control or extra button is rejected.
    private func systemBannerSnapshot(
        _ root: AXUIElement,
        ownerBundleID: String,
        isModal: Bool
    ) -> Candidate? {
        guard !isModal, let size = size(of: root),
              size.width > 0, size.width <= 600, size.height > 0, size.height <= 240 else { return nil }
        var pending = [root]
        var texts: [String] = []
        var dismissButtons: [AXUIElement] = []
        var visited = 0
        while let element = pending.popLast() {
            guard visited < 40, Date() < inspectionDeadline else { return nil }
            visited += 1
            guard let role = string(element, kAXRoleAttribute),
                  (attribute(element, kAXModalAttribute) as? Bool) != true else { return nil }
            if role == kAXButtonRole {
                guard string(element, kAXIdentifierAttribute) == "com.apple.controlcenter.dismiss" else { return nil }
                dismissButtons.append(element)
            } else if role == kAXStaticTextRole {
                guard let text = string(element, kAXValueAttribute) ?? string(element, kAXTitleAttribute) else { return nil }
                texts.append(text)
            } else if ![kAXGroupRole, kAXWindowRole, kAXImageRole].contains(role) { return nil }
            if role == kAXImageRole, let title = string(element, kAXTitleAttribute), !title.isEmpty { texts.append(title) }
            guard Date() < inspectionDeadline else { return nil }
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            if result == .success {
                guard let children = value as? [AXUIElement], children.count + pending.count + visited <= 40 else { return nil }
                pending.append(contentsOf: children)
            } else if result != .attributeUnsupported && result != .noValue { return nil }
        }
        guard dismissButtons.count == 1, let dismissButton = dismissButtons.first else { return nil }
        return (BluetoothNoticeSnapshot(
            ownerBundleID: ownerBundleID, texts: texts, isModal: false, hasInteractiveControls: false,
            closeButtonCount: 1, isComplete: true, isFloatingWindow: false,
            width: size.width, height: size.height,
            bannerIdentifier: "smart-routing-system-banner", dismissButtonIdentifier: "com.apple.controlcenter.dismiss"
        ), dismissButton)
    }

    private func size(of element: AXUIElement) -> CGSize? {
        guard let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) else { return nil }
        return size
    }

    /// snapshot rejects any tree it cannot completely classify within its node and time budgets.
    private func legacySnapshot(
        window   : AXUIElement,
        deadline : Date
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
        guard AXValueGetValue(sizeValue, .cgSize, &size), size.width <= 600, size.height <= 240 else { return nil }
        var pending = [window]
        var texts: [String] = []
        var closeButtons: [AXUIElement] = []
        var visited = 0
        while let element = pending.popLast() {
            guard visited < 40, Date() < deadline else { return nil }
            visited += 1
            guard let role = string(element, kAXRoleAttribute) else { return nil }
            if role == kAXButtonRole {
                guard string(element, kAXSubroleAttribute) == kAXCloseButtonSubrole else { return nil }
                closeButtons.append(element)
            } else if role == kAXStaticTextRole {
                guard let text = string(element, kAXValueAttribute) ?? string(element, kAXTitleAttribute) else { return nil }
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
                guard let children = childrenValue as? [AXUIElement], pending.count + children.count + visited <= 40 else { return nil }
                pending.append(contentsOf: children)
            } else if result != .attributeUnsupported && result != .noValue {
                return nil
            }
        }
        guard closeButtons.count == 1, let closeButton = closeButtons.first else { return nil }
        return (BluetoothNoticeSnapshot(
            ownerBundleID          : "com.apple.controlcenter",
            texts                  : texts,
            isModal                : false,
            hasInteractiveControls : false,
            closeButtonCount       : closeButtons.count,
            isComplete             : true,
            isFloatingWindow       : true,
            width                  : size.width,
            height                 : size.height
        ), closeButton)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard Date() < inspectionDeadline else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    /// loadConnectionLabels reads exact strings from Apple's resources, without guessing translations.
    private func loadConnectionLabels() -> Set<String> {
        var labels: Set<String> = []
        let resources = "/System/Library/CoreServices/ControlCenter.app/Contents/Resources/"
        for (table, key) in [("Sound", "HEADPHONES_CONNECTED"), ("Bluetooth", "HID_DEVICE_CONNECTED")] {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: resources + table + ".loctable")),
                  let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]]
            else { continue }
            for translations in dictionary.values {
                if let label = translations[key] as? String { labels.insert(label) }
            }
        }
        return labels
    }
}
