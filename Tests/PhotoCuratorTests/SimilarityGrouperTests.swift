import XCTest
@testable import PhotoCurator

final class SimilarityGrouperTests: XCTestCase {
    func testGroupsNearDuplicateHashesAndPreservesUserDecisions() {
        let root = URL(fileURLWithPath: "/fixtures")
        let baseHash = PerceptualHash(bits: 0xFF00_FF00_FF00_FF00, averageLuminance: 120, dynamicRange: 150)
        let nearbyHash = PerceptualHash(bits: 0xFF00_FF00_FF00_FF03, averageLuminance: 126, dynamicRange: 145)
        let unrelatedHash = PerceptualHash(bits: 0x00FF_00FF_00FF_00FF, averageLuminance: 120, dynamicRange: 150)
        let photos = [
            PhotoItem(url: root.appendingPathComponent("a.jpg"), decision: .keep, perceptualHash: baseHash),
            PhotoItem(url: root.appendingPathComponent("b.jpg"), decision: .reject, perceptualHash: nearbyHash),
            PhotoItem(url: root.appendingPathComponent("c.jpg"), perceptualHash: unrelatedHash),
        ]

        let grouped = SimilarityGrouper.assigningGroups(to: photos)

        XCTAssertEqual(SimilarityGrouper.groupCount(in: grouped), 1)
        XCTAssertEqual(SimilarityGrouper.groupedPhotoCount(in: grouped), 2)
        XCTAssertEqual(grouped[0].similarityGroup?.position, 1)
        XCTAssertEqual(grouped[1].similarityGroup?.position, 2)
        XCTAssertNil(grouped[2].similarityGroup)
        XCTAssertEqual(grouped[0].decision, .keep, "相似分组不能覆盖人工决定")
        XCTAssertEqual(grouped[1].decision, .reject, "相似分组不能覆盖人工决定")
    }

    func testDoesNotGroupFlatImagesOrLargeBrightnessDifferences() {
        let root = URL(fileURLWithPath: "/fixtures")
        let flat = PerceptualHash(bits: .max, averageLuminance: 5, dynamicRange: 4)
        let dark = PerceptualHash(bits: 0xFF00_FF00_FF00_FF00, averageLuminance: 30, dynamicRange: 100)
        let bright = PerceptualHash(bits: 0xFF00_FF00_FF00_FF00, averageLuminance: 190, dynamicRange: 100)
        let photos = [
            PhotoItem(url: root.appendingPathComponent("flat-a.jpg"), perceptualHash: flat),
            PhotoItem(url: root.appendingPathComponent("flat-b.jpg"), perceptualHash: flat),
            PhotoItem(url: root.appendingPathComponent("dark.jpg"), perceptualHash: dark),
            PhotoItem(url: root.appendingPathComponent("bright.jpg"), perceptualHash: bright),
        ]

        let grouped = SimilarityGrouper.assigningGroups(to: photos)

        XCTAssertEqual(SimilarityGrouper.groupCount(in: grouped), 0)
        XCTAssertTrue(grouped.allSatisfy { $0.similarityGroup == nil })
    }

    func testNearDuplicateChainsDoNotCreateOneTransitiveMegaGroup() {
        let root = URL(fileURLWithPath: "/fixtures")
        let photos = [
            PhotoItem(
                url: root.appendingPathComponent("a.jpg"),
                perceptualHash: PerceptualHash(bits: 0, averageLuminance: 100, dynamicRange: 100)
            ),
            PhotoItem(
                url: root.appendingPathComponent("b.jpg"),
                perceptualHash: PerceptualHash(bits: 1, averageLuminance: 100, dynamicRange: 100)
            ),
            PhotoItem(
                url: root.appendingPathComponent("c.jpg"),
                perceptualHash: PerceptualHash(bits: 3, averageLuminance: 100, dynamicRange: 100)
            ),
        ]

        let grouped = SimilarityGrouper.assigningGroups(to: photos, maximumHammingDistance: 1)

        XCTAssertEqual(grouped[0].similarityGroup?.count, 2)
        XCTAssertEqual(grouped[1].similarityGroup?.count, 2)
        XCTAssertNil(grouped[2].similarityGroup, "C 只接近 B、不接近代表 A，不能通过传递链并入大组")
    }

    func testNearDuplicateDifferencesAcrossAllFormerHashBandsAreNotMissed() {
        let root = URL(fileURLWithPath: "/fixtures")
        let photos = [
            PhotoItem(
                url: root.appendingPathComponent("a.jpg"),
                perceptualHash: PerceptualHash(bits: 0, averageLuminance: 100, dynamicRange: 100)
            ),
            PhotoItem(
                url: root.appendingPathComponent("b.jpg"),
                perceptualHash: PerceptualHash(
                    bits: 0x0001_0001_0001_0001,
                    averageLuminance: 100,
                    dynamicRange: 100
                )
            ),
        ]

        let grouped = SimilarityGrouper.assigningGroups(to: photos)

        XCTAssertEqual(grouped[0].similarityGroup?.count, 2)
        XCTAssertEqual(grouped[1].similarityGroup?.count, 2)
    }

    func testTemporallyCloseModerateHashDifferenceBecomesOneSceneFamily() {
        let root = URL(fileURLWithPath: "/fixtures")
        let start = Date(timeIntervalSince1970: 1_000)
        let moderateDifference = UInt64(0x0000_0000_0000_3FFF)
        let photos = [
            PhotoItem(
                url: root.appendingPathComponent("a.jpg"),
                captureDate: start,
                perceptualHash: PerceptualHash(bits: 0, averageLuminance: 100, dynamicRange: 100)
            ),
            PhotoItem(
                url: root.appendingPathComponent("b.jpg"),
                captureDate: start.addingTimeInterval(60),
                perceptualHash: PerceptualHash(bits: moderateDifference, averageLuminance: 108, dynamicRange: 100)
            ),
            PhotoItem(
                url: root.appendingPathComponent("c.jpg"),
                captureDate: start.addingTimeInterval(300),
                perceptualHash: PerceptualHash(bits: moderateDifference, averageLuminance: 108, dynamicRange: 100)
            ),
        ]

        let grouped = SimilarityGrouper.assigningGroups(to: photos)

        XCTAssertEqual(grouped[0].similarityGroup?.count, 2)
        XCTAssertEqual(grouped[1].similarityGroup?.count, 2)
        XCTAssertNil(grouped[2].similarityGroup, "相隔过久的中等相似照片不能只靠宽松阈值合并")
    }

    func testSameCaptureTimeCannotGroupVisuallyUnrelatedPhotos() {
        let root = URL(fileURLWithPath: "/fixtures")
        let captureDate = Date(timeIntervalSince1970: 1_000)
        let photos = [
            PhotoItem(
                url: root.appendingPathComponent("a.jpg"),
                captureDate: captureDate,
                perceptualHash: PerceptualHash(
                    bits: 0,
                    averageLuminance: 100,
                    dynamicRange: 100
                )
            ),
            PhotoItem(
                url: root.appendingPathComponent("b.jpg"),
                captureDate: captureDate,
                perceptualHash: PerceptualHash(
                    bits: .max,
                    averageLuminance: 100,
                    dynamicRange: 100
                )
            ),
        ]

        let grouped = SimilarityGrouper.assigningGroups(to: photos)

        XCTAssertTrue(
            grouped.allSatisfy { $0.similarityGroup == nil },
            "时间只能辅助画面相似判断，不能单独形成相似照片"
        )
    }
}
