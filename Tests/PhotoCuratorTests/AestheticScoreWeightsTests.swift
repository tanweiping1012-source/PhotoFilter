import Foundation
import XCTest
@testable import PhotoCurator

final class AestheticScoreWeightsTests: XCTestCase {
    /// 同样的维度分配同样的权重，必须永远得到同一个总分。
    /// 这正是把总分从模型手里收回本地要换来的东西。
    func testTotalIsDeterministicForTheSameInput() {
        let dimensions = AestheticScoreDimensions(
            moment: 74,
            composition: 81,
            subject: 68,
            lighting: 90,
            storytelling: 77
        )
        let weights = AestheticScoreWeights(
            moment: 5,
            composition: 2,
            subject: 4,
            lighting: 1,
            storytelling: 3
        )
        let first = AestheticScoreTotal.total(dimensions: dimensions, weights: weights)

        for _ in 0..<100 {
            XCTAssertEqual(
                AestheticScoreTotal.total(dimensions: dimensions, weights: weights),
                first
            )
        }
    }

    /// 五维取同一个值时，加权平均在任何权重下都等于该值。
    func testUniformDimensionsGiveTheSameTotalUnderAnyWeights() {
        let dimensions = AestheticScoreDimensions(
            moment: 73,
            composition: 73,
            subject: 73,
            lighting: 73,
            storytelling: 73
        )
        let candidates: [AestheticScoreWeights] = [
            .balanced,
            AestheticScoreWeights(moment: 5, composition: 0, subject: 0, lighting: 0, storytelling: 0),
            AestheticScoreWeights(moment: 1, composition: 2, subject: 3, lighting: 4, storytelling: 5),
            AestheticScoreWeights(moment: 0, composition: 0, subject: 0, lighting: 0, storytelling: 1),
        ]

        for weights in candidates {
            XCTAssertEqual(
                AestheticScoreTotal.total(dimensions: dimensions, weights: weights),
                73
            )
        }
    }

    /// 权重必须真的改变排序，否则这个功能只是装饰。
    func testWeightsChangeWhichPhotoRanksFirst() throws {
        let sharpButFlat = AestheticScoreDimensions(
            moment: 60,
            composition: 92,
            subject: 90,
            lighting: 92,
            storytelling: 55
        )
        let tellingButRough = AestheticScoreDimensions(
            moment: 92,
            composition: 62,
            subject: 65,
            lighting: 60,
            storytelling: 95
        )
        let scores = [
            AIFinalSelectionScore(photoID: "flat", dimensions: sharpButFlat),
            AIFinalSelectionScore(photoID: "telling", dimensions: tellingButRough),
        ]
        let candidateIDs = Set(scores.map(\.photoID))

        let favoursCraft = AestheticScoreWeights(
            moment: 0,
            composition: 5,
            subject: 5,
            lighting: 5,
            storytelling: 0
        )
        let favoursStory = AestheticScoreWeights(
            moment: 5,
            composition: 0,
            subject: 0,
            lighting: 0,
            storytelling: 5
        )

        XCTAssertEqual(
            try AIFinalSelectionRunValidator.rankedCandidatePhotoIDs(
                scores: scores,
                candidatePhotoIDs: candidateIDs,
                weights: favoursCraft
            ),
            ["flat", "telling"]
        )
        XCTAssertEqual(
            try AIFinalSelectionRunValidator.rankedCandidatePhotoIDs(
                scores: scores,
                candidatePhotoIDs: candidateIDs,
                weights: favoursStory
            ),
            ["telling", "flat"]
        )
    }

    /// 权重全被拉到 0 时不能除以 0，也不能把所有照片显示成 0 分。
    func testAllZeroWeightsFallBackToEqualWeighting() {
        let dimensions = AestheticScoreDimensions(
            moment: 70,
            composition: 80,
            subject: 90,
            lighting: 60,
            storytelling: 50
        )
        let zeroed = AestheticScoreWeights(
            moment: 0,
            composition: 0,
            subject: 0,
            lighting: 0,
            storytelling: 0
        )

        XCTAssertTrue(zeroed.isDegenerate)
        XCTAssertEqual(
            AestheticScoreTotal.total(dimensions: dimensions, weights: zeroed),
            AestheticScoreTotal.total(dimensions: dimensions, weights: .balanced)
        )
    }

