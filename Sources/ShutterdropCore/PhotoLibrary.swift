import Foundation

/// A shot as it lands on the Mac: a live preview or a full-size original.
public struct Photo: Equatable, Sendable {
    public var url: URL
    /// When the camera took it, by the camera's clock.
    public var captured: Date?
}

/// Where Shutterdrop keeps photos: `<root>/<yyyy-MM-dd>/previews` and
/// `<root>/<yyyy-MM-dd>/originals`, dated by the camera's clock.
/// An original's capture time is stored as its file modification date.
public struct PhotoLibrary: Sendable {
    public static let folderName = "Shutterdrop"

    public static var defaultRoot: URL {
        root(in: FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0])
    }

    /// The library for a folder the user picked: a `Shutterdrop` folder inside
    /// it, so day folders never spill into e.g. ~/Downloads. A pick that is
    /// already a `Shutterdrop` folder is used as is.
    public static func root(in chosen: URL) -> URL {
        chosen.lastPathComponent == folderName ? chosen : chosen.appending(path: folderName)
    }

    public let root: URL
    /// How deleted files go away: the Trash, so a mistake can be undone (tests delete outright).
    let discard: @Sendable (URL) throws -> Void

    public init(root: URL = defaultRoot) {
        self.init(root: root) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    }

    init(root: URL, discard: @escaping @Sendable (URL) throws -> Void) {
        self.root = root
        self.discard = discard
    }

    public func previewsFolder(for date: Date?) -> URL { dayFolder(date).appending(path: "previews") }
    public func originalsFolder(for date: Date?) -> URL { dayFolder(date).appending(path: "originals") }

    public func dayFolder(_ date: Date?) -> URL {
        guard let date else { return root.appending(path: "undated") }
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return root.appending(path: String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!))
    }

    /// Moves a downloaded postview into the library under its camera file name.
    public func addPreview(from temporary: URL, named name: String) throws -> Photo {
        let captured = CameraTimestamp.fromPreviewName(name)
        let destination = try prepare(previewsFolder(for: captured), name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return Photo(url: destination, captured: captured)
    }

    public func hasOriginal(named name: String, size: UInt32, captured: Date?) -> Bool {
        let url = originalsFolder(for: captured).appending(path: name)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value == UInt64(size)
    }

    public func addOriginal(_ bytes: [UInt8], named name: String, captured: Date?) throws -> Photo {
        let destination = try prepare(originalsFolder(for: captured), name)
        try Data(bytes).write(to: destination, options: .atomic)
        if let captured {
            try FileManager.default.setAttributes([.modificationDate: captured], ofItemAtPath: destination.path)
        }
        return Photo(url: destination, captured: captured)
    }

    /// Number of photo files and their total size, for "move existing photos?".
    public func contentsSummary() -> (files: Int, bytes: Int64) {
        var files = 0
        var bytes: Int64 = 0
        for day in days() {
            for photo in previews(inDay: day) + originals(inDay: day) {
                files += 1
                bytes += Int64((try? photo.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return (files, bytes)
    }

    /// Moves every day folder into `newRoot`, merging with days already there.
    /// Files that already exist at the destination are left in place, not
    /// overwritten. Returns how many files moved.
    @discardableResult
    public func moveContents(to newRoot: URL) throws -> Int {
        let source = root.standardizedFileURL.resolvingSymlinksInPath().path
        let destination = newRoot.standardizedFileURL.resolvingSymlinksInPath().path
        guard source != destination else { return 0 }
        // Only day folders move, so the new folder may sit inside the old one
        // (~/Downloads → ~/Downloads/Shutterdrop) but not inside a day.
        let insideADay = days().contains { day in
            let path = day.standardizedFileURL.resolvingSymlinksInPath().path
            return destination == path || destination.hasPrefix(path + "/")
        }
        guard !insideADay else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "The new folder is inside one of the day folders."])
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: newRoot, withIntermediateDirectories: true)
        var moved = 0
        for day in days() {
            let target = newRoot.appending(path: day.lastPathComponent)
            if !fileManager.fileExists(atPath: target.path) {
                let count = files(in: day.appending(path: "previews")).count + files(in: day.appending(path: "originals")).count
                try fileManager.moveItem(at: day, to: target)
                moved += count
                continue
            }
            for kind in ["previews", "originals"] {
                let folder = target.appending(path: kind)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                for file in files(in: day.appending(path: kind)) where !fileManager.fileExists(atPath: folder.appending(path: file.lastPathComponent).path) {
                    try fileManager.moveItem(at: file, to: folder.appending(path: file.lastPathComponent))
                    moved += 1
                }
            }
        }
        return moved
    }

    /// Day folders, newest first. Only folders Shutterdrop creates count
    /// (`yyyy-MM-dd` and `undated`), so a library inside e.g. ~/Downloads
    /// never shows, moves or deletes unrelated folders.
    public func days() -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return folders
            .filter { Self.isDayFolderName($0.lastPathComponent) && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func isDayFolderName(_ name: String) -> Bool {
        name == "undated" || name.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
    }

    /// Moves a shot's files (preview and originals) to the Trash.
    public func trash(_ shot: Shot) throws {
        for photo in [shot.preview].compactMap({ $0 }) + shot.originals {
            guard isInside(photo.url) else { continue }
            try discard(photo.url)
        }
    }

    /// Moves a whole day folder to the Trash; refuses anything that isn't one of this library's days.
    public func trashDay(_ day: URL) throws {
        guard days().map(\.standardizedFileURL).contains(day.standardizedFileURL) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "\(day.lastPathComponent) isn't a Shutterdrop day folder."])
        }
        try discard(day)
    }

    private func isInside(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }

    public func shots(inDay folder: URL) -> [Shot] {
        ShotMatcher.shots(previews: previews(inDay: folder), originals: originals(inDay: folder))
    }

    /// The date a day folder stands for (nil for "undated").
    public static func date(ofDay folder: URL) -> Date? {
        CameraTimestamp.fromPTP(folder.lastPathComponent.replacingOccurrences(of: "-", with: "") + "T000000")
    }

    public func previews(inDay folder: URL) -> [Photo] {
        files(in: folder.appending(path: "previews")).map { Photo(url: $0, captured: CameraTimestamp.fromPreviewName($0.lastPathComponent)) }
    }

    public func originals(inDay folder: URL) -> [Photo] {
        files(in: folder.appending(path: "originals")).map { url in
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return Photo(url: url, captured: modified)
        }
    }

    private func files(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Creates `folder` and returns the destination for `name`, replacing any existing file.
    private func prepare(_ folder: URL, _ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        return destination
    }
}

/// Camera timestamps carry no time zone; they are read as Mac local time.
public enum CameraTimestamp {
    /// Remote API postview names look like `pict261123_1338510000.JPG`:
    /// `pict<yyMMdd>_<HHmmss>` followed by four more digits.
    public static func fromPreviewName(_ name: String) -> Date? {
        guard let match = name.firstMatch(of: /pict(\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})/) else { return nil }
        return date(2000 + Int(match.1)!, Int(match.2)!, Int(match.3)!, Int(match.4)!, Int(match.5)!, Int(match.6)!)
    }

    /// PTP DateTime strings: `yyyyMMdd'T'HHmmss`, optionally followed by tenths or a zone (ignored).
    public static func fromPTP(_ text: String) -> Date? {
        guard let match = text.firstMatch(of: /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/) else { return nil }
        return date(Int(match.1)!, Int(match.2)!, Int(match.3)!, Int(match.4)!, Int(match.5)!, Int(match.6)!)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
    }
}
