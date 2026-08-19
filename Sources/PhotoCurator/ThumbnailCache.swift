import AppKit
import ImageIO

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlightLoads: [String: Task<CGImage?, Never>] = [:]

    private init() {
        cache.countLimit = 120
        cache.totalCostLimit = 96 * 1_024 * 1_024
    }

    func image(for url: URL, maximumPixelSize: Int = 360) async -> NSImage? {
        let keyString = "\(url.standardizedFileURL.path)|\(maximumPixelSize)"
        let key = keyString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let task: Task<CGImage?, Never>
        if let existingTask = inFlightLoads[keyString] {
            task = existingTask
        } else {
            task = Task.detached(priority: .utility) {
                Self.makeThumbnailCGImage(for: url, maximumPixelSize: maximumPixelSize)
            }
            inFlightLoads[keyString] = task
        }

        let image = await task.value
        inFlightLoads[keyString] = nil
        guard !Task.isCancelled, let image else { return nil }

        let thumbnail = NSImage(cgImage: image, size: .zero)
        let cost = max(1, image.bytesPerRow * image.height)
        cache.setObject(thumbnail, forKey: key, cost: cost)
        return thumbnail
    }

    func removeAll() {
        inFlightLoads.values.forEach { $0.cancel() }
        inFlightLoads.removeAll()
        cache.removeAllObjects()
    }

    nonisolated private static func makeThumbnailCGImage(
        for url: URL,
        maximumPixelSize: Int
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
