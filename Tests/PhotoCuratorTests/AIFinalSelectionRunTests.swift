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
        XCTAssertEqual(plan.estimatedMinimumMinutes, 9)
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

    func testPlannerRejectsUnsafeCandidateToTargetRatios() {
        XCTAssertThrowsError(
            try AIFinalSelectionRunPlanner.makePlan(
                candidateLocalPhotoIDs: (1...11).map { "photo-\($0)" },
                targetWinnerCount: 6
            )
        ) { error in
            XCTAssertEqual(error as? AIFinalSelectionRunPlanError, .insufficientCandidates)
        }
        XCTAssertThrowsError(
            try AIFinalSelectionRunPlanner.makePlan(
                candidateLocalPhotoIDs: (1...13).map { "photo-\($0)" },
                targetWinnerCount: 2
            )
        ) { error in
            XCTAssertEqual(error as? AIFinalSelectionRunPlanError, .tooManyCandidates)
        }
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
        XCTAssertFalse(
            AIFinalSelectionRetryPolicy.shouldRetry(
                formatError,
                completedRetryCount: 1
            )
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
        XCTAssertFalse(
            AIFinalSelectionRetryPolicy.shouldRetry(
                ArkAestheticReviewClientError.requestRejected(
                    statusCode: 429,
                    providerCode: "RateLimit"
                ),
                completedRetryCount: 0
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
