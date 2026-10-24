import Foundation
import IOKit
import IOUSBHost

public enum CameraPairingError: Error, CustomStringConvertible {
    case notRoot
    case cameraNotFound
    case notMassStorage
    case endpointsNotFound
    case badStatus(String)
    case commandFailed(status: UInt8)

    public var description: String {
        switch self {
        case .notRoot: "pairing needs administrator rights (run with sudo)"
        case .cameraNotFound: "no Sony camera on USB; connect it and turn it on"
        case .notMassStorage: "the camera isn't in USB Mass Storage mode (MENU → Setup → USB Connection → Mass Storage)"
        case .endpointsNotFound: "the camera's USB storage interface has no bulk endpoints"
        case let .badStatus(detail): "unexpected reply from the camera: \(detail)"
        case let .commandFailed(status): "the camera rejected the pairing command (status \(status))"
        }
    }
}

/// Registers this Mac on a Sony camera so Send to Computer will talk to it.
///
/// Over USB Mass Storage (Bulk-Only Transport): a vendor SCSI command 0x7A,
/// then an 8 KB block holding the computer's name and PTP/IP GUID. Protocol
/// reverse-engineered by Clemens Fruhwirth (sony-guid-setter in sony-pm-alt).
/// Taking the camera from macOS's storage driver needs root.
public enum CameraPairing {
    public static let sonyVendorID = 0x054C
    static let command: [UInt8] = [0x7A, 0x04, 0, 0, 0, 0, 0, 0, 0]
    static let payloadSize = 8192
    static let massStorageClass = 8

    /// Whether a Sony camera is on USB, and whether it's in Mass Storage mode.
    /// Needs no special rights, so the app can check before asking for a password.
    public static func connectedCamera() -> (found: Bool, massStorage: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, sonyDeviceMatching())
        guard service != 0 else { return (false, false) }
        defer { IOObjectRelease(service) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else { return (true, false) }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            let interfaceClass = IORegistryEntryCreateCFProperty(child, "bInterfaceClass" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            if interfaceClass == massStorageClass { return (true, true) }
        }
        return (true, false)
    }

    /// Matches by explicit IOPropertyMatch: a top-level idVendor key (as
    /// IOUSBHostDevice's createMatchingDictionary builds it) matched nothing
    /// from user space on macOS 26.
    private static func sonyDeviceMatching() -> CFDictionary {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching["IOPropertyMatch"] = ["idVendor": sonyVendorID]
        return matching
    }

    public static func pair(guid: [UInt8], name: String, log: (String) -> Void = { _ in }) throws {
        precondition(guid.count == 16, "PTP/IP GUIDs are 16 bytes")
        guard getuid() == 0 else { throw CameraPairingError.notRoot }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, sonyDeviceMatching())
        guard service != 0 else { throw CameraPairingError.cameraNotFound }
        defer { IOObjectRelease(service) }

        // Capture detaches macOS's drivers (the camera's disk disappears); destroying
        // the device afterwards resets it and hands it back to them.
        log("Taking over the camera's USB connection…")
        let device = try IOUSBHostDevice(__ioService: service, options: [.deviceCapture], queue: nil, interestHandler: nil)
        defer { device.destroy() }
        try device.__configure(withValue: 1, matchInterfaces: true)

        let interface = try openMassStorageInterface(of: device.ioService)
        defer { interface.destroy() }

        let (inAddress, outAddress) = try bulkEndpoints(interface)
        let input = try interface.copyPipe(withAddress: inAddress)
        let output = try interface.copyPipe(withAddress: outAddress)
        let lun = maxLUN(interface)
        log("Mass storage interface ready (LUN \(lun))")

        let tag: UInt32 = 1
        try send(commandBlockWrapper(tag: tag, dataLength: UInt32(payloadSize), lun: lun, command: command), on: output, using: interface)
        try send(payload(guid: guid, name: name), on: output, using: interface)
        log("Sent the pairing block")

