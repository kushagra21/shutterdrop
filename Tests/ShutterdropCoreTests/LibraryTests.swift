import Foundation
import Testing
@testable import ShutterdropCore

private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
}

private func photo(_ path: String, _ captured: Date?) -> Photo {
    Photo(url: URL(filePath: "/x/\(path)"), captured: captured)
}

@Test func previewTimestamp() {
    #expect(CameraTimestamp.fromPreviewName("pict261123_1338510000.JPG") == date(23, 13, 38, 51))
    #expect(CameraTimestamp.fromPreviewName("DSC01234.JPG") == nil)
}

@Test func ptpTimestamp() {
    #expect(CameraTimestamp.fromPTP("20261123T133851") == date(23, 13, 38, 51))
    #expect(CameraTimestamp.fromPTP("20261123T133851.0+0530") == date(23, 13, 38, 51))
    #expect(CameraTimestamp.fromPTP("") == nil)
}

@Test func matchesPreviewsToShots() {
    let previews = [
        photo("pict261123_1338510000.JPG", date(23, 13, 38, 51)),
        photo("pict261123_1338550000.JPG", date(23, 13, 38, 55)),
        photo("pict261123_1400000000.JPG", date(23, 14, 0, 0)),
    ]
    let originals = [
        photo("DSC00010.ARW", date(23, 13, 38, 52)),
        photo("DSC00010.JPG", date(23, 13, 38, 52)),
        photo("DSC00011.JPG", date(23, 13, 38, 55)),
        photo("DSC00012.JPG", date(23, 13, 50, 0)),
    ]
    let matches = ShotMatcher.match(previews: previews, originals: originals)
    #expect(matches.map { $0.originals.map(\.url.lastPathComponent) } == [
        ["DSC00010.ARW", "DSC00010.JPG"],
        ["DSC00011.JPG"],
        [],
    ])
}

@Test func burstWithinOneSecondPairsInOrder() {
    let second = date(23, 10, 0, 0)
    let previews = [photo("pict261123_1000000000.JPG", second), photo("pict261123_1000000001.JPG", second)]
    let originals = [photo("DSC00020.JPG", second), photo("DSC00021.JPG", second)]
    let matches = ShotMatcher.match(previews: previews, originals: originals)
    #expect(matches.map { $0.originals.map(\.url.lastPathComponent) } == [["DSC00020.JPG"], ["DSC00021.JPG"]])
}

@Test func libraryStoresAndFindsFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "shutterdrop-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = PhotoLibrary(root: root)

    let temporary = root.appending(path: "download.tmp")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: temporary)
    let preview = try library.addPreview(from: temporary, named: "pict261123_1338510000.JPG")
    #expect(preview.url.path.hasSuffix("2026-11-23/previews/pict261123_1338510000.JPG"))

    let captured = date(23, 13, 38, 52)
    let original = try library.addOriginal([9, 9, 9, 9], named: "DSC00010.JPG", captured: captured)
    #expect(original.url.path.hasSuffix("2026-11-23/originals/DSC00010.JPG"))
    #expect(library.hasOriginal(named: "DSC00010.JPG", size: 4, captured: captured))
    #expect(!library.hasOriginal(named: "DSC00010.JPG", size: 5, captured: captured))

    let day = library.dayFolder(captured)
    // Compare names: the temp folder sits behind a /var → /private/var symlink.
    #expect(library.previews(inDay: day).map(\.url.lastPathComponent) == [preview.url.lastPathComponent])
    #expect(library.previews(inDay: day).map(\.captured) == [preview.captured])
    #expect(library.originals(inDay: day).map(\.captured) == [captured])
}
