import Testing
@testable import SSDP

@Test func parsesNotify() throws {
    let text = "NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nNT: urn:microsoft-com:service:MtpNullService:1\r\n"
        + "NTS: ssdp:alive\r\nLocation: http://192.168.0.50:1900/\r\nServer: UPnP/1.0 SonyImagingDevice/1.0\r\n\r\n"
    let message = try #require(SSDPMessage.parse(text, sender: "192.168.0.50"))
    #expect(message.kind == .notify)
    #expect(message.headers["LOCATION"] == "http://192.168.0.50:1900/")
    #expect(message.headers["NT"] == "urn:microsoft-com:service:MtpNullService:1")
    #expect(message.looksLikeSonyCamera)
}

@Test func parsesSearchResponseWithBareNewlines() throws {
    let text = "HTTP/1.1 200 OK\nST: upnp:rootdevice\nSERVER: Linux/5.10 UPnP/1.0 MiniUPnPd/2.2\n\n"
    let message = try #require(SSDPMessage.parse(text, sender: "192.168.0.1"))
    #expect(message.kind == .response)
    #expect(message.headers["ST"] == "upnp:rootdevice")
    #expect(!message.looksLikeSonyCamera)
}

@Test func sonyTVIsNotACamera() throws {
    let text = "HTTP/1.1 200 OK\r\nST: uuid:NFANDROID2-PRV-SONYANDROIDTV2024BF1-SONY=BRAVIA=BF1-0000\r\n"
        + "SERVER: Linux/5.4, UPnP/1.0, Portable SDK for UPnP devices\r\n\r\n"
    let message = try #require(SSDPMessage.parse(text, sender: "192.168.0.236"))
    #expect(message.mentionsSony)
    #expect(!message.looksLikeSonyCamera)
}

@Test func rejectsEmpty() {
    #expect(SSDPMessage.parse("\r\n", sender: "1.2.3.4") == nil)
}
