import Testing
@testable import ShutterdropCore

@Test func pairingPayloadLayout() {
    let guid = Array(UInt8(0x10)...UInt8(0x1F))
    let payload = CameraPairing.payload(guid: guid, name: "Shutterdrop")
    #expect(payload.count == 8192)
    #expect(payload[0..<5] == [0x25, 0x01, 0x00, 0x00, 0x08])
    #expect(payload[5..<17].allSatisfy { $0 == 0 })
    // Name: first 8 UTF-16LE code units ("Shutterd").
    #expect(Array(payload[17..<33]) == Array("Shutterd".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
    #expect(payload[33..<177].allSatisfy { $0 == 0 })
    #expect(payload[177..<181] == [0x10, 0x00, 0x00, 0x00])
    #expect(Array(payload[181..<197]) == guid)
    #expect(payload[197...].allSatisfy { $0 == 0 })
}

@Test func commandBlockWrapperBytes() {
    let wrapper = CameraPairing.commandBlockWrapper(tag: 1, dataLength: 8192, lun: 2, command: CameraPairing.command)
    #expect(wrapper.count == 31)
    #expect(wrapper == Array("USBC".utf8) + [1, 0, 0, 0] + [0x00, 0x20, 0, 0] + [0x00, 2, 9]
        + [0x7A, 0x04, 0, 0, 0, 0, 0, 0, 0] + [UInt8](repeating: 0, count: 7))
}

@Test func parsesCommandStatus() throws {
    let status = try CameraPairing.parseStatus(Array("USBS".utf8) + [1, 0, 0, 0] + [0, 0, 0, 0] + [0])
    #expect(status.tag == 1)
    #expect(status.status == 0)
    #expect(throws: CameraPairingError.self) { try CameraPairing.parseStatus([0, 1, 2]) }
}
