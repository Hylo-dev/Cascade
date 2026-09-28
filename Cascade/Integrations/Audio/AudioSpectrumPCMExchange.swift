//
//  AudioSpectrumPCMExchange.swift
//  Cascade
//

import Accelerate
import CoreAudio
import AudioToolbox
import Dispatch
import os
import Synchronization

/// AudioSpectrumPCMExchange transfers bounded PCM snapshots from HAL to one analysis worker.
///
/// HAL alone owns the rolling window and its cursors. Three preallocated slots have explicit
/// empty/writing/ready/reading ownership; the worker never reads a slot HAL can modify.
/// Swift's native atomics require macOS 15. The 14.2 fallback uses only a nonblocking try-lock
/// around the ownership word, dropping a snapshot on contention. Neither path waits for the worker.
nonisolated final class AudioSpectrumPCMExchange: @unchecked Sendable {
    private let slots       = [SpectrumPCMSlot(), SpectrumPCMSlot(), SpectrumPCMSlot()]
    private let left        = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    private let right       = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    private let publishStep : Int
    private let signal      : any DispatchSourceUserDataAdd
    private var cursor      = 0
    private var received    = 0
    private var sincePublish = 0
    private var sequence    : UInt64 = 0

    init(sampleRate: Double, signal: any DispatchSourceUserDataAdd) {
        publishStep = max(1, Int(ceil(sampleRate / 30)))
        self.signal = signal
        left.initialize(repeating: 0, count: 2_048)
        right.initialize(repeating: 0, count: 2_048)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    /// receive copies at most 8,192 stereo frames; HAL retains the supplied buffers only for this call.
    /// All destination storage already exists. No tasks, arrays, FFTs, or stream yields run in HAL.
    func receive(_ data: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
        guard let first = buffers.first, let firstData = first.mData,
              (1...2).contains(first.mNumberChannels), buffers.count <= 2 else { return }
        let firstChannels = Int(first.mNumberChannels)
        let firstSamples = firstData.assumingMemoryBound(to: Float.self)
        var secondSamples: UnsafePointer<Float>?
        var frameCount = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * firstChannels)
        if buffers.count == 2 {
            let second = buffers[1]
            guard firstChannels == 1, second.mNumberChannels == 1, let secondData = second.mData else { return }
            secondSamples = UnsafePointer(secondData.assumingMemoryBound(to: Float.self))
            frameCount = min(frameCount, Int(second.mDataByteSize) / MemoryLayout<Float>.size)
        }
        guard frameCount > 0 else { return }

        // An unusual device buffer must not turn the audio callback into unbounded work.
        // Retain the most recent part; any skipped prefix is simply absent from the visualizer.
        // The ring is written in at most two contiguous runs per call, each a single copy
        // or de-interleave: a per-sample Swift loop on this real-time thread cost ~0.9 % of a
        // core in a debug build.
        let firstFrame = max(0, frameCount - 8_192)
        var written = 0
        while written < frameCount - firstFrame {
            let run = min(frameCount - firstFrame - written, 2_048 - cursor)
            let frame = firstFrame + written
            if let secondSamples {
                (left + cursor).update(from: firstSamples + frame, count: run)
                (right + cursor).update(from: secondSamples + frame, count: run)
            } else if firstChannels == 2 {
                var split = DSPSplitComplex(realp: left + cursor, imagp: right + cursor)
                UnsafeRawPointer(firstSamples + frame * 2)
                    .withMemoryRebound(to: DSPComplex.self, capacity: run) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(run))
                    }
            } else {
                (left + cursor).update(from: firstSamples + frame, count: run)
                (right + cursor).update(from: firstSamples + frame, count: run)
            }
            cursor = (cursor + run) & 2_047
            written += run
        }
        received = min(2_048, received + written)
        sincePublish += frameCount
        guard received == 2_048, sincePublish >= publishStep else { return }
        sincePublish = 0
        for slot in slots {
            guard slot.transition(from: 0, to: 1) else { continue }
            // Oldest sample first: the run from the cursor to the end, then the start.
            let tail = 2_048 - cursor
            slot.left.update(from: left + cursor, count: tail)
            slot.right.update(from: right + cursor, count: tail)
            (slot.left + tail).update(from: left, count: cursor)
            (slot.right + tail).update(from: right, count: cursor)
            sequence &+= 1
            slot.sequence = sequence
            slot.release(as: 2)
            signal.add(data: 1)
            return
        }
    }

    /// copyLatest drains at most three slots into caller-owned worker scratch buffers.
    /// Snapshot order is independent of slot index, so an older ready slot cannot overwrite a newer one.
    func copyLatest(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) -> Bool {
        var newest: UInt64 = 0
        for slot in slots {
            guard slot.transition(from: 2, to: 3) else { continue }
            if slot.sequence > newest {
                left.update(from: slot.left, count: 2_048)
                right.update(from: slot.right, count: 2_048)
                newest = slot.sequence
            }
            slot.release(as: 0)
        }
        return newest != 0
    }
}

/// SpectrumPCMSlot owns one immutable snapshot while its state is ready or reading.
private nonisolated final class SpectrumPCMSlot: @unchecked Sendable {
    let left  = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    let right = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    var sequence: UInt64 = 0

    private let atomic: AnyObject?
    private let fallbackLock: os_unfair_lock_t
    private var fallbackState = 0

    init() {
        if #available(macOS 15, *) {
            atomic = SpectrumAtomicSlotState()
        } else {
            atomic = nil
        }
        fallbackLock = .allocate(capacity: 1)
        fallbackLock.initialize(to: os_unfair_lock())
        left.initialize(repeating: 0, count: 2_048)
        right.initialize(repeating: 0, count: 2_048)
    }

    deinit {
        left.deallocate()
        right.deallocate()
        fallbackLock.deallocate()
    }

    func transition(from expected: Int, to desired: Int) -> Bool {
        if #available(macOS 15, *), let atomic = atomic as? SpectrumAtomicSlotState {
            return atomic.value.compareExchange(
                expected: expected,
                desired: desired,
                ordering: .acquiringAndReleasing
            ).exchanged
        }
        guard os_unfair_lock_trylock(fallbackLock) else { return false }
        // The legacy lock remains held while the caller owns this slot. A release is therefore
        // an unlock, never a second acquisition that could block the real-time thread.
        guard fallbackState == expected else {
            os_unfair_lock_unlock(fallbackLock)
            return false
        }
        fallbackState = desired
        return true
    }

    func release(as state: Int) {
        if #available(macOS 15, *), let atomic = atomic as? SpectrumAtomicSlotState {
            atomic.value.store(state, ordering: .releasing)
            return
        }
        fallbackState = state
        os_unfair_lock_unlock(fallbackLock)
    }
}

/// SpectrumAtomicSlotState keeps atomic storage behind its platform availability boundary.
@available(macOS 15, *)
private nonisolated final class SpectrumAtomicSlotState: Sendable {
    let value = Atomic<Int>(0)
}
