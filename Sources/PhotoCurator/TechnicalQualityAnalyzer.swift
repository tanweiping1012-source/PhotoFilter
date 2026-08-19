import Foundation

enum TechnicalRisk: Equatable {
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

struct TechnicalQuality: Equatable {
    let sharpness: Double
    let dynamicRange: UInt8
    let shadowClippingRatio: Double
    let highlightClippingRatio: Double
    let risks: [TechnicalRisk]

    var primaryRisk: TechnicalRisk? {
        risks.first
    }
}

enum TechnicalQualityAnalyzer {
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
        let sharpness = laplacianVariance(in: raster)

        var risks: [TechnicalRisk] = []
        if raster.dynamicRange < 28 {
            risks.append(.lowContrast)
        }
        if raster.dynamicRange >= 28, sharpness < 90 {
            risks.append(.lowSharpness)
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

    private static func laplacianVariance(in raster: LuminanceRaster) -> Double {
        guard raster.width >= 3, raster.height >= 3 else { return 0 }

        var values: [Double] = []
        values.reserveCapacity((raster.width - 2) * (raster.height - 2))
        for y in 1..<(raster.height - 1) {
            for x in 1..<(raster.width - 1) {
                let center = Double(raster.pixels[y * raster.width + x])
                let left = Double(raster.pixels[y * raster.width + x - 1])
                let right = Double(raster.pixels[y * raster.width + x + 1])
                let top = Double(raster.pixels[(y - 1) * raster.width + x])
                let bottom = Double(raster.pixels[(y + 1) * raster.width + x])
                values.append(4 * center - left - right - top - bottom)
            }
        }

        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }
}
