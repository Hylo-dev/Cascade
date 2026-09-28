//
//  VolumeCheckFailure.swift
//  Cascade
//

#if VOLUME_MONITOR_TESTS
import Foundation
import AppKit

enum VolumeCheckFailure: Error {
    case failed(String)
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message  : String
) throws {
    guard condition() else { throw VolumeCheckFailure.failed(message) }
}

#endif
