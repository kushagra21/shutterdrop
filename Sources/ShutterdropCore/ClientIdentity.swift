import Foundation

/// The PTP/IP GUID this Mac presents to the camera. The camera is paired to it
/// over USB once, so the app and sdprobe must share it and it must not change.
public enum ClientIdentity {
    public static let name = "Shutterdrop"

    public static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Shutterdrop/client-guid")
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
