import Foundation
import XCTest
@testable import PhotoCurator

final class AIFinalSelectionRunTests: XCTestCase {
    func testFortyEightCandidatesUseMaximumSizedTransferWindows() throws {
        let ids = (1...48).map { "photo-\($0)" }

        let plan = try AIFinalSelectionRunPlanner.makePlan(
            candidateLocalPhotoIDs: ids,
            targetWinnerCount: 12
        )

        XCTAssertEqual(plan.requestCount, 10)
        XCTAssertEqual(plan.groups.map(\.photoCount), Array(repeating: 5, count: 9) + [3])
        XCTAssertEqual(plan.coveredPhotoIDs, Set(ids))
        XCTAssertEqual(plan.transmittedPhotoCount, 48)
        XCTAssertEqual(plan.targetWinnerCount, 12)
        // 请求间隔从固定 60 秒降到 4 秒后，48 张候选的最短耗时从约 9 分钟降到 1 分钟以内。
        XCTAssertEqual(plan.estimatedMinimumMinutes, 1)
        XCTAssertTrue(plan.groups.allSatisfy { $0.scope.kind == .finalSelection })
    }

    func testTransferWindowsAvoidSinglePhotoTail() throws {
        let ids = (1...38).map { "photo-\($0)" }

        let plan = try AIFinalSelectionRunPlanner.makePlan(
            candidateLocalPhotoIDs: ids,
            targetWinnerCount: 10
        )

        XCTAssertEqual(plan.groups.map(\.photoCount), [5, 5, 5, 5, 5, 5, 5, 3])
        XCTAssertTrue(plan.groups.allSatisfy { (2...5).contains($0.photoCount) })
        XCTAssertEqual(plan.coveredPhotoIDs, Set(ids))
        XCTAssertEqual(plan.photoRange(forGroupAt: 0), 1...5)
        XCTAssertEqual(plan.photoRange(forGroupAt: 6), 31...35)
        XCTAssertEqual(plan.photoRange(forGroupAt: 7), 36...38)
        XCTAssertNil(plan.photoRange(forGroupAt: 8))
    }

    func testPlannerCarriesOneCategoryAcrossEveryTransferWindow() throws {
        let plan = try AIFinalSelectionRunPlanner.makePlan(
            candidateLocalPhotoIDs: (1...8).map {
                "person-\($0)"
            },
            targetWinnerCount: 2,
            category: .people
        )

        XCTAssertTrue(
            plan.groups.allSatisfy {
                $0.scope.category == .people
            }
        )
        XCTAssertFalse(
            plan.groups.contains {
                $0.scope.category == .scenery
            }
        )
    }

    func testRunProgressUsesCompletedPhotosInsteadOfRequestCount() {
        let progress = AIFinalSelectionRunProgress(
            phase: .running,
            completedBatchCount: 1,
            totalBatchCount: 2,
            completedPhotoCount: 5,
            candidatePhotoCount: 8,
            targetWinnerCount: 4
        )

        XCTAssertEqual(progress.fractionCompleted, 0.625)
    }

    /// 候选多于或少于目标都不该拦住用户：候选多只是挑选空间更大，
    /// 候选少则最多选出候选那么多张。旧实现要求候选达到目标的 2 倍，
    /// 结果是"目标从 8 调到 9"就让开始按钮整个消失。
    func testPlannerAcceptsAnyCandidateToTargetRatio() throws {
        // 候选少于目标的两倍：允许，目标按实际可得数量收敛。
        let tightPlan = try AIFinalSelectionRunPlanner.makePlan(
            candidateLocalPhotoIDs: (1...16).map { "photo-\($0)" },
            targetWinnerCount: 9
        )
        XCTAssertEqual(tightPlan.candidatePhotoCount, 16)
        XCTAssertEqual(tightPlan.targetWinnerCount, 9)

        // 候选少于目标：允许，最终最多只能选出候选那么多张。
        let scarcePlan = try AIFinalSelectionRunPlanner.makePlan(
            candidateLocalPhotoIDs: (1...3).map { "photo-\($0)" },
            targetWinnerCount: 10
        )
        XCTAssertEqual(scarcePlan.candidatePhotoCount, 3)
        XCTAssertEqual(scarcePlan.targetWinnerCount, 3)

        // 候选远多于目标：允许，AI 的挑选空间更大而已。
        let wide = try AIFinalSelectionRunPlanner.makePlan(
            candidateLocalPhotoIDs: (1...13).map { "photo-\($0)" },
            targetWinnerCount: 2
        )
        XCTAssertEqual(wide.candidatePhotoCount, 13)
        XCTAssertEqual(wide.targetWinnerCount, 2)

        // 仍然拒绝真正无意义的输入。两种"空"指向两种不同的操作，必须分开报告。
        XCTAssertThrowsError(
            try AIFinalSelectionRunPlanner.makePlan(
                candidateLocalPhotoIDs: [],
                targetWinnerCount: 3
            )
        ) { error in
            XCTAssertEqual(error as? AIFinalSelectionRunPlanError, .emptyCandidatePool)
        }
        XCTAssertThrowsError(
            try AIFinalSelectionRunPlanner.makePlan(
                candidateLocalPhotoIDs: ["photo-1"],
                targetWinnerCount: 0
            )
        ) { error in
            XCTAssertEqual(error as? AIFinalSelectionRunPlanError, .emptyTarget)
        }
        XCTAssertThrowsError(
            try AIFinalSelectionRunPlanner.makePlan(
                candidateLocalPhotoIDs: ["photo-1", "photo-1"],
                targetWinnerCount: 1
            )
        ) { error in
            XCTAssertEqual(error as? AIFinalSelectionRunPlanError, .duplicateCandidateID)
        }
    }

