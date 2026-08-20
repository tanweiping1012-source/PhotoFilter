import XCTest
@testable import PhotoCurator

final class TechnicalQualityAnalyzerTests: XCTestCase {
    /// 单张照片的绝对边缘强度不能判定清晰度：细节少的干净画面不该被标成风险。
    func testSharpnessRiskIsNotAssignedFromASinglePhoto() {
        let softButCleanScene = LuminanceRaster(
            width: 32,
            height: 32,
            pixels: (0..<1024).map { UInt8(40 + ($0 / 32) * 5) }
        )

        let quality = TechnicalQualityAnalyzer.analyze(softButCleanScene)

        XCTAssertFalse(quality.risks.contains(.lowSharpness))
    }

    /// 同一相似家族里明显更糊的一张才提示清晰度风险。
    func testSharpnessRiskComesFromTheSimilarityFamilyReference() {
        let sharp = makePhoto(id: "sharp", sharpness: 4.0, groupID: "similar-1", position: 1)
        let alsoSharp = makePhoto(id: "also-sharp", sharpness: 3.6, groupID: "similar-1", position: 2)
        let blurred = makePhoto(id: "blurred", sharpness: 1.1, groupID: "similar-1", position: 3)

        let updated = TechnicalQualityAnalyzer.assigningSharpnessRisks(
            to: [sharp, alsoSharp, blurred]
        )

        XCTAssertFalse(updated[0].technicalQuality?.risks.contains(.lowSharpness) ?? true)
        XCTAssertFalse(updated[1].technicalQuality?.risks.contains(.lowSharpness) ?? true)
        XCTAssertTrue(updated[2].technicalQuality?.risks.contains(.lowSharpness) ?? false)
    }

    /// 低反差画面的边缘强度本来就低，不能再叠加一条清晰度风险。
    func testLowContrastPhotoIsNotAlsoFlaggedForSharpness() {
        let flat = makePhoto(id: "flat", sharpness: 0.1, groupID: nil, position: 0, dynamicRange: 10)
        let normal = makePhoto(id: "normal", sharpness: 3.0, groupID: nil, position: 0)

        let updated = TechnicalQualityAnalyzer.assigningSharpnessRisks(to: [flat, normal])

        XCTAssertFalse(updated[0].technicalQuality?.risks.contains(.lowSharpness) ?? true)
    }

    private func makePhoto(
        id: String,
        sharpness: Double,
        groupID: String?,
        position: Int,
        dynamicRange: UInt8 = 120
    ) -> PhotoItem {
        var photo = PhotoItem(
            url: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            technicalQuality: TechnicalQuality(
                sharpness: sharpness,
                dynamicRange: dynamicRange,
                shadowClippingRatio: 0,
                highlightClippingRatio: 0,
                risks: dynamicRange < 28 ? [.lowContrast] : []
            )
        )
        if let groupID {
            photo.similarityGroup = SimilarityGroupMembership(
                id: groupID,
                position: position,
                count: 3
            )
        }
        return photo
    }

    func testUniformImageIsFlaggedAsLowContrast() {
        let raster = LuminanceRaster(width: 8, height: 8, pixels: Array(repeating: 128, count: 64))

        let quality = TechnicalQualityAnalyzer.analyze(raster)

        XCTAssertEqual(quality.sharpness, 0)
        XCTAssertEqual(quality.risks, [.lowContrast])
    }

    func testCheckerboardIsNotFlaggedForSharpnessOrExposure() {
        let pixels = (0..<64).map { index in
            ((index / 8 + index % 8).isMultiple(of: 2)) ? UInt8(40) : UInt8(220)
        }
        let raster = LuminanceRaster(width: 8, height: 8, pixels: pixels)

        let quality = TechnicalQualityAnalyzer.analyze(raster)

        XCTAssertGreaterThan(quality.sharpness, 1)
        XCTAssertTrue(quality.risks.isEmpty)
    }

    func testSevereShadowAndHighlightClippingAreFlagged() {
        let darkPixels = Array(repeating: UInt8(0), count: 48) + Array(repeating: UInt8(128), count: 16)
        let brightPixels = Array(repeating: UInt8(255), count: 48) + Array(repeating: UInt8(128), count: 16)

        let darkQuality = TechnicalQualityAnalyzer.analyze(
            LuminanceRaster(width: 8, height: 8, pixels: darkPixels)
        )
        let brightQuality = TechnicalQualityAnalyzer.analyze(
            LuminanceRaster(width: 8, height: 8, pixels: brightPixels)
        )

        XCTAssertTrue(darkQuality.risks.contains(.heavyShadowClipping))
        XCTAssertTrue(brightQuality.risks.contains(.heavyHighlightClipping))
    }
}
