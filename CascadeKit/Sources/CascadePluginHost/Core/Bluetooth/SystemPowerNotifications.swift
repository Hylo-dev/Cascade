//
//  SystemPowerNotifications.swift
//  CascadeKit
//

import Foundation
import IOKit
import IOKit.pwr_mgt

/// SystemPowerNotifications tells the Bluetooth source when the Mac is about to sleep and when it
/// has woken, from IOKit's root power domain, so PluginHost needs no AppKit for it. Its port
/// delivers to a queue of its own, so nothing runs between transitions and no run loop is
/// involved. macOS waits for every registered client to allow sleep, so a message is allowed
/// before anything else happens and the transition is only then handed on: however busy the
/// Bluetooth source is, it never holds the Mac awake.
///
/// Its registration is read and written only on its own queue, which the port delivers to and
/// `stop` reaches with `queue.sync`, which is what makes the type safe to share. The registration
/// holds an unretained pointer to the instance, so the instance must be stopped before it goes
/// away, which `deinit` does as a last resort.
final class SystemPowerNotifications: @unchecked Sendable {

    enum Transition: Sendable {

        case willSleep
        case didWake
    }

    /// Response is what one power message asks for: whether to allow the change, at once, and
    /// which transition, if any, to report afterwards.
    struct Response: Equatable, Sendable {

        let allowsChange: Bool
        let transition  : Transition?
    }

    // IOMessage.h builds these with iokit_common_msg, a macro Swift cannot import:
    // sys_iokit (0xE0000000) | sub_iokit_common (0) | the message code.
    private static let canSystemSleep    : UInt32 = 0xE000_0270
    private static let systemWillSleep   : UInt32 = 0xE000_0280
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300

    private let queue  = DispatchQueue(label: "cascade.plugin-host.system-power", qos: .userInitiated)
    private let handler: @Sendable (Transition) -> Void

    private var rootPort: io_connect_t = 0
    private var port    : IONotificationPortRef?
    private var notifier: io_object_t = 0

    /// init registers for the root domain's power messages, or fails when IOKit refuses. The
    /// handler runs on this instance's queue and should hand the transition on, not do the work.
    init?(handler: @escaping @Sendable (Transition) -> Void) {
        self.handler = handler

        rootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &port,
            { context, _, message, argument in
                guard let context else { return }

                Unmanaged<SystemPowerNotifications>.fromOpaque(context)
                    .takeUnretainedValue()
                    .receive(message, argument: argument)
            },
            &notifier
        )
        guard rootPort != 0, let port else {
            unregister()
            return nil
        }

        IONotificationPortSetDispatchQueue(port, queue)
    }

    /// stop ends the registration; call it from any queue but this instance's own.
    func stop() {
        queue.sync {
            unregister()
        }
    }

    deinit {
        unregister()
    }

    /// response maps one of the root domain's messages to what it asks for.
    static func response(to message: UInt32) -> Response {
        switch message {
            case canSystemSleep    : Response(allowsChange: true, transition: nil)
            case systemWillSleep   : Response(allowsChange: true, transition: .willSleep)
            case systemHasPoweredOn: Response(allowsChange: false, transition: .didWake)
            default                : Response(allowsChange: false, transition: nil)
        }
    }

    private func receive(
        _ message: UInt32,
        argument : UnsafeMutableRawPointer?
    ) {
        let response = Self.response(to: message)
        if response.allowsChange {
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        }
        if let transition = response.transition {
            handler(transition)
        }
    }

    private func unregister() {
        if notifier != 0 {
            IODeregisterForSystemPower(&notifier)
            notifier = 0
        }
        if rootPort != 0 {
            IOServiceClose(rootPort)
            rootPort = 0
        }
        if let port {
            IONotificationPortDestroy(port)
            self.port = nil
        }
    }
}
