import Foundation
import os
import PTPIP
import SSDP

/// A file on the card that the library doesn't have yet.
public struct PendingFile: Equatable, Sendable {
    public var name: String
    /// Camera clock.
    public var captured: Date?
    public var size: UInt64
}

/// Copies full-size files off the camera in Send to Computer mode (PTP/IP),
/// skipping files the library already has.
public struct CardImporter: Sendable {
    public enum Update: Sendable {
        /// The camera didn't accept the connection yet; trying again.
        case retrying(attempt: Int)
        case connected(model: String)
        /// Reading the card: `done` of `total` files looked at.
        case reading(done: Int, total: Int)
        /// The card has been read; `new` is what will be copied if confirmed.
        case found(total: Int, new: [PendingFile])
        case saved(Photo, index: Int, count: Int)
    }

    public static let defaultFormats: Set<UInt16> = [0x3801, 0xB101]  // JPEG, Sony ARW
    static let association: UInt16 = 0x3001  // a folder
    static let connectPatience: Duration = .seconds(20)

    public let library: PhotoLibrary
    /// Object formats to copy; empty = every file.
    public let formats: Set<UInt16>
    /// Only copy files the camera dated at or after this (camera clock); nil = all.
    public let since: Date?

    public init(library: PhotoLibrary, formats: Set<UInt16> = defaultFormats, since: Date? = nil) {
        self.library = library
        self.formats = formats
        self.since = since
    }

    /// Waits for a camera in Send to Computer mode to announce itself
    /// (MtpNullService over SSDP) and returns its address.
    public static func waitForCamera(seconds: Double) async throws -> String? {
        let found = OSAllocatedUnfairLock<String?>(initialState: nil)
        try await SSDP.discover(seconds: seconds, searchTarget: "urn:microsoft-com:service:MtpNullService:1") { message in
            guard message.looksLikeSonyCamera,
                  message.headers.values.contains(where: { $0.contains("MtpNullService") }) else { return false }
            found.withLock { $0 = message.sender }
            return true
        }
        try Task.checkCancellation()
        return found.withLock { $0 }
    }

    /// Copies new files. `confirm` sees the list first and can decline (a dry
    /// run). Cancelling the task stops after the file in progress and still
    /// signs off with the camera.
    @discardableResult
    public func run(
        host: String,
        port: UInt16 = PTPIPClient.defaultPort,
        guid: [UInt8],
        name: String,
        confirm: @Sendable ([PendingFile]) async -> Bool = { _ in true },
        onUpdate: @Sendable (Update) -> Void
    ) async throws -> [Photo] {
        let client = PTPIPClient(host: host, port: port, guid: guid, name: name)
        // The camera announces itself over SSDP a moment before it opens 15740,
        // and its Wi-Fi may still be waking up; keep trying for a while.
        let deadline = ContinuousClock.now + Self.connectPatience
        var attempt = 1
        while true {
            do {
                _ = try await client.connect()
                break
            } catch {
                guard ContinuousClock.now < deadline else { throw error }
                attempt += 1
                onUpdate(.retrying(attempt: attempt))
                try await Task.sleep(for: .seconds(1))
            }
        }
        do {
            let photos = try await importAll(client, confirm: confirm, onUpdate: onUpdate)
            try? await client.closeSession()
            await client.disconnect()
            return photos
        } catch {
            await client.disconnect()
            throw error
        }
    }

    private func importAll(
        _ client: PTPIPClient,
        confirm: @Sendable ([PendingFile]) async -> Bool,
        onUpdate: @Sendable (Update) -> Void
    ) async throws -> [Photo] {
        let info = try await client.getDeviceInfo()
        try await client.openSession()
        onUpdate(.connected(model: info.model))

        // Sony's Send to Computer handshake (as libgphoto2 does it over PTP/IP):
        // the start message shows "Sending…" and stops the camera ending the
        // session after ~2 minutes; the finish message lets it wrap up.
        let sonyTransferControl = Set([PTPCode.Operation.sony9280, PTPCode.Operation.sony9281])
            .isSubset(of: info.operationsSupported)
        if sonyTransferControl {
            try await sonyTransfer(client, message: Self.sonyStartMessage)
        }
        let saved = try await copyNewFiles(client, confirm: confirm, onUpdate: onUpdate)
        if sonyTransferControl {
            try await sonyTransfer(client, message: Self.sonyFinishMessage)
        }
        return saved
    }

    /// 0x9280 payloads: four UInt32 values, plus two bytes in the start message.
    static let sonyStartMessage: [UInt8] = littleEndian([2, 2, 0, 0]) + [1, 1]
    static let sonyFinishMessage: [UInt8] = littleEndian([0, 5, 0, 0])

    private static func littleEndian(_ values: [UInt32]) -> [UInt8] {
        values.flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
    }

    private func sonyTransfer(_ client: PTPIPClient, message: [UInt8]) async throws {
        for (code, data) in [(PTPCode.Operation.sony9280, message), (PTPCode.Operation.sony9281, nil)] {
            let result = try await client.transaction(code, [4], sending: data)
            guard result.isOK else { throw PTPIPError.operationFailed(operation: code, response: result.response.code) }
        }
    }

    private func copyNewFiles(
        _ client: PTPIPClient,
        confirm: @Sendable ([PendingFile]) async -> Bool,
        onUpdate: @Sendable (Update) -> Void
    ) async throws -> [Photo] {
        var handles: [UInt32] = []
        for storage in try await client.getStorageIDs() {
            handles += try await client.getObjectHandles(storageID: storage)
        }
        onUpdate(.reading(done: 0, total: handles.count))

        var candidates: [(handle: UInt32, info: ObjectInfo, captured: Date?)] = []
        for (index, handle) in handles.enumerated() {
            let object = try await client.getObjectInfo(handle: handle)
            if (index + 1) % 10 == 0 || index + 1 == handles.count {
                onUpdate(.reading(done: index + 1, total: handles.count))
            }
            let wanted = formats.isEmpty ? object.format != Self.association : formats.contains(object.format)
            let captured = CameraTimestamp.fromPTP(object.captureDate)
            // With a cutoff, undated files are skipped too.
            let recent = since.map { cutoff in captured.map { $0 >= cutoff } ?? false } ?? true
            guard wanted, recent else { continue }
            candidates.append((handle, object, captured))
        }
        let pending = candidates.filter {
            !library.hasOriginal(named: $0.info.filename, size: $0.info.compressedSize, captured: $0.captured)
        }
        let files = pending.map { PendingFile(name: $0.info.filename, captured: $0.captured, size: UInt64($0.info.compressedSize)) }
        onUpdate(.found(total: candidates.count, new: files))
        guard !files.isEmpty, await confirm(files) else { return [] }

        var saved: [Photo] = []
        for (index, item) in pending.enumerated() where !Task.isCancelled {
            let bytes = try await client.getObject(handle: item.handle)
            let photo = try library.addOriginal(bytes, named: item.info.filename, captured: item.captured)
            saved.append(photo)
            onUpdate(.saved(photo, index: index + 1, count: pending.count))
        }
        return saved
    }
}