    /// 候选少于目标时，跑完之后也不能因为"凑不满目标"而作废整轮结果。
    func testFinalSelectionReturnsWhatIsAvailableWhenCandidatesRunShort() throws {
        let ranked = ["photo-1", "photo-2", "photo-3"]

        let selection = try AIFinalSelectionRunValidator.finalSelectionIDs(
            rankedCandidatePhotoIDs: ranked,
            lockedKeeperPhotoIDs: ["keeper-1"],
            candidatePhotoIDs: Set(ranked),
            targetSelectionCount: 10
        )

        XCTAssertEqual(selection, Set(ranked + ["keeper-1"]))
    }

    func testValidatedScoresMapBackToLocalPhotoIDsWithoutRankingRequest() throws {
        let scope = AestheticReviewScope(
            kind: .finalSelection,
            groupID: "ai-score-window-001"
        )
        let localIDs = ["local-a", "local-b"]
        let request = AestheticReviewRequestBuilder.make(
            scope: scope,
            localPhotoIDs: localIDs,
            requestID: "request-final"
        )
        let response = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: "request-final",
            scope: scope,
            reviews: [
                makeEntry(photoID: "photo_001", score: 80),
                makeEntry(photoID: "photo_002", score: 92),
            ]
        )

        XCTAssertEqual(
            try AIFinalSelectionRunValidator.scoredPhotos(
                from: response,
                request: request,
                localPhotoIDs: localIDs
            ).map(\.photoID),
            localIDs
        )
    }

    func testGlobalRankingIgnoresTransferWindowBoundaries() throws {
        let scores = [
            score("window-1-a", 72),
            score("window-1-b", 94),
            score("window-2-a", 88),
            score("window-2-b", 81),
        ]
        let candidateIDs = Set(scores.map(\.photoID))

        let ranked = try AIFinalSelectionRunValidator.rankedCandidatePhotoIDs(
            scores: scores,
            candidatePhotoIDs: candidateIDs
        )

        XCTAssertEqual(
            ranked,
            ["window-1-b", "window-2-a", "window-2-b", "window-1-a"]
        )
        XCTAssertEqual(
            try AIFinalSelectionRunValidator.finalSelectionIDs(
                rankedCandidatePhotoIDs: ranked,
                lockedKeeperPhotoIDs: ["keeper"],
                candidatePhotoIDs: candidateIDs,
                targetSelectionCount: 3
            ),
            ["keeper", "window-1-b", "window-2-a"]
        )
    }

    func testGlobalRankingUsesDimensionsForEqualTotalScores() throws {
        let lowerDimensions = AestheticScoreDimensions(
            moment: 80,
            composition: 80,
            subject: 80,
            lighting: 80,
            storytelling: 80
        )
        let higherDimensions = AestheticScoreDimensions(
            moment: 82,
            composition: 82,
            subject: 82,
            lighting: 82,
            storytelling: 82
        )
        let scores = [
            AIFinalSelectionScore(
                photoID: "photo-a",
                score: 88,
                dimensions: lowerDimensions
            ),
            AIFinalSelectionScore(
                photoID: "photo-b",
                score: 88,
                dimensions: higherDimensions
            ),
        ]

        XCTAssertEqual(
            try AIFinalSelectionRunValidator.rankedCandidatePhotoIDs(
                scores: scores,
                candidatePhotoIDs: Set(scores.map(\.photoID))
            ),
            ["photo-b", "photo-a"]
        )
    }

    func testGlobalRankingRequiresEveryCandidateScore() {
        XCTAssertThrowsError(
            try AIFinalSelectionRunValidator.rankedCandidatePhotoIDs(
                scores: [score("photo-a", 90)],
                candidatePhotoIDs: ["photo-a", "photo-b"]
            )
        ) { error in
            XCTAssertEqual(
                error as? AIFinalSelectionRunValidationError,
                .incompleteCandidateScores
            )
        }
    }

    func testRetryPolicyRetriesOnlyOneModelFormatFailure() {
        let formatError = ArkAestheticReviewClientError.invalidResponse(
            stage: .missingReviewPayload
        )

        XCTAssertTrue(
            AIFinalSelectionRetryPolicy.shouldRetry(
                formatError,
                completedRetryCount: 0
            )
        )
        XCTAssertTrue(
            AIFinalSelectionRetryPolicy.shouldRetry(
                formatError,
                completedRetryCount: 1
            )
        )
        XCTAssertFalse(
            AIFinalSelectionRetryPolicy.shouldRetry(
                formatError,
                completedRetryCount: AIFinalSelectionRetryPolicy.maximumAutomaticRetryCount
            )
        )
        // 格式错误的冷却时间保持很短：这类失败重发一次通常就能拿到合法 JSON。
        XCTAssertEqual(
            AIFinalSelectionRetryPolicy.retryDelay(
                for: formatError,
                completedRetryCount: 3,
                jitter: 1
            ),
            5
        )
        XCTAssertTrue(
            AIFinalSelectionRetryPolicy.shouldRetry(
                AestheticReviewValidationError.invalidDimensions,
                completedRetryCount: 0
            )
        )
        XCTAssertTrue(
            AIFinalSelectionRetryPolicy.shouldRetry(
                AestheticReviewValidationError.invalidSummary,
                completedRetryCount: 0
            )
        )
        // 限流和服务端故障必须自动退避重试：BYOK 场景下 429 是常态，
        // 让整轮评分为一次限流停下来会白白浪费已经付过费的批次。
        XCTAssertEqual(
            AIFinalSelectionRetryPolicy.retryDelay(
                for: ArkAestheticReviewClientError.requestRejected(
                    statusCode: 429,
                    providerCode: "RateLimit",
                    retryAfter: nil
                ),
                completedRetryCount: 0,
                jitter: 1
            ),
            2
        )
        // 服务端明确给了 Retry-After 时以它为准，不用自己猜。
        XCTAssertEqual(
            AIFinalSelectionRetryPolicy.retryDelay(
                for: ArkAestheticReviewClientError.requestRejected(
                    statusCode: 429,
                    providerCode: "RateLimit",
                    retryAfter: 17
                ),
                completedRetryCount: 2,
                jitter: 1
            ),
            17
        )
        // 退避按 2 的幂增长。
        XCTAssertEqual(
            AIFinalSelectionRetryPolicy.retryDelay(
                for: URLError(.timedOut),
                completedRetryCount: 3,
                jitter: 1
            ),
            16
        )
        // 权限、模型 ID 一类的错误重试没有意义。
        XCTAssertNil(
            AIFinalSelectionRetryPolicy.retryDelay(
                for: ArkAestheticReviewClientError.requestRejected(
                    statusCode: 401,
                    providerCode: "invalid_api_key",
                    retryAfter: nil
                ),
                completedRetryCount: 0,
                jitter: 1
            )
        )
        // 重试次数用尽后必须真的停下来。
        XCTAssertNil(
            AIFinalSelectionRetryPolicy.retryDelay(
                for: URLError(.timedOut),
                completedRetryCount: AIFinalSelectionRetryPolicy.maximumAutomaticRetryCount,
                jitter: 1
            )
        )
    }

    private func score(
        _ photoID: String,
        _ score: Int
    ) -> AIFinalSelectionScore {
        AIFinalSelectionScore(
            photoID: photoID,
            score: score,
            dimensions: dimensions(score)
        )
    }

    private func makeEntry(
        photoID: String,
        score: Int
    ) -> AestheticReviewEntry {
        AestheticReviewEntry(
            photoID: photoID,
            score: score,
            dimensions: dimensions(score),
            reasons: ["主体和画面关系清楚"],
            summary: "画面完成度稳定，主体和叙事表达清楚。"
        )
    }

    private func dimensions(_ score: Int) -> AestheticScoreDimensions {
        AestheticScoreDimensions(
            moment: score,
            composition: score,
            subject: score,
            lighting: score,
            storytelling: score
        )
    }
}
