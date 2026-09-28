import Foundation
import Compression
import CryptoKit
import Darwin

enum Failure: Error {
    case arguments, sameFile, invalidRange, filesystem, outputLimit, shortOutput, hashMismatch
    case punchHole(Int32), shortRead
}
func run() throws {
    let a = CommandLine.arguments
    guard a.count == 6, let offset = UInt64(a[3]), let length = UInt64(a[4]) else { throw Failure.arguments }
    let wanted = (a[5].hasPrefix("sha256:") ? String(a[5].dropFirst(7)) : a[5]).lowercased()
    guard wanted.count == 64, wanted.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw Failure.arguments }
    let input = try FileHandle(forReadingFrom: URL(fileURLWithPath: a[1]))
    defer { try? input.close() }
    let output = try FileHandle(forUpdating: URL(fileURLWithPath: a[2]))
    defer { try? output.close() }
    var sourceStat = stat(), targetStat = stat(), fs = statfs()
    guard fstat(input.fileDescriptor, &sourceStat) == 0, fstat(output.fileDescriptor, &targetStat) == 0,
          fstatfs(output.fileDescriptor, &fs) == 0, fs.f_bsize > 0 else { throw Failure.filesystem }
    guard sourceStat.st_dev != targetStat.st_dev || sourceStat.st_ino != targetStat.st_ino else { throw Failure.sameFile }
    let size = try output.seekToEnd()
    guard offset <= size, length <= size - offset, length <= UInt64(Int64.max),
          offset <= UInt64(Int64.max) - length else { throw Failure.invalidRange }
    let block = UInt64(fs.f_bsize), bufferSize = 65536
    let zeroes = Data(count: bufferSize)
    var produced: UInt64 = 0, punched: UInt64 = 0
    func write(_ data: Data, at position: UInt64) throws {
        guard !data.isEmpty else { return }
        try output.seek(toOffset: position)
        try output.write(contentsOf: data)
    }
    let filter = try OutputFilter(.decompress, using: .lz4, bufferCapacity: bufferSize) { data in
        guard let data = data else { return }
        guard UInt64(data.count) <= length - produced else { throw Failure.outputLimit }
        let position = offset + produced
        if data.count <= zeroes.count && data == zeroes.prefix(data.count) {
            let leading = min(UInt64(data.count), (block - position % block) % block)
            let middle = (UInt64(data.count) - leading) / block * block
            try write(Data(data.prefix(Int(leading))), at: position)
            if middle > 0 {
                var hole = fpunchhole_t(fp_flags: 0, reserved: 0, fp_offset: off_t(position + leading), fp_length: off_t(middle))
                guard fcntl(output.fileDescriptor, F_PUNCHHOLE, &hole) == 0 else { throw Failure.punchHole(errno) }
                punched += middle
            }
            let trailingStart = Int(leading + middle)
            try write(Data(data.dropFirst(trailingStart)), at: position + UInt64(trailingStart))
        } else {
            try write(data, at: position)
        }
        produced += UInt64(data.count)
    }
    while try autoreleasepool(invoking: { () throws -> Bool in
        guard let data = try input.read(upToCount: bufferSize), !data.isEmpty else { return false }
        try filter.write(data)
        return true
    }) {}
    try filter.finalize()
    guard produced == length else { throw Failure.shortOutput }
    try output.synchronize()
    try output.seek(toOffset: offset)
    var remaining = length, digest = SHA256()
    while remaining > 0 {
        try autoreleasepool {
            guard let data = try output.read(upToCount: Int(min(remaining, 1048576))), !data.isEmpty else { throw Failure.shortRead }
            digest.update(data: data)
            remaining -= UInt64(data.count)
        }
    }
    let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
    guard actual == wanted else { throw Failure.hashMismatch }
    let result: [String: Any] = ["status": "verified", "offset": offset, "bytes": produced,
                                "sha256": "sha256:" + actual, "punchedBytes": punched]
    print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
}
do { try run() }
catch { fputs("tart-layer-unpack: \(error)\n", stderr); exit(1) }
