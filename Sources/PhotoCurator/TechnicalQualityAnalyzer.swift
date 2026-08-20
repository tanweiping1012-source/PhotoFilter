import Foundation

enum TechnicalRisk: Equatable, Sendable {
    case lowSharpness
    case lowContrast
    case heavyShadowClipping
    case heavyHighlightClipping

    var title: String {
        switch self {
        case .lowSharpness: String(localized: "清晰度风险")
        case .lowContrast: String(localized: "低反差")
        case .heavyShadowClipping: String(localized: "严重欠曝")
        case .heavyHighlightClipping: String(localized: "严重过曝")
        }
    }
}

struct TechnicalQuality: Equatable, Sendable {
    /// 按画面反差归一化后的边缘强度。数值只在同一批照片之间比较有意义，不是绝对画质分。
    let sharpness: Double
    let dynamicRange: UInt8
    let shadowClippingRatio: Double
    let highlightClippingRatio: Double
    let risks: [TechnicalRisk]

    var primaryRisk: TechnicalRisk? {
        risks.first
    }

    func withRisks(_ risks: [TechnicalRisk]) -> TechnicalQuality {
        TechnicalQuality(
            sharpness: sharpness,
            dynamicRange: dynamicRange,
            shadowClippingRatio: shadowClippingRatio,
            highlightClippingRatio: highlightClippingRatio,
            risks: risks
        )
    }
}

enum TechnicalQualityAnalyzer {
    /// 清晰度必须在足够大的栅格上评估：64px 缩略图已经把对焦信息滤掉，
    /// 剩下的只是“画面细节多不多”，会把干净的风景锐图误判为模糊。
    static let recommendedRasterSideLength = PhotoAnalysisPipeline.qualityPixelSize
    /// 低于同一相似家族参考值的这个比例才提示清晰度风险；单张照片的绝对边缘强度不足以下结论。
    static let lowSharpnessRatio = 0.55
    /// 没有相似家族时只能拿整库中位数当参考，而不同场景的细节量本来就差很多，
    /// 因此阈值必须更严，只提示明显落在最差一端的照片。
    static let lowSharpnessLibraryRatio = 0.35

    static func analyze(_ raster: LuminanceRaster) -> TechnicalQuality {
        let pixels = raster.pixels
        guard !pixels.isEmpty,
              pixels.count == raster.width * raster.height else {
            return TechnicalQuality(
                sharpness: 0,
                dynamicRange: 0,
                shadowClippingRatio: 0,
                highlightClippingRatio: 0,
                risks: []
            )
        }

        let shadows = Double(pixels.filter { $0 <= 8 }.count) / Double(pixels.count)
        let highlights = Double(pixels.filter { $0 >= 247 }.count) / Double(pixels.count)
        let sharpness = normalizedSharpness(in: raster)

        // 反差与曝光可以按绝对阈值判断；清晰度不行，它在 `assigningSharpnessRisks` 里按同组参考值判断。
        var risks: [TechnicalRisk] = []
        if raster.dynamicRange < 28 {
            risks.append(.lowContrast)
        }
        if shadows >= 0.35 {
            risks.append(.heavyShadowClipping)
        }
        if highlights >= 0.35 {
            risks.append(.heavyHighlightClipping)
        }

        return TechnicalQuality(
            sharpness: sharpness,
            dynamicRange: raster.dynamicRange,
            shadowClippingRatio: shadows,
            highlightClippingRatio: highlights,
            risks: risks
        )
    }

    /// 参与统计的最强边缘比例。
    ///
    /// 取“最强的一小撮边缘”而不是全局方差或某个固定分位：大片天空、纯色背景会把全局统计稀释掉，
    /// 而固定分位（例如 P90）在边缘稀疏的画面里会直接落进平坦区域，读数变成 0。
    static let edgeSampleRatio = 0.01
    private static let minimumEdgeSampleCount = 8

    /// 最强边缘的平均强度除以画面反差。
    ///
    /// 除以反差是为了让阴天低反差场景和晴天高反差场景可以放在一起比较。
    static func normalizedSharpness(in raster: LuminanceRaster) -> Double {
        guard raster.width >= 3, raster.height >= 3 else { return 0 }

        var magnitudes: [Double] = []
        magnitudes.reserveCapacity((raster.width - 2) * (raster.height - 2))
        for y in 1..<(raster.height - 1) {
            for x in 1..<(raster.width - 1) {
                let center = Double(raster.pixels[y * raster.width + x])
                let left = Double(raster.pixels[y * raster.width + x - 1])
                let right = Double(raster.pixels[y * raster.width + x + 1])
                let top = Double(raster.pixels[(y - 1) * raster.width + x])
                let bottom = Double(raster.pixels[(y + 1) * raster.width + x])
                magnitudes.append(abs(4 * center - left - right - top - bottom))
            }
        }

        guard !magnitudes.isEmpty else { return 0 }
        magnitudes.sort()
        let sampleCount = min(
            magnitudes.count,
            max(minimumEdgeSampleCount, Int(Double(magnitudes.count) * edgeSampleRatio))
        )
        let strongestEdges = magnitudes.suffix(sampleCount)
        let edgeStrength = strongestEdges.reduce(0, +) / Double(sampleCount)
        let contrast = max(8, Double(raster.dynamicRange))
        return edgeStrength / contrast
    }

    /// 清晰度风险只在同一批照片之间成立：先按相似家族取参考值，没有家族时退回整库参考值。
    ///
    /// 这样“同一个场景里明显更糊的那张”会被提示，而整张照片本身细节少（干净的海景、雪山）不会被误标。
    static func assigningSharpnessRisks(to photos: [PhotoItem]) -> [PhotoItem] {
        var updated = photos
        let libraryReference = referenceSharpness(
            in: photos.compactMap { $0.technicalQuality?.sharpness }
        )

        var sharpnessByGroup: [String: [Double]] = [:]
        for photo in photos {
            guard let groupID = photo.similarityGroup?.id,
                  let sharpness = photo.technicalQuality?.sharpness else { continue }
            sharpnessByGroup[groupID, default: []].append(sharpness)
        }
        let groupReference = sharpnessByGroup.compactMapValues { referenceSharpness(in: $0) }

        for index in updated.indices {
            guard let quality = updated[index].technicalQuality else { continue }
            var risks = quality.risks.filter { $0 != .lowSharpness }
            let familyReference = updated[index].similarityGroup
                .flatMap { groupReference[$0.id] }
            let reference = familyReference ?? libraryReference
            let ratio = familyReference == nil
                ? lowSharpnessLibraryRatio
                : lowSharpnessRatio
            if let reference,
               reference > 0,
               !risks.contains(.lowContrast),
               quality.sharpness < reference * ratio {
                risks.insert(.lowSharpness, at: 0)
            }
            updated[index].technicalQuality = quality.withRisks(risks)
        }
        return updated
    }

    /// 参考值取中位数：均值容易被一两张极端锐利或极端模糊的照片带偏。
    static func referenceSharpness(in values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