        let status = try receiveStatus(on: input, using: interface)
        guard status.tag == tag else { throw CameraPairingError.badStatus("tag \(status.tag), expected \(tag)") }
        guard status.status == 0 else { throw CameraPairingError.commandFailed(status: status.status) }
        log("The camera accepted the pairing")
    }

    // MARK: - Wire format

    /// Layout: 25 01 00 00 08, 12 zero bytes, the name as 16 bytes of UTF-16LE,
    /// 144 zero bytes, 10 00 00 00, the 16-byte GUID, zeros to 8192 bytes.
    static func payload(guid: [UInt8], name: String) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: payloadSize)
        bytes.replaceSubrange(0..<5, with: [0x25, 0x01, 0x00, 0x00, 0x08])
        let nameBytes = name.utf16.prefix(8).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        bytes.replaceSubrange(17..<17 + nameBytes.count, with: nameBytes)
        bytes.replaceSubrange(177..<181, with: [0x10, 0x00, 0x00, 0x00])
        bytes.replaceSubrange(181..<197, with: guid)
        return bytes
    }

    /// Bulk-Only Transport Command Block Wrapper (31 bytes) for a host-to-device command.
    static func commandBlockWrapper(tag: UInt32, dataLength: UInt32, lun: UInt8, command: [UInt8]) -> [UInt8] {
        Array("USBC".utf8) + littleEndian(tag) + littleEndian(dataLength)
            + [0x00, lun, UInt8(command.count)]
            + command + [UInt8](repeating: 0, count: 16 - command.count)
    }

    /// Bulk-Only Transport Command Status Wrapper (13 bytes).
    static func parseStatus(_ bytes: [UInt8]) throws -> (tag: UInt32, status: UInt8) {
        guard bytes.count >= 13, bytes[0..<4].elementsEqual("USBS".utf8) else {
            throw CameraPairingError.badStatus("\(bytes.count) bytes: \(bytes.prefix(13).map { String(format: "%02x", $0) }.joined())")
        }
        let tag = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[4 + $1]) << (8 * $1) }
        return (tag, bytes[12])
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    // MARK: - USB

    /// Right after capture and configure, the previous interface may still be
    /// terminating and refuse to open; look it up again until the new one opens.
    private static func openMassStorageInterface(of device: io_service_t) throws -> IOUSBHostInterface {
        var lastError: Error = CameraPairingError.notMassStorage
        for _ in 0..<15 {
            do {
                let service = try massStorageInterface(of: device)
                defer { IOObjectRelease(service) }
                return try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        throw lastError
    }

    private static func massStorageInterface(of device: io_service_t) throws -> io_service_t {
        // Interfaces appear as children of the device once it's configured.
        for _ in 0..<20 {
            var iterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(device, kIOServicePlane, &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                while case let child = IOIteratorNext(iterator), child != 0 {
                    let interfaceClass = IORegistryEntryCreateCFProperty(child, "bInterfaceClass" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? Int
                    if IOObjectConformsTo(child, "IOUSBHostInterface") != 0, interfaceClass == massStorageClass {
                        return child
                    }
                    IOObjectRelease(child)
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw CameraPairingError.notMassStorage
    }

    private static func bulkEndpoints(_ interface: IOUSBHostInterface) throws -> (in: Int, out: Int) {
        var input: Int?
        var output: Int?
        var endpoint = IOUSBGetNextEndpointDescriptor(interface.configurationDescriptor, interface.interfaceDescriptor, nil)
        while let current = endpoint {
            let isBulk = current.pointee.bmAttributes & 0x03 == 0x02
            let address = Int(current.pointee.bEndpointAddress)
            if isBulk, address & 0x80 != 0 { input = input ?? address }
            if isBulk, address & 0x80 == 0 { output = output ?? address }
            endpoint = IOUSBGetNextEndpointDescriptor(
                interface.configurationDescriptor, interface.interfaceDescriptor,
                UnsafeRawPointer(current).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
            )
        }
        guard let input, let output else { throw CameraPairingError.endpointsNotFound }
        return (input, output)
    }

    /// Bulk-Only "Get Max LUN". sony-guid-setter addresses the command to the
    /// LUN this returns (2 on the A7 III); a stalled request means 0.
    private static func maxLUN(_ interface: IOUSBHostInterface) -> UInt8 {
        let request = IOUSBDeviceRequest(
            bmRequestType: 0xA1, bRequest: 0xFE, wValue: 0,
            wIndex: UInt16(interface.interfaceDescriptor.pointee.bInterfaceNumber), wLength: 1
        )
        // Plain NSMutableData: IOUSBHost's ioData buffers have a fixed length and
        // throw an Objective-C exception if it's set.
        let buffer = NSMutableData(length: 1)!
        var transferred = 0
        guard (try? interface.__send(request, data: buffer, bytesTransferred: &transferred, completionTimeout: 1)) != nil,
              transferred == 1 else { return 0 }
        return buffer.bytes.load(as: UInt8.self)
    }

    private static func send(_ bytes: [UInt8], on pipe: IOUSBHostPipe, using interface: IOUSBHostInterface) throws {
        let buffer = NSMutableData(bytes: bytes, length: bytes.count)
        var transferred = 0
        try pipe.__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: 2)
        guard transferred == bytes.count else {
            throw CameraPairingError.badStatus("sent \(transferred) of \(bytes.count) bytes")
        }
    }

    private static func receiveStatus(on pipe: IOUSBHostPipe, using interface: IOUSBHostInterface) throws -> (tag: UInt32, status: UInt8) {
        let buffer = NSMutableData(length: 13)!
        var transferred = 0
        do {
            try pipe.__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: 2)
        } catch {
            // The device may stall the status phase once; clear it and read again.
            try pipe.clearStall()
            try pipe.__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: 2)
        }
        return try parseStatus([UInt8](Data(bytes: buffer.bytes, count: transferred)))
    }
}
