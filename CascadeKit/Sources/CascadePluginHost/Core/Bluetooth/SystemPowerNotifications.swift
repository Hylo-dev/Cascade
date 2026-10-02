//
//  SystemPowerNotifications.swift
//  CascadeKit
//

import Foundation
import IOKit
import IOKit.pwr_mgt

/// SystemPowerNotifications tells the Bluetooth source when the Mac is about to sleep and when it
/// has woken, from IOKit's root power domain, so PluginHost needs no AppKit for it. Its port
/// delivers to the queue it is given, so nothing runs between transitions and no run loop is
/// involved. macOS waits for every registered client to allow sleep, so the callback allows it
/// at once: it only reports the transition, it never holds the Mac awake.
///
/// It is created, used and stopped on that one queue, which is what makes the type safe to
/// share. The registration holds an unretained pointer to the instance, so the instance must be
/// stopped before it goes away, which `deinit` does as a last resort.
final class SystemPowerNotifications: @unchecked Sendable {

    enum Transition: Sendable {

        case willSleep
        case didWake
    }

    // IOMessage.h builds these with iokit_common_msg, a macro Swift cannot import:
    // sys_iokit (0xE0000000) | sub_iokit_common (0) | the message code.
    private static let canSystemSleep    : UInt32 = 0xE000_0270
    private static let systemWillSleep   : UInt32 = 0xE000_0280
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300

    private let handler: @Sendable (Transition) -> Void

    private var rootPort: io_connect_t = 0
    private var port    : IONotificationPortRef?
    private var notifier: io_object_t = 0

    /// init registers for the root domain's power messages, or fails when IOKit refuses.
    init?(
        queue  : DispatchQueue,
        handler: @escaping @Sendable (Transition) -> Void
    ) {
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
            stop()
            return nil
        }

        IONotificationPortSetDispatchQueue(port, queue)
    }

    func stop() {
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

    deinit {
        stop()
    }

    private func receive(
        _ message: UInt32,
        argument : UnsafeMutableRawPointer?
    ) {
        switch message {
            case Self.canSystemSleep:
                IOAllowPowerChange(rootPort, Int(bitPattern: argument))

            case Self.systemWillSleep:
                handler(.willSleep)
                IOAllowPowerChange(rootPort, Int(bitPattern: argument))

            case Self.systemHasPoweredOn:
                handler(.didWake)

            default:
                break
        }
    }
}
