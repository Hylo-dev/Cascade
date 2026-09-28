import Foundation
import Compression
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
var data = Data(count: 8 * 1024 * 1024 + 123)
for i in 0..<8192 { data[65536 + i] = UInt8((i * 37 + 11) % 251 + 1) }
for i in 0..<16384 { data[3 * 1024 * 1024 + 17 + i] = UInt8((i * 19 + 3) % 251 + 1) }
data[data.count - 1] = 239
try data.write(to: dir.appendingPathComponent("expected.bin"))
try (data as NSData).compressed(using: .lz4).write(to: dir.appendingPathComponent("nsdata.lz4"))
var stream = Data()
let filter = try OutputFilter(.compress, using: .lz4, bufferCapacity: 65536) {
    if let bytes = $0 { stream.append(bytes) }
}
for offset in stride(from: 0, to: data.count, by: 7777) {
    try filter.write(data[offset..<min(offset + 7777, data.count)])
}
try filter.finalize()
try stream.write(to: dir.appendingPathComponent("outputfilter.lz4"))