    /// 半分必须向上进位，且全程用整数运算，不受浮点表示影响。
    func testHalfValuesRoundUp() {
        let dimensions = AestheticScoreDimensions(
            moment: 80,
            composition: 81,
            subject: 0,
            lighting: 0,
            storytelling: 0
        )
        let weights = AestheticScoreWeights(
            moment: 1,
            composition: 1,
            subject: 0,
            lighting: 0,
            storytelling: 0
        )

        // (80 + 81) / 2 = 80.5
        XCTAssertEqual(
            AestheticScoreTotal.total(dimensions: dimensions, weights: weights),
            81
        )
    }

    func testWeightsAreClampedOnInitAndOnDecode() throws {
        let clamped = AestheticScoreWeights(
            moment: 99,
            composition: -4,
            subject: 3,
            lighting: 5,
            storytelling: 0
        )
        XCTAssertEqual(clamped.moment, AestheticScoreWeights.maximumWeight)
        XCTAssertEqual(clamped.composition, AestheticScoreWeights.minimumWeight)

        let raw = Data(
            #"{"moment":42,"composition":-7,"subject":2,"lighting":1,"storytelling":3}"#
                .utf8
        )
        let decoded = try JSONDecoder().decode(AestheticScoreWeights.self, from: raw)
        XCTAssertEqual(decoded.moment, AestheticScoreWeights.maximumWeight)
        XCTAssertEqual(decoded.composition, AestheticScoreWeights.minimumWeight)
        XCTAssertEqual(decoded.subject, 2)
    }

    func testSettingOneDimensionLeavesTheOthersUntouched() {
        let updated = AestheticScoreWeights.balanced.setting(0, for: .lighting)

        XCTAssertEqual(updated.lighting, 0)
        XCTAssertEqual(updated.moment, AestheticScoreWeights.balanced.moment)
        XCTAssertEqual(updated.storytelling, AestheticScoreWeights.balanced.storytelling)
        for dimension in AestheticScoreDimension.allCases {
            XCTAssertEqual(
                updated.weight(for: dimension),
                dimension == .lighting ? 0 : 3
            )
        }
    }

    func testWeightsSurviveAStoreRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "weights-round-trip"))
        defaults.removePersistentDomain(forName: "weights-round-trip")
        defer { defaults.removePersistentDomain(forName: "weights-round-trip") }

        XCTAssertEqual(AestheticScoreWeightsStore.load(defaults: defaults), .balanced)

        let custom = AestheticScoreWeights(
            moment: 5,
            composition: 1,
            subject: 4,
            lighting: 0,
            storytelling: 2
        )
        AestheticScoreWeightsStore.save(custom, defaults: defaults)

        XCTAssertEqual(AestheticScoreWeightsStore.load(defaults: defaults), custom)
    }

    /// 权重变化不得改动任何已经保存的评分数据——它只是换一种看法。
    func testChangingWeightsDoesNotMutateStoredDimensions() {
        let dimensions = AestheticScoreDimensions(
            moment: 88,
            composition: 71,
            subject: 79,
            lighting: 64,
            storytelling: 93
        )
        let recommendation = AestheticRecommendation(
            scope: AestheticReviewScope(kind: .finalSelection, groupID: "window-1"),
            dimensions: dimensions,
            reasons: ["瞬间抓得准"],
            summary: "瞬间和叙事突出，光线偏弱。"
        )

        let first = recommendation.total(with: .balanced)
        let second = recommendation.total(
            with: AestheticScoreWeights(
                moment: 5,
                composition: 0,
                subject: 0,
                lighting: 0,
                storytelling: 5
            )
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(recommendation.dimensions, dimensions)
    }
}
