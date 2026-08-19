import XCTest
@testable import PhotoCurator

final class LocalCandidateRankerTests: XCTestCase {
    func testRanksTechnicallyStrongerPhotoFirstAndPreservesUserDecisions() {
        let root = URL(fileURLWithPath: "/fixtures")
        let strong = makePhoto(
            url: root.appendingPathComponent("strong.jpg"),
            decision: .keep,
            sharpness: 520,
            range: 180,
            risks: []
        )
        let weak = makePhoto(
            url: root.appendingPathComponent("weak.jpg"),
            decision: .reject,
            sharpness: 70,
            range: 40,
            risks: [.lowSharpness, .heavyShadowClipping]
        )

        let ranked = LocalCandidateRanker.assigningRecommendations(to: [weak, strong])
        let rankedStrong = ranked.first { $0.filename == "strong.jpg" }
        let rankedWeak = ranked.first { $0.filename == "weak.jpg" }

        XCTAssertEqual(rankedStrong?.localRecommendations.first?.rank, 1)
        XCTAssertEqual(rankedWeak?.localRecommendations.first?.rank, 2)
        XCTAssertTrue(rankedStrong?.localRecommendations.first?.isTopCandidate == true)
        XCTAssertEqual(rankedStrong?.decision, .keep, "本地推荐不能覆盖人工决定")
        XCTAssertEqual(rankedWeak?.decision, .reject, "本地推荐不能覆盖人工决定")
    }

    func testRanksVisualSimilarityOnceEvenWhenLegacyTimeMetadataExists() {
        let root = URL(fileURLWithPath: "/fixtures")
        let photoA = makePhoto(
            url: root.appendingPathComponent("a.jpg"),
            sharpness: 350,
            range: 150,
            risks: [],
            burst: BurstGroupMembership(id: "burst-1", position: 1, count: 2),
            similarity: SimilarityGroupMembership(id: "similar-1", position: 1, count: 2)
        )
        let photoB = makePhoto(
            url: root.appendingPathComponent("b.jpg"),
            sharpness: 120,
            range: 70,
            risks: [.lowSharpness],
            burst: BurstGroupMembership(id: "burst-1", position: 2, count: 2),
            similarity: SimilarityGroupMembership(id: "similar-1", position: 2, count: 2)
        )

        let ranked = LocalCandidateRanker.assigningRecommendations(to: [photoA, photoB])

        XCTAssertEqual(ranked[0].localRecommendations.count, 1)
        XCTAssertTrue(ranked[0].localRecommendations.allSatisfy(\.isTopCandidate))
        XCTAssertEqual(ranked[1].localRecommendations.map(\.rank), [2])
    }

    func testIgnoresLegacyTimeOnlyGroup() {
        let root = URL(fileURLWithPath: "/fixtures")
        let photos = [
            makePhoto(
                url: root.appendingPathComponent("a.jpg"),
                sharpness: 350,
                range: 150,
                risks: [],
                burst: BurstGroupMembership(
                    id: "burst-legacy",
                    position: 1,
                    count: 2
                ),
                similarity: nil
            ),
            makePhoto(
                url: root.appendingPathComponent("b.jpg"),
                sharpness: 120,
                range: 70,
                risks: [],
                burst: BurstGroupMembership(
                    id: "burst-legacy",
                    position: 2,
                    count: 2
                ),
                similarity: nil
            ),
        ]

        let ranked = LocalCandidateRanker.assigningRecommendations(to: photos)

        XCTAssertTrue(ranked.allSatisfy { $0.localRecommendations.isEmpty })
    }

    private func makePhoto(
        url: URL,
        decision: PhotoDecision = .undecided,
        sharpness: Double,
        range: UInt8,
        risks: [TechnicalRisk],
        burst: BurstGroupMembership? = nil,
        similarity: SimilarityGroupMembership? = SimilarityGroupMembership(
            id: "similar-1",
            position: 1,
            count: 2
        )
    ) -> PhotoItem {
        PhotoItem(
            url: url,
            decision: decision,
            technicalQuality: TechnicalQuality(
                sharpness: sharpness,
                dynamicRange: range,
                shadowClippingRatio: risks.contains(.heavyShadowClipping) ? 0.5 : 0,
                highlightClippingRatio: risks.contains(.heavyHighlightClipping) ? 0.5 : 0,
                risks: risks
            ),
            burstGroup: burst,
            similarityGroup: similarity
        )
    }
}
