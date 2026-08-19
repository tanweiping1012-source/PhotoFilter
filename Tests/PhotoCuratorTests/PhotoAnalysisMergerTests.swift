import XCTest
@testable import PhotoCurator

final class PhotoAnalysisMergerTests: XCTestCase {
    func testAnalysisMergePreservesUserDecisionAndCandidateGroups() {
        let url = URL(fileURLWithPath: "/fixtures/photo.jpg")
        let original = PhotoItem(
            url: url,
            decision: .keep,
            burstGroup: BurstGroupMembership(id: "burst-1", position: 1, count: 2),
            similarityGroup: SimilarityGroupMembership(id: "similar-1", position: 1, count: 2)
        )
        let hash = PerceptualHash(bits: 0xFF00_FF00_FF00_FF00, averageLuminance: 120, dynamicRange: 150)
        let quality = TechnicalQuality(
            sharpness: 320,
            dynamicRange: 150,
            shadowClippingRatio: 0,
            highlightClippingRatio: 0,
            risks: []
        )
        let result = PhotoAnalysisResult(
            photoID: original.id,
            captureDate: Date(timeIntervalSince1970: 1_000),
            perceptualHash: hash,
            technicalQuality: quality
        )

        let updated = PhotoAnalysisMerger.applying([result], to: [original])

        XCTAssertEqual(updated[0].decision, .keep)
        XCTAssertEqual(updated[0].burstGroup, original.burstGroup)
        XCTAssertEqual(updated[0].similarityGroup, original.similarityGroup)
        XCTAssertEqual(updated[0].captureDate, result.captureDate)
        XCTAssertEqual(updated[0].perceptualHash, hash)
        XCTAssertEqual(updated[0].technicalQuality, quality)
        XCTAssertEqual(updated[0].curationCategory, .scenery)
    }

    func testAnalysisDoesNotOverwriteUserAssignedCategory() {
        let original = PhotoItem(
            url: URL(fileURLWithPath: "/fixtures/person.jpg"),
            curationCategory: .scenery,
            isCurationCategoryUserAssigned: true
        )
        let result = PhotoAnalysisResult(
            photoID: original.id,
            captureDate: nil,
            perceptualHash: nil,
            technicalQuality: nil,
            curationCategory: .people
        )

        let updated = PhotoAnalysisMerger.applying(
            [result],
            to: [original]
        )

        XCTAssertEqual(updated[0].curationCategory, .scenery)
        XCTAssertTrue(updated[0].isCurationCategoryUserAssigned)
    }
}
