import Testing
@testable import PTPIP

@Test func ptpStringRoundTrip() throws {
    var writer = ByteWriter()
    writer.appendPTPString("AB")
    writer.appendPTPString("")
    #expect(writer.bytes == [3, 0x41, 0, 0x42, 0, 0, 0, 0])
    var reader = ByteReader(writer.bytes)
    #expect(try reader.readPTPString() == "AB")
    #expect(try reader.readPTPString() == "")
    #expect(reader.remaining == 0)
}

@Test func parsesDeviceInfo() throws {
    var writer = ByteWriter()
    writer.append(UInt16(100))
    writer.append(UInt32(0x11))
    writer.append(UInt16(100))
    writer.appendPTPString("Sony PTP Extensions")
    writer.append(UInt16(0))
    writer.appendArray([UInt16(0x1001), 0x1002, 0x9201])
    writer.appendArray([UInt16(0xC201)])
    writer.appendArray([UInt16]())
    writer.appendArray([UInt16]())
    writer.appendArray([UInt16(0x3801), 0xB101])
    writer.appendPTPString("Sony Corporation")
    writer.appendPTPString("ILCE-7M3")
    writer.appendPTPString("4.04")
    writer.appendPTPString("0000000012345678")

    let info = try DeviceInfo(parsing: writer.bytes)
    #expect(info.vendorExtensionID == 0x11)
    #expect(info.vendorExtensionDescription == "Sony PTP Extensions")
    #expect(info.operationsSupported == [0x1001, 0x1002, 0x9201])
    #expect(info.eventsSupported == [0xC201])
    #expect(info.imageFormats == [0x3801, 0xB101])
    #expect(info.model == "ILCE-7M3")
    #expect(info.deviceVersion == "4.04")
    #expect(info.serialNumber == "0000000012345678")
}

@Test func parsesObjectInfo() throws {
    var writer = ByteWriter()
    writer.append(UInt32(0x0001_0001))  // storage
    writer.append(UInt16(0x3801))       // JPEG
    writer.append(UInt16(0))
    writer.append(UInt32(8_000_000))
    writer.append(UInt16(0x3801))
    writer.append(UInt32(10_000))
    writer.append(UInt32(160))
    writer.append(UInt32(120))
    writer.append(UInt32(6000))
    writer.append(UInt32(4000))
    writer.append(UInt32(24))
    writer.append(UInt32(0))
    writer.append(UInt16(0))
    writer.append(UInt32(0))
    writer.append(UInt32(0))
    writer.appendPTPString("DSC01234.JPG")
    writer.appendPTPString("20261024T153000")

    let object = try ObjectInfo(parsing: writer.bytes)
    #expect(object.filename == "DSC01234.JPG")
    #expect(object.format == 0x3801)
    #expect(object.compressedSize == 8_000_000)
    #expect(object.imageWidth == 6000)
    #expect(object.captureDate == "20261024T153000")
}

@Test func codeNames() {
    #expect(PTPCode.event(0xC201) == "Sony ObjectAdded (0xC201)")
    #expect(PTPCode.response(0x2001) == "OK (0x2001)")
    #expect(PTPCode.operation(0x9999) == "0x9999")
}
