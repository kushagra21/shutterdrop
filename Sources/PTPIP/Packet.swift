import Foundation

/// PTP/IP packet types. Every packet starts with UInt32 length (including the
/// 8-byte header) and UInt32 type, both little-endian.
public enum PacketType: UInt32, Sendable {
    case initCommandRequest = 1
    case initCommandAck = 2
    case initEventRequest = 3
    case initEventAck = 4
    case initFail = 5
    case operationRequest = 6
    case operationResponse = 7
    case event = 8
    case startData = 9
    case data = 10
    case cancel = 11
    case endData = 12
    case probeRequest = 13
    case probeResponse = 14
}

public struct OperationRequest: Equatable, Sendable {
    /// 1 = no data phase or camera-to-host data, 2 = host-to-camera data.
    public static let noDataOrDataIn: UInt32 = 1
    public static let dataOut: UInt32 = 2

    public var dataPhase: UInt32
    public var code: UInt16
    public var transactionID: UInt32
    public var parameters: [UInt32]

    public init(dataPhase: UInt32 = noDataOrDataIn, code: UInt16, transactionID: UInt32, parameters: [UInt32] = []) {
        self.dataPhase = dataPhase
        self.code = code
        self.transactionID = transactionID
        self.parameters = parameters
    }
}

/// An operation response or an event: both are a code, a transaction ID and up to five parameters.
public struct CodeContainer: Equatable, Sendable {
    public var code: UInt16
    public var transactionID: UInt32
    public var parameters: [UInt32]

    public init(code: UInt16, transactionID: UInt32, parameters: [UInt32] = []) {
        self.code = code
        self.transactionID = transactionID
        self.parameters = parameters
    }
}

public typealias OperationResponse = CodeContainer
public typealias Event = CodeContainer

public enum Packet: Equatable, Sendable {
    public static let headerSize = 8
    public static let protocolVersion: UInt32 = 0x0001_0000

    case initCommandRequest(guid: [UInt8], name: String, version: UInt32)
    case initCommandAck(connectionNumber: UInt32, guid: [UInt8], name: String, version: UInt32)
    case initEventRequest(connectionNumber: UInt32)
    case initEventAck
    case initFail(reason: UInt32)
    case operationRequest(OperationRequest)
    case operationResponse(OperationResponse)
    case event(Event)
    case startData(transactionID: UInt32, totalLength: UInt64)
    case data(transactionID: UInt32, payload: [UInt8])
    case endData(transactionID: UInt32, payload: [UInt8])
    case cancel(transactionID: UInt32)
    case probeRequest
    case probeResponse
    case unknown(type: UInt32, payload: [UInt8])

    /// The packet with its 8-byte header, ready to send.
    public func encoded() -> Data {
        var body = ByteWriter()
        let type: UInt32
        switch self {
        case let .initCommandRequest(guid, name, version):
            type = PacketType.initCommandRequest.rawValue
            body.append(bytes: guid)
            body.appendNullTerminatedUTF16(name)
            body.append(version)
        case let .initCommandAck(connectionNumber, guid, name, version):
            type = PacketType.initCommandAck.rawValue
            body.append(connectionNumber)
            body.append(bytes: guid)
            body.appendNullTerminatedUTF16(name)
            body.append(version)
        case let .initEventRequest(connectionNumber):
            type = PacketType.initEventRequest.rawValue
            body.append(connectionNumber)
        case .initEventAck:
            type = PacketType.initEventAck.rawValue
        case let .initFail(reason):
            type = PacketType.initFail.rawValue
            body.append(reason)
        case let .operationRequest(request):
            type = PacketType.operationRequest.rawValue
            body.append(request.dataPhase)
            body.append(request.code)
            body.append(request.transactionID)
            for parameter in request.parameters { body.append(parameter) }
        case let .operationResponse(container), let .event(container):
            type = if case .event = self { PacketType.event.rawValue } else { PacketType.operationResponse.rawValue }
            body.append(container.code)
            body.append(container.transactionID)
            for parameter in container.parameters { body.append(parameter) }
        case let .startData(transactionID, totalLength):
            type = PacketType.startData.rawValue
            body.append(transactionID)
            body.append(totalLength)
        case let .data(transactionID, payload):
            type = PacketType.data.rawValue
            body.append(transactionID)
            body.append(bytes: payload)
        case let .endData(transactionID, payload):
            type = PacketType.endData.rawValue
            body.append(transactionID)
            body.append(bytes: payload)
        case let .cancel(transactionID):
            type = PacketType.cancel.rawValue
            body.append(transactionID)
        case .probeRequest:
            type = PacketType.probeRequest.rawValue
        case .probeResponse:
            type = PacketType.probeResponse.rawValue
        case let .unknown(rawType, payload):
            type = rawType
            body.append(bytes: payload)
        }

        var packet = ByteWriter()
        packet.append(UInt32(Self.headerSize + body.bytes.count))
        packet.append(type)
        packet.append(bytes: body.bytes)
        return Data(packet.bytes)
    }

    /// Reads the length and type from the first 8 bytes of a packet.
    public static func header(_ bytes: [UInt8]) throws -> (length: UInt32, type: UInt32) {
        var reader = ByteReader(bytes)
        return (try reader.read(), try reader.read())
    }

    /// Decodes a packet body (everything after the 8-byte header).
    public static func decode(type rawType: UInt32, payload: [UInt8]) throws -> Packet {
        guard let type = PacketType(rawValue: rawType) else {
            return .unknown(type: rawType, payload: payload)
        }
        var reader = ByteReader(payload)
        switch type {
        case .initCommandRequest:
            return .initCommandRequest(
                guid: try reader.readBytes(16),
                name: try reader.readNullTerminatedUTF16(),
                version: reader.remaining >= 4 ? try reader.read() : 0
            )
        case .initCommandAck:
            return .initCommandAck(
                connectionNumber: try reader.read(),
                guid: try reader.readBytes(16),
                name: try reader.readNullTerminatedUTF16(),
                version: reader.remaining >= 4 ? try reader.read() : 0
            )
        case .initEventRequest:
            return .initEventRequest(connectionNumber: try reader.read())
        case .initEventAck:
            return .initEventAck
        case .initFail:
            return .initFail(reason: reader.remaining >= 4 ? try reader.read() : 0)
        case .operationRequest:
            return .operationRequest(OperationRequest(
                dataPhase: try reader.read(),
                code: try reader.read(),
                transactionID: try reader.read(),
                parameters: try readParameters(&reader)
            ))
        case .operationResponse:
            return .operationResponse(try readCodeContainer(&reader))
        case .event:
            return .event(try readCodeContainer(&reader))
        case .startData:
            return .startData(transactionID: try reader.read(), totalLength: try reader.read())
        case .data:
            return .data(transactionID: try reader.read(), payload: reader.readRest())
        case .endData:
            return .endData(transactionID: try reader.read(), payload: reader.readRest())
        case .cancel:
            return .cancel(transactionID: try reader.read())
        case .probeRequest:
            return .probeRequest
        case .probeResponse:
            return .probeResponse
        }
    }

    private static func readCodeContainer(_ reader: inout ByteReader) throws -> CodeContainer {
        CodeContainer(code: try reader.read(), transactionID: try reader.read(), parameters: try readParameters(&reader))
    }

    private static func readParameters(_ reader: inout ByteReader) throws -> [UInt32] {
        var parameters: [UInt32] = []
        while reader.remaining >= 4, parameters.count < 5 {
            parameters.append(try reader.read())
        }
        return parameters
    }
}
