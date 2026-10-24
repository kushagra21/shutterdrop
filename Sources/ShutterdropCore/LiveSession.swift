import Foundation

/// Watches a camera in Ctrl w/ Smartphone mode and saves the preview of every
/// shot, whether taken with the camera's shutter button or by `takePicture`.
public struct LiveSession: Sendable {
    public enum Update: Sendable {
        case connected(apis: [String])
        case status(String)
        case saved(Photo)
        case problem(String)
    }

    /// Consecutive failed polls before giving up (camera off, Wi-Fi dropped).
    static let maxFailures = 5

    public let camera: RemoteCamera
    public let library: PhotoLibrary

    public init(camera: RemoteCamera, library: PhotoLibrary) {
        self.camera = camera
        self.library = library
    }

    /// Runs until cancelled or the camera stops answering.
    public func run(onUpdate: @Sendable (Update) -> Void) async throws {
        let apis = try await camera.availableAPIs()
        guard apis.contains("getEvent") else {
            throw RemoteCameraError(code: -1, message: "camera does not offer getEvent")
        }
        onUpdate(.connected(apis: apis))

        // Pictures already reported before we connected are not new shots.
        var seen = Set(try await camera.event(longPoll: false).pictureURLs)
        var lastStatus: String?
        var failures = 0

        while !Task.isCancelled {
            let event: RemoteCameraEvent
            do {
                event = try await camera.event(longPoll: true)
                failures = 0
            } catch let error as URLError where error.code == .timedOut {
                continue
            } catch let error as RemoteCameraError where error.code == RemoteCameraError.alreadyPolling {
                try await Task.sleep(for: .milliseconds(500))
                continue
            } catch {
                failures += 1
                if failures >= Self.maxFailures { throw error }
                onUpdate(.problem("\(error)"))
                try await Task.sleep(for: .seconds(1))
                continue
            }

            if let status = event.cameraStatus, status != lastStatus {
                lastStatus = status
                onUpdate(.status(status))
            }
            for url in event.pictureURLs where seen.insert(url).inserted {
                do {
                    let temporary = try await camera.download(url)
                    onUpdate(.saved(try library.addPreview(from: temporary, named: url.lastPathComponent)))
                } catch {
                    onUpdate(.problem("could not save \(url.lastPathComponent): \(error)"))
                }
            }
        }
    }
}
