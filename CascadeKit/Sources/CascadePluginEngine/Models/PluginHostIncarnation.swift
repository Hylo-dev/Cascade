//
//  PluginHostIncarnation.swift
//  CascadeKit
//

import Darwin
import Foundation

/// PluginHostIncarnation is one PluginHost process as the kernel recorded it at handshake: its
/// PID, checked against the connection's peer, the moment it started and its executable. The
/// kernel never signals a PID read at kill time, which reads 0 after an exit and another
/// process's after a relaunch; it signals only while the live process at the recorded PID still
/// matches all three, as spike S1 verified.
public struct PluginHostIncarnation: Equatable, Sendable {

    let pid              : pid_t
    let startSeconds     : UInt64
    let startMicroseconds: UInt64
    let path             : String

    init(
        pid              : pid_t,
        startSeconds     : UInt64,
        startMicroseconds: UInt64,
        path             : String
    ) {
        self.pid               = pid
        self.startSeconds      = startSeconds
        self.startMicroseconds = startMicroseconds
        self.path              = path
    }

    /// init(pid:) records the live process at `pid`, or fails when there is none.
    init?(pid: pid_t) {
        guard pid > 0, let start = Self.start(of: pid), let path = Self.path(of: pid) else { return nil }

        self.init(pid: pid, startSeconds: start.seconds, startMicroseconds: start.microseconds, path: path)
    }

    /// isLive says whether the process at the recorded PID is still this incarnation.
    var isLive: Bool {
        guard let start = Self.start(of: pid) else { return false }

        return start.seconds == startSeconds
            && start.microseconds == startMicroseconds
            && Self.path(of: pid) == path
    }

    /// kill sends SIGKILL to this incarnation and returns true, or refuses when the PID is gone
    /// or now names another process.
    func kill() -> Bool {
        isLive && Darwin.kill(pid, SIGKILL) == 0
    }

    private static func start(of pid: pid_t) -> (seconds: UInt64, microseconds: UInt64)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }

        return (info.pbi_start_tvsec, info.pbi_start_tvusec)
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }

        return URL(fileURLWithPath: String(decoding: buffer.prefix(Int(length)), as: UTF8.self)).resolvingSymlinksInPath().path
    }
}
