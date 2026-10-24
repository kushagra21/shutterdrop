/// The DeviceInfo dataset returned by GetDeviceInfo (PTP spec 5.5.1).
public struct DeviceInfo: Equatable, Sendable {
    public var standardVersion: UInt16
    public var vendorExtensionID: UInt32
    public var vendorExtensionVersion: UInt16
    public var vendorExtensionDescription: String
    public var functionalMode: UInt16
    public var operationsSupported: [UInt16]
    public var eventsSupported: [UInt16]
    public var devicePropertiesSupported: [UInt16]
    public var captureFormats: [UInt16]
    public var imageFormats: [UInt16]
    public var manufacturer: String
    public var model: String
    public var deviceVersion: String
    public var serialNumber: String

    public init(parsing bytes: [UInt8]) throws {
        var reader = ByteReader(bytes)
        standardVersion = try reader.read()
        vendorExtensionID = try reader.read()
        vendorExtensionVersion = try reader.read()
        vendorExtensionDescription = try reader.readPTPString()
        functionalMode = try reader.read()
        operationsSupported = try reader.readArray(UInt16.self)
        eventsSupported = try reader.readArray(UInt16.self)
        devicePropertiesSupported = try reader.readArray(UInt16.self)
        captureFormats = try reader.readArray(UInt16.self)
        imageFormats = try reader.readArray(UInt16.self)
        manufacturer = try reader.readPTPString()
        model = try reader.readPTPString()
        deviceVersion = try reader.readPTPString()
        serialNumber = try reader.readPTPString()
    }
}

/// The ObjectInfo dataset returned by GetObjectInfo (PTP spec 5.5.2).
public struct ObjectInfo: Equatable, Sendable {
    public var storageID: UInt32
    public var format: UInt16
    public var protectionStatus: UInt16
    public var compressedSize: UInt32
    public var thumbFormat: UInt16
    public var thumbCompressedSize: UInt32
    public var thumbWidth: UInt32
    public var thumbHeight: UInt32
    public var imageWidth: UInt32
    public var imageHeight: UInt32
    public var imageBitDepth: UInt32
    public var parentObject: UInt32
    public var associationType: UInt16
    public var associationDescription: UInt32
    public var sequenceNumber: UInt32
    public var filename: String
    public var captureDate: String

    public init(parsing bytes: [UInt8]) throws {
        var reader = ByteReader(bytes)
        storageID = try reader.read()
        format = try reader.read()
        protectionStatus = try reader.read()
        compressedSize = try reader.read()
        thumbFormat = try reader.read()
        thumbCompressedSize = try reader.read()
        thumbWidth = try reader.read()
        thumbHeight = try reader.read()
        imageWidth = try reader.read()
        imageHeight = try reader.read()
        imageBitDepth = try reader.read()
        parentObject = try reader.read()
        associationType = try reader.read()
        associationDescription = try reader.read()
        sequenceNumber = try reader.read()
        filename = try reader.readPTPString()
        captureDate = reader.remaining > 0 ? try reader.readPTPString() : ""
    }
}
