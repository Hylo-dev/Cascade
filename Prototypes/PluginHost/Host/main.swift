//
//  main.swift
//  PluginHost
//

import CoreBluetooth
import Darwin
import Foundation

/// The host stands in for Cascade: it runs the commands it is launched with, in order, and
/// writes one JSON object per line to standard output, which `open --stdout` sends to a file.

func now() -> Double {
    Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9
}

func emit(
    _ event: String,
    _ fields: [String: Any] = [:]
) {
    var record     = fields
    record["event"] = event
    record["time"]  = now()

    let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

/// Incarnation is what the host records about one PluginHost process at handshake. A kill is
/// allowed only while the live process at that PID still matches all of it.
struct Incarnation {

    let pid        : pid_t
    let id         : String
    let startSecond: UInt64
    let startMicro : UInt64
    let path       : String
}

func processStart(_ pid: pid_t) -> (UInt64, UInt64)? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }

    return (info.pbi_start_tvsec, info.pbi_start_tvusec)
}

func processPath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }

    return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
}

/// guardedKill sends SIGKILL only to the incarnation it was given: a vanished PID, a PID whose
/// process started at another time, or one running another executable is refused.
func guardedKill(_ incarnation: Incarnation) -> (String, Int32) {
    guard let start = processStart(incarnation.pid) else { return ("refused-gone", errno) }
    guard start == (incarnation.startSecond, incarnation.startMicro) else { return ("refused-restarted", 0) }
    guard processPath(incarnation.pid) == incarnation.path else { return ("refused-foreign", 0) }

    return kill(incarnation.pid, SIGKILL) == 0 ? ("killed", 0) : ("failed", errno)
}

/// ExitWatch registers NOTE_EXIT on one PID at handshake, so the exit is never missed even
/// when it happens before anyone waits for it.
final class ExitWatch {

    private let queue: Int32

    init?(pid: pid_t) {
        queue = kqueue()

        var change = kevent(
            ident : UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags : UInt16(EV_ADD | EV_ONESHOT | EV_RECEIPT),
            fflags: UInt32(NOTE_EXIT) | UInt32(NOTE_EXITSTATUS),
            data  : 0,
            udata : nil
        )
        var receipt = kevent()
        let count   = kevent(queue, &change, 1, &receipt, 1, nil)
        guard queue >= 0, count == 1, receipt.flags & UInt16(EV_ERROR) != 0, receipt.data == 0 else {
            return nil
        }
    }

    deinit {
        close(queue)
    }

    /// wait returns the raw wait status, or nil when the process is still alive at the deadline.
    func wait(seconds: Double) -> Int32? {
        var event   = kevent()
        var timeout = timespec(tv_sec: Int(seconds), tv_nsec: Int((seconds - Double(Int(seconds))) * 1e9))
        guard kevent(queue, nil, 0, &event, 1, &timeout) == 1 else { return nil }

        return Int32(truncatingIfNeeded: event.data)
    }
}

let bundle      = Bundle.main.bundleIdentifier ?? ""
let serviceID   = bundle + ".Service"
let servicePath = Bundle.main.bundleURL
    .appendingPathComponent("Contents/XPCServices/PluginHostService.xpc/Contents/MacOS/PluginHostService")
    .resolvingSymlinksInPath().path

func makeConnection() -> NSXPCConnection {
    let made = NSXPCConnection(serviceName: serviceID)
    made.remoteObjectInterface = NSXPCInterface(with: SpikeService.self)
    made.setCodeSigningRequirement(SpikeIdentity.requirement(identifier: serviceID))
    made.interruptionHandler = { [weak made] in
        emit("interrupted", ["processIdentifier": made?.processIdentifier ?? -1])
    }
    made.invalidationHandler = {
        emit("invalidated")
    }
    made.resume()

    return made
}

func makeProxy(_ connection: NSXPCConnection) -> SpikeService {
    connection.remoteObjectProxyWithErrorHandler { error in
        emit("proxy-error", ["error": "\(error)"])
    } as! SpikeService
}

var connection = makeConnection()
var proxy      = makeProxy(connection)

var current: Incarnation?
var watch  : ExitWatch?

/// call runs one asynchronous request and waits for its reply on this thread, which stands in
/// for an engine-owned thread: the deadline is a semaphore timeout, never a sleep.
func call<Value>(
    timeout: Double,
    _ body : (@escaping (Value) -> Void) -> Void
) -> Value? {
    let done  = DispatchSemaphore(value: 0)
    let box   = NSLock()
    var value: Value?

    body { reply in
        box.withLock { value = reply }
        done.signal()
    }
    guard done.wait(timeout: .now() + timeout) == .success else { return nil }

    return box.withLock { value }
}

func describe(status: Int32) -> [String: Any] {
    let signal = status & 0x7f

    return signal == 0
        ? ["exitCode": Int((status >> 8) & 0xff)]
        : ["signal": Int(signal)]
}

