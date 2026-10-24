import Foundation
import os
import PTPIP
import ShutterdropCore
import SSDP

// sdprobe: Shutterdrop's command-line tool. Probes the camera (discover,
// connect), saves live previews (live) and imports full-size files (import).

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
      sdprobe live [--endpoint URL] [--out DIR]
          Camera in Ctrl w/ Smartphone mode, Mac joined to its DIRECT-… Wi-Fi:
          save a preview of every shot as it's taken, until Ctrl-C.
      sdprobe import [<camera-ip>] [--wait N] [--since YYYY-MM-DD[THH:MM]] [--dry-run] [--out DIR] [--all-formats]
          Camera in Send to Computer mode on the home Wi-Fi: copy new JPEG/ARW
          files, then pair them with the live previews. Without an IP, waits up
          to N seconds (default 120) for the camera to announce itself.
          --since only copies files the camera dated at or after that day/time;
          --dry-run lists what would be copied without copying.
      --out DIR defaults to ~/Pictures/Shutterdrop.
    """

setvbuf(stdout, nil, _IOLBF, 0)

/// Callable from any thread (camera callbacks arrive off the main actor).
func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    print("\(formatter.string(from: Date())) \(message)")
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
        return false
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
    let client = PTPIPClient(host: host, port: port, guid: try ClientIdentity.guid(), name: name)
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

// MARK: - live

@MainActor func runLive(endpoint: URL?, library: PhotoLibrary) async throws {
    log("Looking for the camera's Remote API…")
    let camera = if let endpoint { RemoteCamera(endpoint: endpoint) } else { await RemoteCamera.discover() }
    log("Using \(camera.endpoint.absoluteString). Saving previews under \(library.root.path)")
    try await LiveSession(camera: camera, library: library).run { update in
        let message = switch update {
        case let .connected(apis): "Connected (\(apis.count) API calls available). Take photos with the camera. Ctrl-C to stop."
        case let .status(status): "Camera: \(status)"
        case let .saved(photo): "Saved \(photo.url.path)"
        case let .problem(problem): "Problem: \(problem)"
        }
        log(message)
    }
}

// MARK: - import

@MainActor func runImport(host: String?, port: UInt16, wait: Double, library: PhotoLibrary, allFormats: Bool, since: Date?, dryRun: Bool) async throws {
    var host = host
    if host == nil {
        log("Waiting up to \(Int(wait)) s. Choose Network → Send to Computer on the camera.")
        host = try await CardImporter.waitForCamera(seconds: wait)
    }
    guard let host else {
        fail("no camera announced itself; is Send to Computer running and the camera on this Wi-Fi?")
    }
    log("Importing from \(host) into \(library.root.path)")
    let importer = CardImporter(library: library, formats: allFormats ? [] : CardImporter.defaultFormats, since: since)
    let saved = try await importer.run(
        host: host, port: port, guid: try ClientIdentity.guid(), name: ClientIdentity.name, confirm: { _ in !dryRun }
    ) { update in
        let message = switch update {
        case let .connected(model): "Connected to \(model)"
        case let .found(total, new): describeFound(total: total, new: new, listing: dryRun)
        case let .saved(photo, index, count): "[\(index)/\(count)] \(photo.url.lastPathComponent)"
        }
        log(message)
    }
    guard !dryRun else { return log("Dry run: nothing copied") }
    log("Imported \(saved.count) file(s)")

    for day in Set(saved.map { library.dayFolder($0.captured) }).sorted(by: { $0.path < $1.path }) {
        let matches = ShotMatcher.match(previews: library.previews(inDay: day), originals: library.originals(inDay: day))
        guard !matches.isEmpty else { continue }
        log("\(day.lastPathComponent): \(matches.filter { !$0.originals.isEmpty }.count) of \(matches.count) previews matched")
        for match in matches {
            let names = match.originals.map(\.url.lastPathComponent).joined(separator: " + ")
            print("  \(match.preview.url.lastPathComponent) → \(names.isEmpty ? "(no original)" : names)")
        }
    }
}

func describeFound(total: Int, new: [PendingFile], listing: Bool) -> String {
    let dates = new.compactMap(\.captured)
    let megabytes = new.reduce(0) { $0 + $1.size } / 1_000_000
    var text = "\(total) matching file(s) on the camera, \(new.count) new (\(megabytes) MB)"
    if let first = dates.min(), let last = dates.max() {
        text += ", camera dates \(first.formatted(date: .numeric, time: .shortened)) – \(last.formatted(date: .numeric, time: .shortened))"
    }
    if listing {
        for file in new.prefix(50) {
            text += "\n  \(file.name)  \(file.captured?.formatted(date: .numeric, time: .standard) ?? "undated")"
        }
        if new.count > 50 { text += "\n  … and \(new.count - 50) more" }
    }
    return text
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

/// `2026-10-24`, `2026-10-24T13:30` or `2026-10-24T13:30:15`, local time.
func parseSince(_ text: String) -> Date? {
    let parts = text.split(separator: "T", maxSplits: 1)
    let day = parts[0].replacingOccurrences(of: "-", with: "")
    var time = parts.count > 1 ? parts[1].replacingOccurrences(of: ":", with: "") : "0000"
    if time.count == 4 { time += "00" }
    guard day.count == 8, time.count == 6 else { return nil }
    return CameraTimestamp.fromPTP("\(day)T\(time)")
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
    case "live":
        arguments.removeFirst()
        let endpointText = option("--endpoint")
        let endpoint = endpointText.flatMap(URL.init(string:))
        if endpointText != nil, endpoint == nil { fail("--endpoint must be a URL") }
        let library = PhotoLibrary(root: option("--out").map { URL(filePath: $0) } ?? PhotoLibrary.defaultRoot)
        guard arguments.isEmpty else { fail("unexpected arguments: \(arguments.joined(separator: " "))\n\n\(usage)") }
        try await runLive(endpoint: endpoint, library: library)
    case "import":
        arguments.removeFirst()
        let wait = numberOption("--wait", as: Double.self) ?? 120
        let port = numberOption("--port", as: UInt16.self) ?? PTPIPClient.defaultPort
        let library = PhotoLibrary(root: option("--out").map { URL(filePath: $0) } ?? PhotoLibrary.defaultRoot)
        let allFormats = flag("--all-formats")
        let sinceText = option("--since")
        let since = sinceText.flatMap(parseSince)
        if sinceText != nil, since == nil { fail("--since must look like 2026-10-24, 2026-10-24T13:30 or 2026-10-24T13:30:15") }
        let dryRun = flag("--dry-run")
        guard arguments.count <= 1 else { fail("import takes at most one camera IP address\n\n\(usage)") }
        try await runImport(host: arguments.first, port: port, wait: wait, library: library, allFormats: allFormats, since: since, dryRun: dryRun)
    case "-h", "--help", "help":
        print(usage)
    default:
        fail(usage)
    }
} catch {
    fail("\(error)")
}
