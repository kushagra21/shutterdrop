import Foundation
import os
import SSDP

public struct RemoteCameraError: Error, CustomStringConvertible {
    /// Camera Remote API error codes seen so far.
    public static let cameraNotReady = 40401
    public static let alreadyPolling = 40402

    public var code: Int
    public var message: String

    public var description: String { "camera API error \(code)\(message.isEmpty ? "" : ": \(message)")" }
}

public struct RemoteCameraEvent: Equatable, Sendable {
    public var cameraStatus: String?
    public var pictureURLs: [URL] = []
}

/// Sony's Camera Remote API (ScalarWebAPI), which the A7 III serves in
/// Ctrl w/ Smartphone mode: JSON-RPC over HTTP on the camera's own Wi-Fi network.
public struct RemoteCamera: Sendable {
    public static let defaultEndpoint = URL(string: "http://192.168.122.1:10000/sony")!
    /// For calls that should answer at once, so an unreachable camera fails fast.
    static let quickTimeout: TimeInterval = 5
    static let serviceType = "urn:schemas-sony-com:service:ScalarWebAPI:1"

    public let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = defaultEndpoint) {
        let configuration = URLSessionConfiguration.ephemeral
        // getEvent long-polls; the camera answers when something changes.
        configuration.timeoutIntervalForRequest = 40
        self.endpoint = endpoint
        session = URLSession(configuration: configuration)
    }

    /// Finds the camera's API endpoint via SSDP and its device description,
    /// falling back to the A7 III's fixed Wi-Fi Direct address.
    public static func discover(seconds: Double = 3) async -> RemoteCamera {
        let location = OSAllocatedUnfairLock<String?>(initialState: nil)
        _ = try? await SSDP.discover(seconds: seconds, searchTarget: serviceType) { message in
            guard message.headers.values.contains(where: { $0.contains("ScalarWebAPI") }),
                  let url = message.location else { return false }
            location.withLock { $0 = url }
            return true
        }
        guard let text = location.withLock({ $0 }), let url = URL(string: text),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let endpoint = actionListURL(inDeviceDescription: String(decoding: data, as: UTF8.self))
        else { return RemoteCamera() }
        return RemoteCamera(endpoint: endpoint)
    }

    public func availableAPIs() async throws -> [String] {
        let data = try await call("camera", "getAvailableApiList")
        let result = try Self.result(in: data)
        return (result.first as? [String]) ?? []
    }

    /// Current state, or with `longPoll` the next change.
    public func event(longPoll: Bool) async throws -> RemoteCameraEvent {
        let data = try await call("camera", "getEvent", params: longPoll ? "[true]" : "[false]", timeout: longPoll ? 40 : Self.quickTimeout)
        return Self.parseEvent(data)
    }

    /// Fires the shutter and returns the postview URL(s).
    public func takePicture() async throws -> [URL] {
        let result = try Self.result(in: try await call("camera", "actTakePicture", timeout: 30))
        return ((result.first as? [String]) ?? []).compactMap(URL.init(string:))
    }

    /// Downloads a postview to a temporary file.
    public func download(_ url: URL) async throws -> URL {
        let (temporary, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RemoteCameraError(code: http.statusCode, message: "HTTP \(http.statusCode) for \(url.lastPathComponent)")
        }
        return temporary
    }

    func call(
        _ service: String,
        _ method: String,
        params: String = "[]",
        version: String = "1.0",
        timeout: TimeInterval = quickTimeout
    ) async throws -> Data {
        var request = URLRequest(url: endpoint.appending(path: service), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"method":"\#(method)","params":\#(params),"id":1,"version":"\#(version)"}"#.utf8)
        let (data, _) = try await session.data(for: request)
        if let error = Self.error(in: data) { throw error }
        return data
    }

    // MARK: - Parsing

    static func error(in data: Data) -> RemoteCameraError? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [Any], let code = error.first as? Int
        else { return nil }
        return RemoteCameraError(code: code, message: error.dropFirst().first as? String ?? "")
    }

    static func result(in data: Data) throws -> [Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [Any]
        else { throw RemoteCameraError(code: -1, message: "unreadable response") }
        return result
    }

    /// getEvent returns a positional array whose slots are null, objects or
    /// arrays of objects; each object names itself with "type".
    static func parseEvent(_ data: Data) -> RemoteCameraEvent {
        var event = RemoteCameraEvent()
        func visit(_ value: Any) {
            if let array = value as? [Any] {
                array.forEach(visit)
            } else if let object = value as? [String: Any] {
                switch object["type"] as? String {
                case "cameraStatus":
                    event.cameraStatus = object["cameraStatus"] as? String
                case "takePicture":
                    event.pictureURLs += ((object["takePictureUrl"] as? [String]) ?? []).compactMap(URL.init(string:))
                default:
                    break
                }
            }
        }
        visit((try? result(in: data)) ?? [])
        return event
    }

    static func actionListURL(inDeviceDescription xml: String) -> URL? {
        // Every service on the A7 III shares one action list URL.
        let tag = "<av:X_ScalarWebAPI_ActionList_URL>"
        guard let start = xml.range(of: tag), let end = xml[start.upperBound...].firstIndex(of: "<") else { return nil }
        return URL(string: String(xml[start.upperBound..<end]).trimmingCharacters(in: .whitespaces))
    }
}
