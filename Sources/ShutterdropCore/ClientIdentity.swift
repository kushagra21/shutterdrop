import Foundation

/// The PTP/IP GUID this Mac presents to the camera. The camera is paired to it
/// over USB once, so the app and sdprobe must share it and it must not change.
public enum ClientIdentity {
    public static let name = "Shutterdrop"

    public static var file: URL { file(inHome: FileManager.default.homeDirectoryForCurrentUser) }

    /// Where a given user keeps the ID (pairing runs as root but must use the user's ID).
    public static func file(inHome home: URL) -> URL {
        home.appending(path: "Library/Application Support/Shutterdrop/client-guid")
    }

    public static func hex(_ guid: [UInt8]) -> String {
        guid.map { String(format: "%02x", $0) }.joined()
    }

    public static func parseHex(_ text: String) -> [UInt8]? {
        let digits = Array(text.filter { $0 != ":" && $0 != "-" })
        guard digits.count == 32 else { return nil }
        let bytes = stride(from: 0, to: 32, by: 2).compactMap { UInt8(String(digits[$0..<$0 + 2]), radix: 16) }
        return bytes.count == 16 ? bytes : nil
    }

    public static func guid() throws -> [UInt8] {
        if let data = try? Data(contentsOf: file), data.count == 16 {
            return [UInt8](data)
        }
        let guid = withUnsafeBytes(of: UUID().uuid) { Array($0) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(guid).write(to: file)
        return guid
    }
}
