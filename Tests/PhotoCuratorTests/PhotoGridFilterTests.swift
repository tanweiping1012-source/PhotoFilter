import Foundation
import XCTest
@testable import PhotoCurator

final class PhotoGridFilterTests: XCTestCase {
    func testAICandidateFilterShowsOnlyCandidatePoolPhotos() {
        let photos = makePhotos()
        let candidateIDs = Set([photos[0].id, photos[2].id])

        let filtered = PhotoGridFilter.aiCandidates.photos(
            from: photos,
            localAICandidateIDs: candidateIDs,
            weights: .balanced
        )

        XCTAssertEqual(filtered.map(\.id), [photos[0].id, photos[2].id])
        XCTAssertEqual(photos.count, 4)
    }

    func testDecisionFiltersRemainIndependentFromAICandidatePool() {
        var photos = makePhotos()
        photos[0].decision = .keep
        photos[1].decision = .reject

        XCTAssertEqual(
            PhotoGridFilter.keep.photos(from: photos, localAICandidateIDs: [], weights: .balanced).map(\.id),
            [photos[0].id]
        )
        XCTAssertEqual(
            PhotoGridFilter.reject.photos(from: photos, localAICandidateIDs: [], weights: .balanced).map(\.id),
            [photos[1].id]
        )
        XCTAssertEqual(
            PhotoGridFilter.undecided.photos(from: photos, localAICandidateIDs: [], weights: .balanced).count,
            2
        )
    }

    func testAIScoredFilterShowsEveryPhotoWithAValidatedScore() {
        var photos = makePhotos()
        photos[0].aestheticRecommendations = [makeRecommendation(score: 82)]
        photos[2].aestheticRecommendations = [makeRecommendation(score: 91)]

        let filtered = PhotoGridFilter.aiScored.photos(
            from: photos,
            localAICandidateIDs: Set(photos.map(\.id)),
            weights: .balanced
        )

        XCTAssertEqual(filtered.map(\.id), [photos[2].id, photos[0].id])
    }

    func testPrimaryScorePrefersFinalSelectionRecord() {
        var photo = makePhotos()[0]
        photo.aestheticRecommendations = [
            makeRecommendation(
                kind: .similarity,
                groupID: "similarity-1",
                score: 96
            ),
            makeRecommendation(
                kind: .finalSelection,
                groupID: "final-1",
                score: 84
            ),
        ]

        XCTAssertEqual(
            photo.primaryAestheticRecommendation?.total(with: .balanced),
            84
        )
        XCTAssertEqual(
            photo.primaryAestheticRecommendation?.scope.kind,
            .finalSelection
        )
    }

    private func makePhotos() -> [PhotoItem] {
        let root = URL(fileURLWithPath: "/fixtures")
        return (1...4).map { index in
            PhotoItem(url: root.appendingPathComponent("IMG_\(index).jpg"))
        }
    }

    private func makeRecommendation(
        kind: CandidateGroupKind = .finalSelection,
        groupID: String = "final-1",
        score: Int = 88
    ) -> AestheticRecommendation {
        AestheticRecommendation(
            scope: AestheticReviewScope(
                kind: kind,
                groupID: groupID
            ),
            dimensions: AestheticScoreDimensions(
                moment: score,
                composition: score,
                subject: score,
                lighting: score,
                storytelling: score
            ),
            reasons: ["主体清楚"],
            summary: "整体表现稳定，适合继续保留。"
        )
    }
}
