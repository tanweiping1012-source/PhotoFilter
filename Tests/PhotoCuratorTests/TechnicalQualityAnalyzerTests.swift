import XCTest
@testable import PhotoCurator

final class TechnicalQualityAnalyzerTests: XCTestCase {
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

        XCTAssertGreaterThan(quality.sharpness, 90)
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
