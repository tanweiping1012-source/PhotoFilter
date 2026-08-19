import XCTest
@testable import PhotoCurator

final class AestheticReviewContractTests: XCTestCase {
    func testPeopleAndSceneryUseDifferentScoringInstructions() {
        let peopleRequest = AestheticReviewRequestBuilder.make(
            scope: AestheticReviewScope(
                kind: .finalSelection,
                groupID: "people-1",
                category: .people
            ),
            localPhotoIDs: ["person"]
        )
        let sceneryRequest = AestheticReviewRequestBuilder.make(
            scope: AestheticReviewScope(
                kind: .finalSelection,
                groupID: "scenery-1",
                category: .scenery
            ),
            localPhotoIDs: ["view"]
        )

        let peoplePrompt = AestheticReviewPrompt.userPrompt(
            for: peopleRequest
        )
        let sceneryPrompt = AestheticReviewPrompt.userPrompt(
            for: sceneryRequest
        )

        XCTAssertTrue(peoplePrompt.contains("表情"))
        XCTAssertTrue(peoplePrompt.contains("姿态"))
        XCTAssertTrue(sceneryPrompt.contains("空间层次"))
        XCTAssertTrue(sceneryPrompt.contains("没有人物"))
        XCTAssertNotEqual(peoplePrompt, sceneryPrompt)
    }

