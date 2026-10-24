/// PTP operation, response, event and object-format codes, standard and Sony-specific.
/// Sony codes follow libgphoto2's ptp.h.
public enum PTPCode {
    public enum Operation {
        public static let getDeviceInfo: UInt16 = 0x1001
        public static let openSession: UInt16 = 0x1002
        public static let closeSession: UInt16 = 0x1003
        public static let getStorageIDs: UInt16 = 0x1004
        public static let getObjectHandles: UInt16 = 0x1007
        public static let getObjectInfo: UInt16 = 0x1008
        public static let getObject: UInt16 = 0x1009
        public static let sonySDIOConnect: UInt16 = 0x9201
        public static let sonyGetSDIOExtDeviceInfo: UInt16 = 0x9202
    }

    public enum Response {
        public static let ok: UInt16 = 0x2001
    }

    public enum Event {
        public static let objectAdded: UInt16 = 0x4002
        public static let sonyObjectAdded: UInt16 = 0xC201
    }

    static let operationNames: [UInt16: String] = [
        0x1001: "GetDeviceInfo", 0x1002: "OpenSession", 0x1003: "CloseSession",
        0x1004: "GetStorageIDs", 0x1005: "GetStorageInfo", 0x1006: "GetNumObjects",
        0x1007: "GetObjectHandles", 0x1008: "GetObjectInfo", 0x1009: "GetObject",
        0x100A: "GetThumb", 0x100B: "DeleteObject", 0x100E: "InitiateCapture",
        0x1014: "GetDevicePropDesc", 0x1015: "GetDevicePropValue", 0x1016: "SetDevicePropValue",
        0x101B: "GetPartialObject",
        0x9201: "Sony SDIOConnect", 0x9202: "Sony GetSDIOGetExtDeviceInfo",
        0x9203: "Sony GetDevicePropDesc", 0x9204: "Sony GetDevicePropertyValue",
        0x9205: "Sony SetControlDeviceA", 0x9206: "Sony GetControlDeviceDesc",
        0x9207: "Sony SetControlDeviceB", 0x9209: "Sony GetAllDevicePropData",
    ]

    static let responseNames: [UInt16: String] = [
        0x2001: "OK", 0x2002: "GeneralError", 0x2003: "SessionNotOpen",
        0x2004: "InvalidTransactionID", 0x2005: "OperationNotSupported",
        0x2006: "ParameterNotSupported", 0x2007: "IncompleteTransfer",
        0x2008: "InvalidStorageID", 0x2009: "InvalidObjectHandle",
        0x2019: "DeviceBusy", 0x201D: "InvalidParameter", 0x201E: "SessionAlreadyOpen",
        0x201F: "TransactionCancelled",
    ]

    static let eventNames: [UInt16: String] = [
        0x4001: "CancelTransaction", 0x4002: "ObjectAdded", 0x4003: "ObjectRemoved",
        0x4004: "StoreAdded", 0x4005: "StoreRemoved", 0x4006: "DevicePropChanged",
        0x4007: "ObjectInfoChanged", 0x4008: "DeviceInfoChanged",
        0x4009: "RequestObjectTransfer", 0x400A: "StoreFull", 0x400C: "StorageInfoChanged",
        0x400D: "CaptureComplete",
        0xC201: "Sony ObjectAdded", 0xC202: "Sony ObjectRemoved", 0xC203: "Sony PropertyChanged",
    ]

    static let objectFormatNames: [UInt16: String] = [
        0x3000: "Undefined", 0x3001: "Association", 0x3801: "JPEG", 0x380D: "TIFF",
        0x300D: "MPEG", 0xB101: "Sony ARW", 0xB982: "MP4",
    ]

    public static func operation(_ code: UInt16) -> String { describe(code, operationNames) }
    public static func response(_ code: UInt16) -> String { describe(code, responseNames) }
    public static func event(_ code: UInt16) -> String { describe(code, eventNames) }
    public static func objectFormat(_ code: UInt16) -> String { describe(code, objectFormatNames) }

    public static func hex<T: FixedWidthInteger>(_ value: T) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }

    private static func describe(_ code: UInt16, _ names: [UInt16: String]) -> String {
        if let name = names[code] { "\(name) (\(hex(code)))" } else { hex(code) }
    }
}