func hello(timeout: Double = 5) {
    let started = now()
    guard let (pid, id) = call(timeout: timeout, { reply in proxy.hello { reply(($0, $1)) } }) else {
        emit("hello-timeout")
        return
    }
    guard let start = processStart(pid) else {
        emit("hello-gone", ["pid": pid])
        return
    }

    current = Incarnation(
        pid        : pid,
        id         : id,
        startSecond: start.0,
        startMicro : start.1,
        path       : processPath(pid) ?? ""
    )
    watch = ExitWatch(pid: pid)
    emit("hello", [
        "pid"              : pid,
        "incarnation"      : id,
        "processIdentifier": connection.processIdentifier,
        "pathMatches"      : processPath(pid) == servicePath,
        "watching"         : watch != nil,
        "replySeconds"     : now() - started,
    ])
}

func killCurrent() {
    guard let incarnation = current else {
        emit("kill-skipped")
        return
    }

    let started          = now()
    let (outcome, error) = guardedKill(incarnation)
    emit("kill", ["outcome": outcome, "errno": error, "pid": incarnation.pid])
    guard outcome == "killed", let watch else { return }

    if let status = watch.wait(seconds: 2) {
        emit("exit", describe(status: status).merging([
            "afterKillSeconds" : now() - started,
            "processIdentifier": connection.processIdentifier,
        ]) { first, _ in first })
    } else {
        emit("exit-timeout")
    }
}

func foreignChecks() {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments     = ["30"]
    try! child.run()

    let pid = child.processIdentifier
    guard let start = processStart(pid) else {
        emit("foreign-gone")
        return
    }

    let foreign = Incarnation(
        pid        : pid,
        id         : "foreign",
        startSecond: start.0,
        startMicro : start.1,
        path       : servicePath
    )
    let restarted = Incarnation(
        pid        : pid,
        id         : "restarted",
        startSecond: start.0,
        startMicro : start.1 &+ 1,
        path       : processPath(pid) ?? ""
    )
    emit("guard-foreign", ["outcome": guardedKill(foreign).0])
    emit("guard-restarted", ["outcome": guardedKill(restarted).0])
    emit("guard-child-alive", ["alive": child.isRunning])

    child.terminate()
    child.waitUntilExit()
}

func run(_ arguments: ArraySlice<String>) {
    var remaining = arguments

    while let command = remaining.popFirst() {
        switch command {
            case "hello":
                hello()

            case "hello-wait":
                hello(timeout: Double(remaining.popFirst() ?? "5") ?? 5)

            case "hang":
                let started = now()
                let replied = call(timeout: 0.25, { reply in proxy.hang { reply(()) } }) != nil
                emit(replied ? "hang-replied" : "deadline-missed", ["afterSeconds": now() - started])

            case "kill":
                killCurrent()

            case "kill-raw":
                if let incarnation = current {
                    emit("kill-raw", ["result": kill(incarnation.pid, SIGKILL), "pid": incarnation.pid])
                }

            case "reconnect":
                connection.invalidate()
                connection = makeConnection()
                proxy      = makeProxy(connection)
                emit("reconnected")

            case "kill-stale":
                emit("kill-stale", ["outcome": current.map { guardedKill($0).0 } ?? "none"])

            case "foreign":
                foreignChecks()

            case "exit":
                proxy.exitCooperatively()
                if let status = watch?.wait(seconds: 2) {
                    emit("exit", describe(status: status))
                } else {
                    emit("exit-timeout")
                }

            case "automation":
                let target = remaining.popFirst() ?? ""
                let ask    = remaining.popFirst() == "1"
                let status = call(timeout: 300, { reply in
                    proxy.automation(bundleIdentifier: target, ask: ask) { reply($0) }
                })
                emit("automation", ["target": target, "ask": ask, "status": status.map { Int($0) } ?? "timeout"])

            case "host-automation":
                let target = remaining.popFirst() ?? ""
                let ask    = remaining.popFirst() == "1"
                emit("host-automation", [
                    "target": target,
                    "ask"   : ask,
                    "status": Int(automationStatus(bundleIdentifier: target, ask: ask)),
                ])

            case "send":
                let target = remaining.popFirst() ?? ""
                let result = call(timeout: 30, { reply in proxy.send(bundleIdentifier: target) { reply(($0, $1)) } })
                emit("send", ["target": target, "status": result.map { Int($0.0) } ?? -1, "name": result?.1 ?? ""])

            case "host-send":
                let target         = remaining.popFirst() ?? ""
                let (status, name) = applicationName(bundleIdentifier: target)
                emit("host-send", ["target": target, "status": Int(status), "name": name])

            case "bluetooth":
                let request = remaining.popFirst() == "1"
                let status  = call(timeout: 300, { reply in proxy.bluetooth(request: request) { reply($0) } })
                emit("bluetooth", ["request": request, "authorization": status ?? -1])

            case "host-bluetooth":
                emit("host-bluetooth", ["authorization": CBManager.authorization.rawValue])

            case "pause":
                Thread.sleep(forTimeInterval: Double(remaining.popFirst() ?? "1") ?? 1)

            default:
                emit("unknown-command", ["command": command])
        }
    }
}

emit("host-ready", ["bundle": bundle, "pid": getpid()])
run(CommandLine.arguments.dropFirst())
emit("host-done")
exit(0)
