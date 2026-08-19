import CoreGraphics
import Foundation
import ImageIO

/// 仅在内存中保存的低清灰度图；用于本地相似度和技术风险分析，不写回原图或导出文件。
struct LuminanceRaster: Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    var dynamicRange: UInt8 {
        guard let minimum = pixels.min(), let maximum = pixels.max() else { return 0 }
        return maximum - minimum
    }
}

enum LuminanceThumbnailReader {
    static func raster(for url: URL, sideLength: Int = 64) -> LuminanceRaster? {
        guard sideLength > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: sideLength,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let context = CGContext(
                data: nil,
                width: sideLength,
                height: sideLength,
                bitsPerComponent: 8,
                bytesPerRow: sideLength,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ),
              let data = context.data else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: sideLength, height: sideLength))

        let pixelCount = sideLength * sideLength
        let pointer = data.assumingMemoryBound(to: UInt8.self)
        let pixels = Array(UnsafeBufferPointer(start: pointer, count: pixelCount))
        return LuminanceRaster(width: sideLength, height: sideLength, pixels: pixels)
    }
}
