import AppKit
import ImageIO
import SwiftUI

/// Downsampled images via ImageIO, which also reads the JPEG preview embedded
/// in Sony ARW files. Cached per URL and size.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, maxPixels: Int) async -> NSImage? {
        let key = "\(maxPixels)|\(url.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let cgImage = await Self.decode(url, maxPixels: maxPixels) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }

    @concurrent
    private static func decode(_ url: URL, maxPixels: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// An image file shown at a given size, loaded off the main thread.
struct PhotoImage: View {
    let url: URL
    var maxPixels = 400
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            image = await ImageCache.shared.image(for: url, maxPixels: maxPixels)
        }
    }
}
