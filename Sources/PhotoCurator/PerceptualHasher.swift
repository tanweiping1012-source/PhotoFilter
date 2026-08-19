import Foundation

/// 将图片压缩为 8 × 8 灰度亮度指纹。该指纹只保存在运行内存，用于本地近重复比较。
struct PerceptualHash: Equatable, Hashable {
    let bits: UInt64
    let averageLuminance: UInt8
    let dynamicRange: UInt8

    func hammingDistance(to other: PerceptualHash) -> Int {
        (bits ^ other.bits).nonzeroBitCount
    }

    func isNearDuplicate(
        of other: PerceptualHash,
        maximumHammingDistance: Int,
        maximumAverageLuminanceDelta: Int
    ) -> Bool {
        abs(Int(averageLuminance) - Int(other.averageLuminance)) <= maximumAverageLuminanceDelta
            && hammingDistance(to: other) <= maximumHammingDistance
    }
}

enum PerceptualHasher {
    private static let sideLength = 8

    static func hash(for url: URL) -> PerceptualHash? {
        guard let raster = LuminanceThumbnailReader.raster(for: url) else { return nil }
        return hash(from: raster)
    }

    static func hash(from raster: LuminanceRaster) -> PerceptualHash? {
        guard raster.width >= sideLength,
              raster.height >= sideLength,
              raster.pixels.count == raster.width * raster.height else {
            return nil
        }

        var pixels: [UInt8] = []
        pixels.reserveCapacity(sideLength * sideLength)
        for targetY in 0..<sideLength {
            let startY = targetY * raster.height / sideLength
            let endY = (targetY + 1) * raster.height / sideLength
            for targetX in 0..<sideLength {
                let startX = targetX * raster.width / sideLength
                let endX = (targetX + 1) * raster.width / sideLength
                var total = 0
                var count = 0
                for sourceY in startY..<endY {
                    for sourceX in startX..<endX {
                        total += Int(raster.pixels[sourceY * raster.width + sourceX])
                        count += 1
                    }
                }
                pixels.append(UInt8(total / max(count, 1)))
            }
        }

        let pixelCount = pixels.count
        var total = 0
        var minimum = UInt8.max
        var maximum = UInt8.min

        for index in 0..<pixelCount {
            let pixel = pixels[index]
            total += Int(pixel)
            minimum = min(minimum, pixel)
            maximum = max(maximum, pixel)
        }

        let average = UInt8(total / pixelCount)
        var bits: UInt64 = 0
        for index in 0..<pixelCount where pixels[index] >= average {
            bits |= UInt64(1) << (pixelCount - 1 - index)
        }

        return PerceptualHash(
            bits: bits,
            averageLuminance: average,
            dynamicRange: maximum - minimum
        )
    }
}
