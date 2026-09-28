import Foundation
import CryptoKit
import Darwin

// Caller must stop all writers and remove cache clones before invoking --stopped.
// This acknowledgement is not a detector of active VMs. Only laboratory files are accepted.
enum Failure: Error {
    case arguments, restrictedPath, regularUnlinkedFileRequired, filesystem, shortRead
    case openFile(Int32), punchHole(Int32), seekExtent(Int32), invalidExtent, sizeChanged, hashMismatch
}
func run() throws {
    let a = CommandLine.arguments
    guard a.count == 3, a[2] == "--stopped" else { throw Failure.arguments }
    let path = URL(fileURLWithPath: a[1]).resolvingSymlinksInPath().standardizedFileURL.path
    let lab = URL(fileURLWithPath: "/private/tmp/cascade-addon-vm").resolvingSymlinksInPath().standardizedFileURL.path
    guard path.hasPrefix(lab + "/"), path.hasSuffix(".img") else { throw Failure.restrictedPath }
    let fd = open(path, O_RDWR | O_NOFOLLOW)
    guard fd >= 0 else { throw Failure.openFile(errno) }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
    defer { try? file.close() }
    func inspect() throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw Failure.filesystem }
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_nlink == 1,
              value.st_size >= 0 else { throw Failure.regularUnlinkedFileRequired }
        return value
    }
    let before = try inspect(), size = UInt64(before.st_size), block = 4096
    var fs = statfs()
    guard fstatfs(fd, &fs) == 0, Int(fs.f_bsize) == block else { throw Failure.filesystem }
    func hash() throws -> String {
        try file.seek(toOffset: 0)
        var remaining = size, digest = SHA256()
        while remaining > 0 {
            try autoreleasepool {
                let count = Int(min(remaining, 1048576))
                guard let data = try file.read(upToCount: count), data.count == count else { throw Failure.shortRead }
                digest.update(data: data)
                remaining -= UInt64(data.count)
            }
        }
        guard try inspect().st_size == before.st_size else { throw Failure.sizeChanged }
        return "sha256:" + digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    let digestBefore = try hash(), zeroes = Data(count: block)
    let page = UInt64(block), limit = size / UInt64(block) * UInt64(block)
    var cursor: UInt64 = 0, zeroBlocks: UInt64 = 0, scannedPages: UInt64 = 0, skippedHoleBytes: UInt64 = 0
    while cursor < limit {
        let dataStart = lseek(fd, off_t(cursor), SEEK_DATA)
        if dataStart < 0 {
            guard errno == ENXIO else { throw Failure.seekExtent(errno) }
            skippedHoleBytes += limit - cursor
            break
        }
        guard UInt64(dataStart) >= cursor, UInt64(dataStart) <= size else { throw Failure.invalidExtent }
        let start = UInt64(dataStart) / page * page
        skippedHoleBytes += min(start, limit) - cursor
        if start >= limit { break }
        let holeStart = lseek(fd, dataStart, SEEK_HOLE)
        guard holeStart >= 0 else { throw Failure.seekExtent(errno) }
        guard holeStart > dataStart, UInt64(holeStart) <= size else { throw Failure.invalidExtent }
        let end = min(limit, (UInt64(holeStart) + page - 1) / page * page)
        try file.seek(toOffset: start)
        var offset = start
        while offset < end {
            try autoreleasepool {
                let count = Int(min(end - offset, 1048576))
                guard let data = try file.read(upToCount: count), data.count == count else { throw Failure.shortRead }
                for local in stride(from: 0, to: count, by: block) {
                    if data[local..<(local + block)] == zeroes {
                        var hole = fpunchhole_t(fp_flags: 0, reserved: 0, fp_offset: off_t(offset + UInt64(local)), fp_length: off_t(block))
                        guard fcntl(fd, F_PUNCHHOLE, &hole) == 0 else { throw Failure.punchHole(errno) }
                        zeroBlocks += 1
                    }
                    scannedPages += 1
                }
                offset += UInt64(count)
            }
        }
        cursor = end
    }
    try file.synchronize()
    let digestAfter = try hash(), after = try inspect()
    guard after.st_size == before.st_size else { throw Failure.sizeChanged }
    guard digestBefore == digestAfter else { throw Failure.hashMismatch }
    let result: [String: Any] = ["status": "verified", "sizeBytes": size, "zeroBlocks": zeroBlocks,
        "pageBytes": block, "scannedPages": scannedPages, "skippedHoleBytes": skippedHoleBytes,
        "punchedBytes": zeroBlocks * UInt64(block), "sha256Before": digestBefore, "sha256After": digestAfter,
        "allocatedBeforeBytes": UInt64(before.st_blocks) * 512, "allocatedAfterBytes": UInt64(after.st_blocks) * 512]
    print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
}
do { try run() }
catch { fputs("compact-zero-pages: \(error)\n", stderr); exit(1) }
