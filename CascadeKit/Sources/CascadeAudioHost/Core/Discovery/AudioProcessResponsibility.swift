//
//  AudioProcessResponsibility.swift
//  CascadeKit
//

import Darwin

/// AudioProcessResponsibility answers "which executable is this process working for?".
///
/// Safari plays its audio through `com.apple.WebKit.GPU`, an XPC service whose executable lives
/// in a system cryptex with no `.app` in its path, so the path rule of `AudioProcessGrouping`
/// cannot name it. launchd, however, records who each process is *responsible* to (the app that
/// spawned the chain), and that is Safari. This is the only way to learn it.
///
/// The call is `responsibility_get_pid_responsible_for_pid` from libsystem: a private SPI with no
/// header. It is resolved dynamically, once, and not linked, so a macOS that drops or renames it
/// degrades to the old behaviour (the process keeps its own bundle ID) instead of crashing or
/// failing to load. The cost is one syscall pair per process per scan, and scans happen only on
/// HAL changes, never on a timer.
public enum AudioProcessResponsibility {

    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    /// The resolved SPI, or nil when this macOS does not export it. `static let` makes the lookup
    /// lazy, thread-safe and run exactly once.
    private static let responsiblePID: ResponsiblePIDFunction? = {
        guard
            let handle = dlopen(nil, RTLD_NOW),
            let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid")
        else { return nil }

        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    /// Returns the executable path of the process `pid` is responsible to, or nil when the SPI is
    /// missing, the answer is unusable (zero or negative), or the process is responsible for
    /// itself: that adds nothing, because the path rule already looked at its own executable.
    public static func responsibleExecutablePath(ofPID pid: Int32) -> String? {
        guard
            let responsiblePID,
            case let responsible = responsiblePID(pid),
            responsible > 0,
            responsible != pid
        else { return nil }

        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(responsible, &buffer, UInt32(buffer.count))

        return length > 0 ? String(cString: buffer) : nil
    }
}
