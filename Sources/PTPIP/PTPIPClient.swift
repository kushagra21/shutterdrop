import Foundation

public enum PTPIPError: Error, CustomStringConvertible {
    case notConnected
    case connectionClosed
    case initFailed(reason: UInt32)
    case unexpectedPacket(Packet)
    case malformedPacket(length: UInt32)
    case packetTooLarge(length: UInt32)
    case transactionInProgress
    case transactionMismatch(expected: UInt32, got: UInt32)
    case cancelled(transactionID: UInt32)
    case operationFailed(operation: UInt16, response: UInt16)

    public var description: String {
        switch self {
        case .notConnected: "not connected"
        case .connectionClosed: "camera closed the connection"
        case let .initFailed(reason): "camera rejected the connection (Init_Fail reason \(PTPCode.hex(reason)))"
        case let .unexpectedPacket(packet): "unexpected packet: \(packet)"
        case let .malformedPacket(length): "malformed packet (length \(length))"
        case let .packetTooLarge(length): "packet too large (\(length) bytes)"
        case .transactionInProgress: "another transaction is already running"
        case let .transactionMismatch(expected, got): "response for transaction \(got), expected \(expected)"
        case let .cancelled(id): "camera cancelled transaction \(id)"
        case let .operationFailed(operation, response):
            "\(PTPCode.operation(operation)) failed: \(PTPCode.response(response))"
        }
    }
}

public struct CameraHello: Sendable {
    public var connectionNumber: UInt32
    public var guid: [UInt8]
    public var name: String
    public var protocolVersion: UInt32
}

public struct TransactionResult: Sendable {
    public var response: OperationResponse
    public var data: [UInt8]

    public var isOK: Bool { response.code == PTPCode.Response.ok }
}

/// A PTP/IP initiator: connects to a camera, runs operations on the command
/// channel and streams events from the event channel.
public actor PTPIPClient {
    public static let defaultPort: UInt16 = 15740

    private let host: String
    private let port: UInt16
    private let guid: [UInt8]
    private let name: String
    private var commandChannel: TCPChannel?
    private var eventChannel: TCPChannel?
    private var sessionOpen = false
    private var nextTransactionID: UInt32 = 1
    private var transactionInFlight = false

    public init(host: String, port: UInt16 = defaultPort, guid: [UInt8], name: String) {
        precondition(guid.count == 16, "PTP/IP GUIDs are 16 bytes")
        self.host = host
        self.port = port
        self.guid = guid
        self.name = name
    }

    /// Opens the command channel, then the event channel (PTP/IP spec order).
    public func connect() async throws -> CameraHello {
        let command = TCPChannel(host: host, port: port, label: "command")
        try await command.open()
        let hello: CameraHello
        do {
            try await command.write(.initCommandRequest(guid: guid, name: name, version: Packet.protocolVersion))
            switch try await command.readPacket() {
            case let .initCommandAck(connectionNumber, guid, name, version):
                hello = CameraHello(connectionNumber: connectionNumber, guid: guid, name: name, protocolVersion: version)
            case let .initFail(reason):
                throw PTPIPError.initFailed(reason: reason)
            case let other:
                throw PTPIPError.unexpectedPacket(other)
            }
        } catch {
            command.close()
            throw error
        }

        let events = TCPChannel(host: host, port: port, label: "event")
        do {
            try await events.open()
            try await events.write(.initEventRequest(connectionNumber: hello.connectionNumber))
            switch try await events.readPacket() {
            case .initEventAck: break
            case let .initFail(reason): throw PTPIPError.initFailed(reason: reason)
            case let other: throw PTPIPError.unexpectedPacket(other)
            }
        } catch {
            events.close()
            command.close()
            throw error
        }

        commandChannel = command
        eventChannel = events
        return hello
    }

    public func disconnect() {
        commandChannel?.close()
        eventChannel?.close()
        commandChannel = nil
        eventChannel = nil
        sessionOpen = false
    }

    /// Runs one operation with no host-to-camera data and collects any data the camera sends back.
    public func transaction(_ code: UInt16, _ parameters: [UInt32] = []) async throws -> TransactionResult {
        guard let command = commandChannel else { throw PTPIPError.notConnected }
        guard !transactionInFlight else { throw PTPIPError.transactionInProgress }
        transactionInFlight = true
        defer { transactionInFlight = false }

        // Operations outside a session (GetDeviceInfo, OpenSession) use transaction ID 0.
        let id: UInt32
        if sessionOpen {
            id = nextTransactionID
            nextTransactionID &+= 1
        } else {
            id = 0
        }

        try await command.write(.operationRequest(OperationRequest(code: code, transactionID: id, parameters: parameters)))
        var data: [UInt8] = []
        while true {
            let packet = try await command.readPacket()
            switch packet {
            case let .startData(transactionID, totalLength):
                try check(transactionID, id)
                data.reserveCapacity(Int(min(totalLength, UInt64(TCPChannel.maxPacketLength))))
            case let .data(transactionID, payload), let .endData(transactionID, payload):
                try check(transactionID, id)
                data.append(contentsOf: payload)
            case let .operationResponse(response):
                try check(response.transactionID, id)
                return TransactionResult(response: response, data: data)
            case let .cancel(transactionID):
                throw PTPIPError.cancelled(transactionID: transactionID)
            case .probeRequest:
                try await command.write(.probeResponse)
            default:
                throw PTPIPError.unexpectedPacket(packet)
            }
        }
    }

    public func getDeviceInfo() async throws -> DeviceInfo {
        try DeviceInfo(parsing: try await requireOK(PTPCode.Operation.getDeviceInfo).data)
    }

    public func openSession(id sessionID: UInt32 = 1) async throws {
        _ = try await requireOK(PTPCode.Operation.openSession, [sessionID])
        sessionOpen = true
        nextTransactionID = 1
    }

    public func getObjectInfo(handle: UInt32) async throws -> ObjectInfo {
        try ObjectInfo(parsing: try await requireOK(PTPCode.Operation.getObjectInfo, [handle]).data)
    }

    /// Camera events as they arrive. Keep-alive probes are answered here and not yielded.
    public func events() throws -> AsyncThrowingStream<Packet, Error> {
        guard let channel = eventChannel else { throw PTPIPError.notConnected }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let packet = try await channel.readPacket()
                        switch packet {
                        case .probeRequest: try await channel.write(.probeResponse)
                        case .probeResponse: break
                        default: continuation.yield(packet)
                        }
                    }
                    continuation.finish()
                } catch PTPIPError.connectionClosed {
                    // The camera ending the session (Wi-Fi off, power off) is a normal end of stream.
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func requireOK(_ code: UInt16, _ parameters: [UInt32] = []) async throws -> TransactionResult {
        let result = try await transaction(code, parameters)
        guard result.isOK else { throw PTPIPError.operationFailed(operation: code, response: result.response.code) }
        return result
    }

    private func check(_ got: UInt32, _ expected: UInt32) throws {
        guard got == expected else { throw PTPIPError.transactionMismatch(expected: expected, got: got) }
    }
}
