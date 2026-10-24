import Foundation
import Testing
@testable import PTPIP

private func roundTrip(_ packet: Packet) throws -> Packet {
    let bytes = [UInt8](packet.encoded())
    let (length, type) = try Packet.header(bytes)
    #expect(Int(length) == bytes.count)
    return try Packet.decode(type: type, payload: Array(bytes[Packet.headerSize...]))
}

@Test func initCommandRequestBytes() {
    let guid = Array(UInt8(1)...UInt8(16))
    let bytes = [UInt8](Packet.initCommandRequest(guid: guid, name: "A", version: Packet.protocolVersion).encoded())
    #expect(bytes == [0x20, 0, 0, 0, 0x01, 0, 0, 0] + guid + [0x41, 0, 0, 0] + [0, 0, 0x01, 0])
}

@Test func operationRequestBytes() {
    let request = OperationRequest(code: PTPCode.Operation.openSession, transactionID: 0, parameters: [1])
    let bytes = [UInt8](Packet.operationRequest(request).encoded())
    #expect(bytes == [0x16, 0, 0, 0, 0x06, 0, 0, 0, 0x01, 0, 0, 0, 0x02, 0x10, 0, 0, 0, 0, 0x01, 0, 0, 0])
}

@Test func decodesCameraResponse() throws {
    // Operation response: OK, transaction 5, one parameter 7.
    let payload: [UInt8] = [0x01, 0x20, 0x05, 0, 0, 0, 0x07, 0, 0, 0]
    #expect(try Packet.decode(type: 7, payload: payload)
        == .operationResponse(OperationResponse(code: 0x2001, transactionID: 5, parameters: [7])))
}

@Test(arguments: [
    Packet.initCommandAck(connectionNumber: 3, guid: Array(repeating: 0xAB, count: 16), name: "ILCE-7M3", version: 0x10000),
    .initEventRequest(connectionNumber: 3),
    .initEventAck,
    .initFail(reason: 1),
    .operationRequest(OperationRequest(code: 0x1008, transactionID: 9, parameters: [0xFFFF_C001])),
    .event(Event(code: 0xC201, transactionID: 0, parameters: [0xFFFF_C001])),
    .startData(transactionID: 4, totalLength: 25_000_000),
    .data(transactionID: 4, payload: [1, 2, 3]),
    .endData(transactionID: 4, payload: [4, 5]),
    .cancel(transactionID: 4),
    .probeRequest,
    .probeResponse,
    .unknown(type: 0x99, payload: [9]),
])
func roundTrips(_ packet: Packet) throws {
    #expect(try roundTrip(packet) == packet)
}

@Test func parametersCappedAtFive() throws {
    var writer = ByteWriter()
    writer.append(UInt16(0x4002))
    writer.append(UInt32(0))
    for parameter in UInt32(1)...6 { writer.append(parameter) }
    guard case let .event(event) = try Packet.decode(type: 8, payload: writer.bytes) else {
        Issue.record("not an event")
        return
    }
    #expect(event.parameters == [1, 2, 3, 4, 5])
}

@Test func truncatedPacketThrows() {
    #expect(throws: ByteReaderError.self) {
        try Packet.decode(type: 7, payload: [0x01, 0x20, 0x05])
    }
}