    func testValidatorRejectsResultFromAnotherCategory() {
        let requestScope = AestheticReviewScope(
            kind: .finalSelection,
            groupID: "selection-1",
            category: .people
        )
        let responseScope = AestheticReviewScope(
            kind: .finalSelection,
            groupID: "selection-1",
            category: .scenery
        )
        let request = makeRequest(
            scope: requestScope,
            requestID: "category-request"
        )
        let response = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: "category-request",
            scope: responseScope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 88,
                    reasons: ["人物状态自然"]
                ),
                makeEntry(
                    photoID: "photo_002",
                    score: 82,
                    reasons: ["人物主体清楚"]
                ),
            ]
        )

        XCTAssertThrowsError(
            try AestheticReviewValidator.validate(
                response,
                for: request
            )
        ) { error in
            XCTAssertEqual(
                error as? AestheticReviewValidationError,
                .scopeMismatch
            )
        }
    }

    func testAppliesIndependentScoresAndPreservesManualDecisions() throws {
        let root = URL(fileURLWithPath: "/fixtures")
        let first = PhotoItem(
            url: root.appendingPathComponent("first.jpg"),
            decision: .keep
        )
        let second = PhotoItem(
            url: root.appendingPathComponent("second.jpg"),
            decision: .reject
        )
        let scope = AestheticReviewScope(
            kind: .similarity,
            groupID: "similar-3"
        )
        let request = AestheticReviewRequestBuilder.make(
            scope: scope,
            localPhotoIDs: [first.id, second.id],
            requestID: "request-1"
        )
        let response = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: "request-1",
            scope: scope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 68,
                    reasons: ["构图稳定但主体较弱"]
                ),
                makeEntry(
                    photoID: "photo_002",
                    score: 91,
                    reasons: ["瞬间具有感染力", "主体表达突出"],
                    summary: "瞬间和主体表现完整，画面完成度高。"
                ),
            ]
        )

        let applied = try AestheticReviewApplier.applying(
            response,
            for: request,
            localPhotoIDs: [first.id, second.id],
            to: [first, second]
        )

        XCTAssertEqual(applied[0].decision, .keep)
        XCTAssertEqual(applied[1].decision, .reject)
        XCTAssertEqual(applied[0].aestheticRecommendations.first?.score, 68)
        XCTAssertEqual(applied[1].aestheticRecommendations.first?.score, 91)
        XCTAssertEqual(
            applied[1].aestheticRecommendations.first?.dimensions.subject,
            86
        )
    }

    func testRejectsUnexpectedOrIncompletePhotoSet() {
        let scope = AestheticReviewScope(
            kind: .similarity,
            groupID: "similar-4"
        )
        let request = makeRequest(scope: scope, requestID: "request-2")
        let response = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: "request-2",
            scope: scope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 88,
                    reasons: ["画面结构简洁"]
                ),
                makeEntry(
                    photoID: "photo_003",
                    score: 77,
                    reasons: ["层次关系自然"]
                ),
            ]
        )

        XCTAssertThrowsError(
            try AestheticReviewValidator.validate(response, for: request)
        ) { error in
            XCTAssertEqual(
                error as? AestheticReviewValidationError,
                .photoIDMismatch
            )
        }
    }

    func testRejectsScoreOutsideAllowedRange() {
        let scope = AestheticReviewScope(
            kind: .similarity,
            groupID: "similar-9"
        )
        let request = makeRequest(scope: scope, requestID: "request-3")
        let response = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: "request-3",
            scope: scope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 101,
                    reasons: ["故事表达完整"]
                ),
                makeEntry(
                    photoID: "photo_002",
                    score: 78,
                    reasons: ["构图关系自然"]
                ),
            ]
        )

        XCTAssertThrowsError(
            try AestheticReviewValidator.validate(response, for: request)
        ) { error in
            XCTAssertEqual(
                error as? AestheticReviewValidationError,
                .invalidScore
            )
        }
    }

    func testRejectsInvalidDimensionOrSummary() {
        let scope = AestheticReviewScope(
            kind: .similarity,
            groupID: "similar-10"
        )
        let request = makeRequest(scope: scope, requestID: "request-4")
        let invalidDimensions = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: "request-4",
            scope: scope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 90,
                    dimensions: AestheticScoreDimensions(
                        moment: 101,
                        composition: 86,
                        subject: 86,
                        lighting: 86,
                        storytelling: 86
                    ),
                    reasons: ["瞬间表达突出"]
                ),
                makeEntry(
                    photoID: "photo_002",
                    score: 80,
                    reasons: ["构图关系稳定"]
                ),
            ]
        )

        XCTAssertThrowsError(
            try AestheticReviewValidator.validate(
                invalidDimensions,
                for: request
            )
        ) { error in
            XCTAssertEqual(
                error as? AestheticReviewValidationError,
                .invalidDimensions
            )
        }

        let invalidSummary = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: "request-4",
            scope: scope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 90,
                    reasons: ["瞬间表达突出"],
                    summary: "短"
                ),
                makeEntry(
                    photoID: "photo_002",
                    score: 80,
                    reasons: ["构图关系稳定"]
                ),
            ]
        )

        XCTAssertThrowsError(
            try AestheticReviewValidator.validate(
                invalidSummary,
                for: request
            )
        ) { error in
            XCTAssertEqual(
                error as? AestheticReviewValidationError,
                .invalidSummary
            )
        }
    }

    func testRejectsRelativeComparisonCommentary() {
        let scope = AestheticReviewScope(
            kind: .finalSelection,
            groupID: "ai-score-window-001"
        )
        let request = makeRequest(
            scope: scope,
            requestID: "relative-commentary"
        )
        let response = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: request.requestID,
            scope: scope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 90,
                    reasons: ["主体表达清楚"],
                    summary: "主体和瞬间表现完整，是本组优先照片。"
                ),
                makeEntry(
                    photoID: "photo_002",
                    score: 80,
                    reasons: ["构图关系稳定"]
                ),
            ]
        )

        XCTAssertThrowsError(
            try AestheticReviewValidator.validate(response, for: request)
        ) { error in
            XCTAssertEqual(
                error as? AestheticReviewValidationError,
                .relativeComparison
            )
        }
    }

    func testPreservesManualAndFinalIndependentScoresForSamePhoto() throws {
        let root = URL(fileURLWithPath: "/fixtures")
        let photos = [
            PhotoItem(url: root.appendingPathComponent("first.jpg")),
            PhotoItem(url: root.appendingPathComponent("second.jpg")),
        ]
        let localPhotoIDs = photos.map(\.id)
        let manualScope = AestheticReviewScope(
            kind: .similarity,
            groupID: "similar-20"
        )
        let manualRequest = AestheticReviewRequestBuilder.make(
            scope: manualScope,
            localPhotoIDs: localPhotoIDs,
            requestID: "manual-request"
        )
        let manualResponse = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: manualRequest.requestID,
            scope: manualScope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 93,
                    reasons: ["主体表达清楚"]
                ),
                makeEntry(
                    photoID: "photo_002",
                    score: 79,
                    reasons: ["叙事表达较弱"]
                ),
            ]
        )
        let manualApplied = try AestheticReviewApplier.applying(
            manualResponse,
            for: manualRequest,
            localPhotoIDs: localPhotoIDs,
            to: photos
        )

        let finalScope = AestheticReviewScope(
            kind: .finalSelection,
            groupID: "ai-score-window-001"
        )
        let finalRequest = AestheticReviewRequestBuilder.make(
            scope: finalScope,
            localPhotoIDs: localPhotoIDs,
            requestID: "final-request"
        )
        let finalResponse = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: finalRequest.requestID,
            scope: finalScope,
            reviews: [
                makeEntry(
                    photoID: "photo_001",
                    score: 84,
                    reasons: ["叙事表达仍可加强"]
                ),
                makeEntry(
                    photoID: "photo_002",
                    score: 90,
                    reasons: ["瞬间表达自然"]
                ),
            ]
        )
        let finalApplied = try AestheticReviewApplier.applying(
            finalResponse,
            for: finalRequest,
            localPhotoIDs: localPhotoIDs,
            to: manualApplied
        )

        XCTAssertEqual(finalApplied[0].aestheticRecommendations.count, 2)
        XCTAssertEqual(
            Set(
                finalApplied[0].aestheticRecommendations.map {
                    $0.scope.kind.rawValue
                }
            ),
            ["similarity", "finalSelection"]
        )
        XCTAssertEqual(
            finalApplied[0].primaryAestheticRecommendation?.score,
            84
        )
    }

    private func makeRequest(
        scope: AestheticReviewScope,
        requestID: String
    ) -> AestheticReviewRequest {
        AestheticReviewRequest(
            requestID: requestID,
            scope: scope,
            photos: [
                AestheticReviewInput(photoID: "photo_001", position: 1),
                AestheticReviewInput(photoID: "photo_002", position: 2),
            ]
        )
    }

    private func makeEntry(
        photoID: String,
        score: Int,
        dimensions: AestheticScoreDimensions = AestheticScoreDimensions(
            moment: 82,
            composition: 83,
            subject: 86,
            lighting: 81,
            storytelling: 84
        ),
        reasons: [String],
        summary: String = "画面表现稳定，主体和叙事信息清楚。"
    ) -> AestheticReviewEntry {
        AestheticReviewEntry(
            photoID: photoID,
            score: score,
            dimensions: dimensions,
            reasons: reasons,
            summary: summary
        )
    }
}
