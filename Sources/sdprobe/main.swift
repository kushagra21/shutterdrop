import Foundation
import os
import PTPIP
import SSDP

// sdprobe: step 1 of Shutterdrop. Finds the camera on the LAN, completes the
// PTP/IP handshake and logs every event while you take photos.

let usage = """
    usage:
      sdprobe discover [--seconds N]
          Search the LAN with SSDP and log every reply and announcement (default 10 s).
      sdprobe connect <camera-ip> [--port N] [--name NAME] [--sony-sdio]
          Connect over PTP/IP, print device info, open a session and log events
          until Ctrl-C.
          --port N      PTP/IP port (default 15740)
          --name NAME   Name the camera sees for this Mac (default "Shutterdrop")
          --sony-sdio   After opening the session, run Sony's SDIO connect sequence
                        (used by PC Remote over USB; may or may not apply over Wi-Fi)
    """

setvbuf(stdout, nil, _IOLBF, 0)

let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

@MainActor func log(_ message: String) {
    print("\(timeFormatter.string(from: Date())) \(message)")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sdprobe: \(message)\n".utf8))
    exit(1)
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined()
}

func params(_ values: [UInt32]) -> String {
    values.isEmpty ? "" : " [" + values.map(PTPCode.hex).joined(separator: ", ") + "]"
}

