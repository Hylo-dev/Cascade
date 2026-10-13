//
//  AudioProcessRecord.swift
//  CascadeKit
//

/// AudioProcessRecord is what Core Audio tells us about one audio process: the HAL object that
/// represents it, its PID, and the identifying strings it reports. It is a plain value, read once
/// per discovery pass, so grouping them into apps is a pure function that needs no HAL access.
///
/// `isRunningOutput` is carried along rather than filtered at the source: the grouping does not
/// care, but the caller decides which processes are worth steering (a silent process has nothing
/// to mute).
public struct AudioProcessRecord: Equatable, Sendable {

    public let objectID        : UInt32
    public let pid             : Int32
    public let bundleID        : String?
    public let executablePath  : String?
    public let isRunningOutput : Bool

    public init(
        objectID        : UInt32,
        pid             : Int32,
        bundleID        : String?,
        executablePath  : String?,
        isRunningOutput : Bool
    ) {
        self.objectID        = objectID
        self.pid             = pid
        self.bundleID        = bundleID
        self.executablePath  = executablePath
        self.isRunningOutput = isRunningOutput
    }
}
