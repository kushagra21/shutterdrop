import Foundation
import Testing
@testable import ShutterdropCore

// Responses below are trimmed from a real A7 III (firmware 4.04) in Ctrl w/ Smartphone mode.

@Test func parsesPictureEvent() {
    let json = #"{"id":1,"result":[null,{"cameraStatus":"IDLE","type":"cameraStatus"},null,null,null,[{"type":"takePicture","takePictureUrl":["http://192.168.122.1:60152/pict261123_1338510000.JPG?%211234%21"]}],[],null]}"#
    let event = RemoteCamera.parseEvent(Data(json.utf8))
    #expect(event.cameraStatus == "IDLE")
    #expect(event.pictureURLs == [URL(string: "http://192.168.122.1:60152/pict261123_1338510000.JPG?%211234%21")!])
}

@Test func parsesEmptyEvent() {
    let json = #"{"id":1,"result":[null,null,null,null,null,[],[],null,null,null,[],null]}"#
    #expect(RemoteCamera.parseEvent(Data(json.utf8)) == RemoteCameraEvent())
}

@Test func parsesError() throws {
    let error = try #require(RemoteCamera.error(in: Data(#"{"error":[40401,""],"id":1}"#.utf8)))
    #expect(error.code == RemoteCameraError.cameraNotReady)
    #expect(RemoteCamera.error(in: Data(#"{"id":1,"result":[]}"#.utf8)) == nil)
}

@Test func findsEndpointInDeviceDescription() {
    let xml = "<av:X_ScalarWebAPI_Service><av:X_ScalarWebAPI_ServiceType>camera</av:X_ScalarWebAPI_ServiceType>"
        + "<av:X_ScalarWebAPI_ActionList_URL>http://192.168.122.1:10000/sony</av:X_ScalarWebAPI_ActionList_URL>"
    #expect(RemoteCamera.actionListURL(inDeviceDescription: xml) == URL(string: "http://192.168.122.1:10000/sony"))
    #expect(RemoteCamera.actionListURL(inDeviceDescription: "<root/>") == nil)
}
