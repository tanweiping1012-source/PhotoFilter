import CoreGraphics
import Foundation
import ImageIO

/// 仅在内存中保存的低清灰度图；用于本地相似度和技术风险分析，不写回原图或导出文件。
struct LuminanceRaster: Equatable, Sendable {
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
              let image = PhotoAnalysisPipeline.decodedImage(
                  for: url,
                  maximumPixelSize: sideLength
              ) else {
            return nil
        }
        return raster(from: image, sideLength: sideLength)
    }

    /// 从已解码的图片生成灰度栅格。
    ///
    /// - Parameter preservingAspectRatio: 感知指纹需要固定的正方形网格，因此默认拉伸为正方形；
    ///   清晰度分析必须保留长宽比，否则横竖方向的梯度会被人为放大或压缩。
    static func raster(
        from image: CGImage,
        sideLength: Int = 64,
        preservingAspectRatio: Bool = false
    ) -> LuminanceRaster? {
        guard sideLength > 0 else { return nil }

        let width: Int
        let height: Int
        if preservingAspectRatio, image.width > 0, image.height > 0 {
            let longestSide = max(image.width, image.height)
            let scale = min(1, Double(sideLength) / Double(longestSide))
            width = max(8, Int((Double(image.width) * scale).rounded()))
            height = max(8, Int((Double(image.height) * scale).rounded()))
        } else {
            width = sideLength
            height = sideLength
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        let pointer = data.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let row = pointer.advanced(by: y * bytesPerRow)
            pixels.append(contentsOf: UnsafeBufferPointer(start: row, count: width))
        }
        return LuminanceRaster(width: width, height: height, pixels: pixels)
    }
}
