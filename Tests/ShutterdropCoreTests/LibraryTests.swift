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
    #expect(library.originalKeys() == ["DSC00010.JPG|4"])

    let day = library.dayFolder(captured)
    // Compare names: the temp folder sits behind a /var → /private/var symlink.
    #expect(library.previews(inDay: day).map(\.url.lastPathComponent) == [preview.url.lastPathComponent])
    #expect(library.previews(inDay: day).map(\.captured) == [preview.captured])
    #expect(library.originals(inDay: day).map(\.captured) == [captured])
}

@Test func groupsShotsNewestFirst() {
    let previews = [
        photo("pict261123_1338510000.JPG", date(23, 13, 38, 51)),
        photo("pict261123_1400000000.JPG", date(23, 14, 0, 0)),
    ]
    let originals = [
        photo("DSC00010.ARW", date(23, 13, 38, 52)),
        photo("DSC00010.JPG", date(23, 13, 38, 52)),
        photo("DSC00012.ARW", date(23, 13, 50, 0)),
    ]
    let shots = ShotMatcher.shots(previews: previews, originals: originals)
    #expect(shots.map(\.displayURL.lastPathComponent) == [
        "pict261123_1400000000.JPG",  // preview still waiting for its original
        "DSC00012.ARW",               // original imported without a preview
        "pict261123_1338510000.JPG",  // matched
    ])
    #expect(shots[0].originals.isEmpty)
    #expect(shots[1].preview == nil)
    #expect(shots[2].originals.map(\.url.lastPathComponent) == ["DSC00010.ARW", "DSC00010.JPG"])
}

@Test func previewLagsBehindShot() {
    // Real pairs from the A7 III: previews are named 1-2 s after the capture.
    let previews = [
        photo("pict261024_1415470000.JPG", date(24, 14, 15, 47)),
        photo("pict261024_1416460000.JPG", date(24, 14, 16, 46)),
    ]
    let originals = [
        photo("DSC04662.JPG", date(24, 14, 15, 46)),
        photo("DSC04664.JPG", date(24, 14, 16, 44)),
        photo("DSC04699.JPG", date(24, 14, 16, 49)),  // 3 s after the preview: a later shot
    ]
    let matches = ShotMatcher.match(previews: previews, originals: originals)
    #expect(matches.map { $0.originals.map(\.url.lastPathComponent) } == [["DSC04662.JPG"], ["DSC04664.JPG"]])
}

@Test func movesLibraryAndMergesDays() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "shutterdrop-move-\(UUID())")
    defer { try? FileManager.default.removeItem(at: base) }
    let old = PhotoLibrary(root: base.appending(path: "old"))
    let new = PhotoLibrary(root: base.appending(path: "new"))
    let day1 = date(23, 10, 0, 0)
    let day2 = date(24, 10, 0, 0)
    _ = try old.addOriginal([1], named: "A.JPG", captured: day1)
    _ = try old.addOriginal([2], named: "B.JPG", captured: day2)
    _ = try old.addOriginal([3], named: "C.JPG", captured: day2)
    _ = try new.addOriginal([9], named: "C.JPG", captured: day2)  // already there: kept as is

    #expect(old.contentsSummary().files == 3)
    #expect(try old.moveContents(to: new.root) == 2)
    #expect(new.originals(inDay: new.dayFolder(day1)).map(\.url.lastPathComponent) == ["A.JPG"])
    #expect(new.originals(inDay: new.dayFolder(day2)).map(\.url.lastPathComponent) == ["B.JPG", "C.JPG"])
    #expect(try Data(contentsOf: new.dayFolder(day2).appending(path: "originals/C.JPG")) == Data([9]))
    #expect(throws: (any Error).self) { try new.moveContents(to: new.dayFolder(day1).appending(path: "inside")) }
}

@Test func libraryLivesInShutterdropFolder() {
    #expect(PhotoLibrary.root(in: URL(filePath: "/Users/x/Downloads")).path == "/Users/x/Downloads/Shutterdrop")
    #expect(PhotoLibrary.root(in: URL(filePath: "/Users/x/Pictures/Shutterdrop")).path == "/Users/x/Pictures/Shutterdrop")
    #expect(PhotoLibrary.defaultRoot.lastPathComponent == "Shutterdrop")
}

