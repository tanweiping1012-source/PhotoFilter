import Foundation
import XCTest
@testable import PhotoCurator

final class PhotoGridFilterTests: XCTestCase {
    func testAICandidateFilterShowsOnlyCandidatePoolPhotos() {
        let photos = makePhotos()
        let candidateIDs = Set([photos[0].id, photos[2].id])

        let filtered = PhotoGridFilter.aiCandidates.photos(
            from: photos,
            localAICandidateIDs: candidateIDs
        )

        XCTAssertEqual(filtered.map(\.id), [photos[0].id, photos[2].id])
        XCTAssertEqual(photos.count, 4)
    }

    func testDecisionFiltersRemainIndependentFromAICandidatePool() {
        var photos = makePhotos()
        photos[0].decision = .keep
        photos[1].decision = .reject

        XCTAssertEqual(
            PhotoGridFilter.keep.photos(from: photos, localAICandidateIDs: []).map(\.id),
            [photos[0].id]
        )
        XCTAssertEqual(
            PhotoGridFilter.reject.photos(from: photos, localAICandidateIDs: []).map(\.id),
            [photos[1].id]
        )
        XCTAssertEqual(
            PhotoGridFilter.undecided.photos(from: photos, localAICandidateIDs: []).count,
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
            aiFinalSelectionIDs: [photos[2].id]
        )

        XCTAssertEqual(filtered.map(\.id), [photos[2].id, photos[0].id])
    }

    func testAISelectedFilterDoesNotConfuseScoredPhotosWithFinalSelection() {
        let photos = makePhotos()
        let candidates = Set(photos.map(\.id))
        let finalSelection = Set([photos[1].id, photos[3].id])

        let filtered = PhotoGridFilter.aiSelected.photos(
            from: photos,
            localAICandidateIDs: candidates,
            aiFinalSelectionIDs: finalSelection
        )

        XCTAssertEqual(filtered.map(\.id), [photos[1].id, photos[3].id])
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

        XCTAssertEqual(photo.primaryAestheticRecommendation?.score, 84)
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
            score: score,
            dimensions: AestheticScoreDimensions(
                moment: 86,
                composition: 87,
                subject: 88,
                lighting: 89,
                storytelling: 90
            ),
            reasons: ["主体清楚"],
            summary: "整体表现稳定，适合继续保留。"
        )
    }
}
