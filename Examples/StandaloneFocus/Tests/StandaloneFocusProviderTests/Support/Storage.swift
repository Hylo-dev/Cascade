//
//  Storage.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneFocusProvider
import Testing

actor Storage: AddonStorageClient {

    enum Failure: Error {

        case lostReply
    }

    enum WriteMode {

        case normal
        case commitThenThrow
        case throwBeforeCommit
    }

    var data     : Data?
    var writes    = 0
    var reads     = 0
    var mode      = WriteMode.normal
    var failRead  = false
    var gateRead  = false
    var gateWrite = false
    var entered   = false
    var waiter   : CheckedContinuation<Void, Never>?

    func configure(
        _ mode: WriteMode = .normal,
        read  : Bool = false,
        write : Bool = false
    ) {
        self.mode = mode
        gateRead  = read
        gateWrite = write
        entered   = false
    }

    func setReadFailure(_ value: Bool) { failRead = value }

    func replace(_ data: Data?) { self.data = data }

    func snapshot() -> Data? { data }

    func counts() -> (Int, Int) { (reads, writes) }

    func read(key: String) async throws -> Data? {
        #expect(key == StandaloneFocusProvider.storageKey)

        reads += 1
        if failRead { throw Failure.lostReply }

        if gateRead {
            entered = true
            await withCheckedContinuation { waiter = $0 }
        }

        return data
    }

    func write(
        _ data: Data,
        key   : String
    ) async throws {
        #expect(key == StandaloneFocusProvider.storageKey)
        #expect(data.count <= 16_384)

        writes += 1
        if mode == .throwBeforeCommit {
            if gateWrite {
                entered = true
                await withCheckedContinuation { waiter = $0 }
            }
            throw Failure.lostReply
        }

        self.data = data
        if gateWrite {
            entered = true
            await withCheckedContinuation { waiter = $0 }
        }
        if mode == .commitThenThrow { throw Failure.lostReply }
    }

    func remove(key: String) async throws { Issue.record("Provider must not remove state") }

    func release() {
        gateRead  = false
        gateWrite = false
        waiter?.resume()
        waiter = nil
    }

    func waitForEntry() async throws {
        for _ in 0..<100_000 {
            if entered { return }
            await Task.yield()
        }

        throw FocusError.busy
    }
}