/// A stable GUID for this Mac, so the camera sees the same initiator every time.
func loadOrCreateGUID() throws -> [UInt8] {
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Shutterdrop")
    let file = folder.appending(path: "client-guid")
    if let data = try? Data(contentsOf: file), data.count == 16 {
        return [UInt8](data)
    }
    let uuid = UUID().uuid
    let guid = withUnsafeBytes(of: uuid) { Array($0) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(guid).write(to: file)
    return guid
}

// MARK: - discover

@MainActor func runDiscover(seconds: Double) async throws {
    log("Searching for \(Int(seconds)) s. Turn on the camera's Wi-Fi function (PC Remote or Send to Computer) now.")
    // Sender → (SERVER header, mark), for the summary. ★ camera-like, · other Sony device.
    let devices = OSAllocatedUnfairLock(initialState: [String: (server: String, mark: String)]())
    let markStrength = [" ", "·", "★"]
    let listened = try await SSDP.discover(seconds: seconds) { message in
        let mark = message.looksLikeSonyCamera ? "★" : message.mentionsSony ? "·" : " "
        var line = "\(mark) \(message.sender)  \(message.startLine)"
        for key in ["SERVER", "ST", "NT", "USN", "LOCATION"] {
            if let value = message.headers[key] { line += "\n      \(key): \(value)" }
        }
        print(line)
        devices.withLock { seen in
            let previous = seen[message.sender]
            seen[message.sender] = (
                server: message.headers["SERVER"] ?? previous?.server ?? "",
                mark: [previous?.mark ?? " ", mark].max { markStrength.firstIndex(of: $0)! < markStrength.firstIndex(of: $1)! }!
            )
        }
    }
    if !listened {
        log("Note: port 1900 is in use by another app, so only replies to our search were seen, not announcements.")
    }
    let summary = devices.withLock { $0 }.sorted { $0.key < $1.key }
    log("Done. \(summary.count) device(s) answered:")
    for (address, device) in summary {
        print("  \(device.mark) \(address)  \(device.server)")
    }
    log("★ = looks like a Sony camera, · = other Sony device (e.g. a Bravia TV). Next: sdprobe connect <camera address>")
}

// MARK: - connect

@MainActor func runConnect(host: String, port: UInt16, name: String, sonySDIO: Bool) async throws {
    let client = PTPIPClient(host: host, port: port, guid: try loadOrCreateGUID(), name: name)
    log("Connecting to \(host):\(port) as \"\(name)\"… (if the camera asks to allow this Mac, accept)")
    let hello = try await client.connect()
    log("Connected to \"\(hello.name)\": connection #\(hello.connectionNumber), GUID \(hex(hello.guid)), protocol \(PTPCode.hex(hello.protocolVersion))")

    let info = try await client.getDeviceInfo()
    log("Device: \(info.manufacturer) \(info.model), firmware \(info.deviceVersion), serial \(info.serialNumber)")
    log("Vendor extension \(PTPCode.hex(info.vendorExtensionID)) v\(info.vendorExtensionVersion) \"\(info.vendorExtensionDescription)\", mode \(PTPCode.hex(info.functionalMode))")
    log("Operations (\(info.operationsSupported.count)): " + info.operationsSupported.map(PTPCode.operation).joined(separator: ", "))
    log("Events (\(info.eventsSupported.count)): " + info.eventsSupported.map(PTPCode.event).joined(separator: ", "))
    log("Image formats: " + info.imageFormats.map(PTPCode.objectFormat).joined(separator: ", "))

    try await client.openSession()
    log("Session open")

    if sonySDIO {
        // libgphoto2's Sony init: SDIOConnect phases 1 and 2, GetSDIOGetExtDeviceInfo(0xC8), phase 3.
        let steps: [(UInt16, [UInt32])] = [
            (PTPCode.Operation.sonySDIOConnect, [1, 0, 0]),
            (PTPCode.Operation.sonySDIOConnect, [2, 0, 0]),
            (PTPCode.Operation.sonyGetSDIOExtDeviceInfo, [0xC8]),
            (PTPCode.Operation.sonySDIOConnect, [3, 0, 0]),
        ]
        for (code, parameters) in steps {
            let result = try await client.transaction(code, parameters)
            log("\(PTPCode.operation(code))\(params(parameters)) → \(PTPCode.response(result.response.code)), \(result.data.count) data bytes")
        }
    }

    log("Waiting for events. Take a photo. Ctrl-C to stop.")
    for try await packet in try await client.events() {
        guard case let .event(event) = packet else {
            log("Event channel: \(packet)")
            continue
        }
        log("Event \(PTPCode.event(event.code))\(params(event.parameters))")

        let isNewObject = event.code == PTPCode.Event.objectAdded || event.code == PTPCode.Event.sonyObjectAdded
        if isNewObject, let handle = event.parameters.first {
            do {
                let object = try await client.getObjectInfo(handle: handle)
                log("  → \(object.filename), \(PTPCode.objectFormat(object.format)), \(object.compressedSize) bytes, \(object.imageWidth)×\(object.imageHeight), captured \(object.captureDate)")
            } catch {
                log("  → GetObjectInfo(\(PTPCode.hex(handle))) failed: \(error)")
            }
        }
    }
    log("Camera closed the event channel")
}

// MARK: - arguments

var arguments = Array(CommandLine.arguments.dropFirst())

@MainActor func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard index + 1 < arguments.count else { fail("\(name) needs a value") }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

@MainActor func numberOption<T: LosslessStringConvertible>(_ name: String, as _: T.Type) -> T? {
    guard let text = option(name) else { return nil }
    guard let value = T(text) else { fail("\(name): invalid value \"\(text)\"") }
    return value
}

@MainActor func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

do {
    switch arguments.first {
    case "discover":
        arguments.removeFirst()
        let seconds = numberOption("--seconds", as: Double.self) ?? 10
        guard arguments.isEmpty else { fail("unexpected arguments: \(arguments.joined(separator: " "))\n\n\(usage)") }
        try await runDiscover(seconds: seconds)
    case "connect":
        arguments.removeFirst()
        let port = numberOption("--port", as: UInt16.self) ?? PTPIPClient.defaultPort
        let name = option("--name") ?? "Shutterdrop"
        let sonySDIO = flag("--sony-sdio")
        guard arguments.count == 1, let host = arguments.first else { fail("connect needs one camera IP address\n\n\(usage)") }
        try await runConnect(host: host, port: port, name: name, sonySDIO: sonySDIO)
    case "-h", "--help", "help":
        print(usage)
    default:
        fail(usage)
    }
} catch {
    fail("\(error)")
}