@Test func movesDaysIntoSubfolder() throws {
    // Upgrading a library kept directly in ~/Downloads into ~/Downloads/Shutterdrop.
    let base = FileManager.default.temporaryDirectory.appending(path: "shutterdrop-sub-\(UUID())")
    defer { try? FileManager.default.removeItem(at: base) }
    let old = PhotoLibrary(root: base)
    _ = try old.addOriginal([1], named: "A.JPG", captured: date(23, 10, 0, 0))
    try FileManager.default.createDirectory(at: base.appending(path: "Apps"), withIntermediateDirectories: true)
    let new = PhotoLibrary(root: PhotoLibrary.root(in: base))
    #expect(try old.moveContents(to: new.root) == 1)
    #expect(new.days().map(\.lastPathComponent) == ["2026-11-23"])
    #expect(old.days().isEmpty)
    #expect(FileManager.default.fileExists(atPath: base.appending(path: "Apps").path))
}

@Test func onlyShutterdropDayFoldersCount() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "shutterdrop-days-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = PhotoLibrary(root: root) { try FileManager.default.removeItem(at: $0) }
    for name in ["2026-10-24", "undated", "2023-11 – Banjara", "Apps", "Sony Camera Update v4.04"] {
        try FileManager.default.createDirectory(at: root.appending(path: name), withIntermediateDirectories: true)
    }
    try Data().write(to: root.appending(path: "2026-10-25"))  // a file, not a folder
    #expect(library.days().map(\.lastPathComponent) == ["undated", "2026-10-24"])
    #expect(throws: (any Error).self) { try library.trashDay(root.appending(path: "Apps")) }
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "Apps").path))
}

@Test func trashesShotFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "shutterdrop-trash-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    // Delete outright instead of filling the real Trash.
    let library = PhotoLibrary(root: root) { try FileManager.default.removeItem(at: $0) }
    let captured = date(23, 13, 38, 52)
    let keep = try library.addOriginal([1], named: "DSC00001.JPG", captured: captured)
    let gone = try library.addOriginal([2], named: "DSC00002.JPG", captured: captured)
    try library.trash(Shot(preview: nil, originals: [gone]))
    #expect(!FileManager.default.fileExists(atPath: gone.url.path))
    #expect(FileManager.default.fileExists(atPath: keep.url.path))
}

@Test func shiftsWrongCameraClock() throws {
    // Shots taken while the camera clock was 30 days fast, moved back to the real day.
    let root = FileManager.default.temporaryDirectory.appending(path: "shutterdrop-shift-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let library = PhotoLibrary(root: root) { try FileManager.default.removeItem(at: $0) }
    let wrongDay = library.dayFolder(date(23, 13, 38, 51))

    let temporary = root.appending(path: "download.tmp")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([1]).write(to: temporary)
    _ = try library.addPreview(from: temporary, named: "pict261123_1338510000.JPG")
    _ = try library.addOriginal([2, 2], named: "DSC00010.ARW", captured: date(23, 13, 38, 50))

    let offset = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 13, minute: 29, second: 50))!
        .timeIntervalSince(date(23, 13, 38, 50))
    let shots = library.shots(inDay: wrongDay)
    #expect(try library.shiftDates(of: shots, by: offset) == 2)

    #expect(!FileManager.default.fileExists(atPath: wrongDay.path))  // emptied and removed
    let rightDay = root.appending(path: "2026-10-24")
    let fixed = library.shots(inDay: rightDay)
    #expect(fixed.count == 1)
    #expect(fixed[0].preview?.url.lastPathComponent == "pict261024_1329510000.JPG")
    #expect(fixed[0].originals.map(\.url.lastPathComponent) == ["DSC00010.ARW"])
    #expect(fixed[0].originals[0].captured == Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 13, minute: 29, second: 50)))
    // A later import still recognises the file although the card says 23 Nov.
    #expect(library.originalKeys().contains("DSC00010.ARW|2"))
}
