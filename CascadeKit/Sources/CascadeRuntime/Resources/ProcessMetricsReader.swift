import Darwin
import Foundation

/// One read of an explicitly expected process incarnation. This reader performs
/// no discovery, rebinding, retries, scheduling, authentication, or process control.
/// Its future caller must invoke synchronous libproc work outside MainActor.
struct ProcessMetricsReader {
    private let readRaw: (Int32) -> RawProcessMetricRead
    private let absoluteTicks: () -> UInt64
    private let readTimebase: () -> RawProcessMetricTimebase

    init(
        readRaw: @escaping (Int32) -> RawProcessMetricRead,
        absoluteTicks: @escaping () -> UInt64,
        readTimebase: @escaping () -> RawProcessMetricTimebase
    ) {
        self.readRaw = readRaw
        self.absoluteTicks = absoluteTicks
        self.readTimebase = readTimebase
    }

    init() {
        self.init(
            readRaw: Self.readNative,
            absoluteTicks: mach_absolute_time,
            readTimebase: Self.nativeTimebase
        )
    }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        guard binding.isValid else { return .unavailable(.invalidExpectation) }
        let start = absoluteTicks()
        let raw = readRaw(binding.pid)
        let end = absoluteTicks()

        switch raw {
        case .failure(let capturedErrno):
            return .unavailable(.readFailed(capturedErrno))

        case .success(let record):
            guard record.birthAbsoluteTicks > 0,
                  record.executableUUID != ProcessMetricBinding.zeroUUID else {
                return .unavailable(.identityUnavailable)
            }
            // Fence using identity returned with these very counters, never a
            // separate PID-only identity query followed by an unfenced read.
            guard record.birthAbsoluteTicks == binding.birthAbsoluteTicks,
                  record.executableUUID == binding.executableUUID else {
                return .unavailable(.identityMismatch)
            }
            guard record.exitAbsoluteTicks == 0 else { return .unavailable(.exited) }
            let window = ProcessMetricWindow(startTicks: start, endTicks: end)
            guard window.isValid(for: binding) else { return .unavailable(.invalidAcquisition) }

            switch readTimebase() {
            case .failure(let code):
                return .unavailable(.timebaseFailed(code))
            case .success(let timebase):
                guard timebase.isValid else { return .unavailable(.invalidTimebase) }
                return .sample(ProcessMetricObservation(
                    binding: binding,
                    userTicks: record.userTicks,
                    systemTicks: record.systemTicks,
                    footprintBytes: record.footprintBytes,
                    window: window,
                    timebase: timebase
                ))
            }
        }
    }

    private static func readNative(_ pid: Int32) -> RawProcessMetricRead {
        var usage = rusage_info_v0()
        let (code, capturedErrno) = withUnsafeMutablePointer(to: &usage) { pointer in
            // The SDK imports the C buffer as rusage_info_t?. Rebind only for
            // the call while retaining the full v0 object's storage/alignment.
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { buffer in
                let code = proc_pid_rusage(pid, RUSAGE_INFO_V0, buffer)
                let capturedErrno = errno
                return (code, capturedErrno)
            }
        }
        // This API returns zero, not a PIDINFO-style byte count. Failed buffers
        // are ignored regardless of their initial or partially written contents.
        guard code == 0 else { return .failure(capturedErrno) }
        return .success(ProcessMetricRecord(
            birthAbsoluteTicks: usage.ri_proc_start_abstime,
            executableUUID: UUID(uuid: usage.ri_uuid),
            userTicks: usage.ri_user_time,
            systemTicks: usage.ri_system_time,
            footprintBytes: usage.ri_phys_footprint,
            exitAbsoluteTicks: usage.ri_proc_exit_abstime
        ))
    }

    private static func nativeTimebase() -> RawProcessMetricTimebase {
        var info = mach_timebase_info_data_t()
        let code = mach_timebase_info(&info)
        guard code == KERN_SUCCESS else { return .failure(code) }
        return .success(ProcessMetricTimebase(numer: info.numer, denom: info.denom))
    }
}
