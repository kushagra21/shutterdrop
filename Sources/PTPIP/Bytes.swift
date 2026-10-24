import Foundation

/// Builds little-endian binary data, the byte order used by PTP and PTP/IP.
public struct ByteWriter: Sendable {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    public mutating func append(bytes other: [UInt8]) {
        bytes.append(contentsOf: other)
    }

    /// UTF-16LE text followed by a 0x0000 terminator (PTP/IP friendly names).
    public mutating func appendNullTerminatedUTF16(_ string: String) {
        for unit in string.utf16 { append(unit) }
        append(UInt16(0))
    }

    /// PTP string: UInt8 character count (including the terminator), then UTF-16LE.
    public mutating func appendPTPString(_ string: String) {
        let units = Array(string.utf16)
        guard !units.isEmpty else { return append(UInt8(0)) }
        append(UInt8(units.count + 1))
        for unit in units { append(unit) }
        append(UInt16(0))
    }

    /// PTP array: UInt32 element count, then the elements.
    public mutating func appendArray<T: FixedWidthInteger>(_ values: [T]) {
        append(UInt32(values.count))
        for value in values { append(value) }
    }
}

public enum ByteReaderError: Error, Equatable {
    case truncated(offset: Int, needed: Int)
}

/// Reads little-endian binary data produced by the camera.
public struct ByteReader: Sendable {
    public let bytes: [UInt8]
    public private(set) var offset = 0

    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public init(_ data: Data) { self.bytes = [UInt8](data) }

    public var remaining: Int { bytes.count - offset }

    public mutating func read<T: FixedWidthInteger>(_: T.Type = T.self) throws -> T {
        let size = MemoryLayout<T>.size
        try require(size)
        var value: T = 0
        for i in 0..<size { value |= T(bytes[offset + i]) << (8 * i) }
        offset += size
        return value
    }

    public mutating func readBytes(_ count: Int) throws -> [UInt8] {
        try require(count)
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    public mutating func readRest() -> [UInt8] {
        defer { offset = bytes.count }
        return Array(bytes[offset...])
    }

    public mutating func readNullTerminatedUTF16() throws -> String {
        var units: [UInt16] = []
        while true {
            let unit = try read(UInt16.self)
            if unit == 0 { break }
            units.append(unit)
        }
        return String(decoding: units, as: UTF16.self)
    }

    public mutating func readPTPString() throws -> String {
        let count = Int(try read(UInt8.self))
        var units: [UInt16] = []
        for _ in 0..<count { units.append(try read(UInt16.self)) }
        if units.last == 0 { units.removeLast() }
        return String(decoding: units, as: UTF16.self)
    }

    public mutating func readArray<T: FixedWidthInteger>(_: T.Type) throws -> [T] {
        let count = Int(try read(UInt32.self))
        try require(count * MemoryLayout<T>.size)
        return try (0..<count).map { _ in try read(T.self) }
    }

    private func require(_ count: Int) throws {
        guard count >= 0, remaining >= count else {
            throw ByteReaderError.truncated(offset: offset, needed: count)
        }
    }
}
