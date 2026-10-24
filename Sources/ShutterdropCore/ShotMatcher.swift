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
