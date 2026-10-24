import Foundation

public struct ShotMatch: Equatable, Sendable {
    public var preview: Photo
    /// The full-size files of the same shot (e.g. JPEG and ARW); empty until imported.
    public var originals: [Photo]
}

/// Pairs live previews with the originals imported later, by camera time.
/// Previews only carry whole seconds, so in a burst within one second the
/// previews and shots are paired in order.
public enum ShotMatcher {
    public static func match(previews: [Photo], originals: [Photo], tolerance: TimeInterval = 2) -> [ShotMatch] {
        // One shot = all originals sharing a base name (DSC01234.JPG + DSC01234.ARW).
        let shots = Dictionary(grouping: originals.filter { $0.captured != nil }) {
            $0.url.deletingPathExtension().lastPathComponent
        }
        .values
        .map { files in (time: files.compactMap(\.captured).min()!, files: files.sorted { $0.url.path < $1.url.path }) }
        .sorted { ($0.time, $0.files[0].url.path) < ($1.time, $1.files[0].url.path) }

        var claimed = Set<Int>()
        return previews.sorted { ($0.captured ?? .distantPast, $0.url.path) < ($1.captured ?? .distantPast, $1.url.path) }
            .map { preview in
                guard let time = preview.captured else { return ShotMatch(preview: preview, originals: []) }
                let best = shots.indices
                    .filter { !claimed.contains($0) && abs(shots[$0].time.timeIntervalSince(time)) <= tolerance }
                    .min { abs(shots[$0].time.timeIntervalSince(time)) < abs(shots[$1].time.timeIntervalSince(time)) }
                guard let best else { return ShotMatch(preview: preview, originals: []) }
                claimed.insert(best)
                return ShotMatch(preview: preview, originals: shots[best].files)
            }
    }
}

/// One photograph as the app shows it: its live preview, its full-size
/// files, or both once matched.
public struct Shot: Identifiable, Equatable, Sendable {
    public var preview: Photo?
    public var originals: [Photo]

    /// The preview's path, else the first original's: stable across reloads.
    public var id: String { (preview ?? originals[0]).url.path }
    public var captured: Date? { preview?.captured ?? originals.compactMap(\.captured).min() }
    /// The best file to show: the preview if any, else an original (ImageIO reads ARW).
    public var displayURL: URL { (preview ?? originals[0]).url }
}

extension ShotMatcher {
    /// Every shot of a day, newest first: matched previews, previews still
    /// waiting for their originals, and originals imported without a preview.
    public static func shots(previews: [Photo], originals: [Photo]) -> [Shot] {
        let matches = match(previews: previews, originals: originals)
        let claimed = Set(matches.flatMap { $0.originals.map(\.url) })
        let unmatched = Dictionary(grouping: originals.filter { !claimed.contains($0.url) }) {
            $0.url.deletingPathExtension().lastPathComponent
        }
        let shots = matches.map { Shot(preview: $0.preview, originals: $0.originals) }
            + unmatched.values.map { Shot(preview: nil, originals: $0.sorted { $0.url.path < $1.url.path }) }
        return shots.sorted { ($0.captured ?? .distantPast, $0.id) > ($1.captured ?? .distantPast, $1.id) }
    }
}
