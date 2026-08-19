import Foundation
import XCTest
@testable import PhotoCurator

final class LocalAestheticCandidatePlannerTests: XCTestCase {
    func testTwelvePhotoTargetStopsAtThirtySixStrongCandidatesInsteadOfFillingFortyEight() {
        var photos = makePhotos(count: 168)
        for index in 0..<42 {
            photos[index].localRecommendations = [winner(groupID: "group-\(index)")]
        }

        let plan = LocalAestheticCandidatePlanner.makePlan(
            for: photos,
            targetSelectionCount: 12
        )

        XCTAssertEqual(plan.totalPhotoCount, 168)
        XCTAssertEqual(plan.eligiblePhotoCount, 168)
        XCTAssertEqual(plan.remainingSelectionCount, 12)
        XCTAssertEqual(plan.requestedCandidateCount, 36)
        XCTAssertEqual(plan.candidateCount, 36)
        XCTAssertTrue(plan.localPhotoIDSet.isSubset(of: Set(photos.prefix(42).map(\.id))))
    }

    func testManualDecisionsAreRespectedAndRemainingTargetControlsPoolSize() {
        var photos = makePhotos(count: 80)
        photos[0].decision = .keep
        photos[1].decision = .keep
        photos[2].decision = .reject

        let plan = LocalAestheticCandidatePlanner.makePlan(
            for: photos,
            targetSelectionCount: 12
        )

        XCTAssertEqual(plan.remainingSelectionCount, 10)
        XCTAssertEqual(plan.eligiblePhotoCount, 77)
        XCTAssertEqual(plan.candidateCount, 20)
        XCTAssertFalse(plan.localPhotoIDSet.contains(photos[0].id))
        XCTAssertFalse(plan.localPhotoIDSet.contains(photos[1].id))
        XCTAssertFalse(plan.localPhotoIDSet.contains(photos[2].id))
    }

    func testCandidatePoolNeverExceedsFortyEightPhotos() {
        let plan = LocalAestheticCandidatePlanner.makePlan(
            for: makePhotos(count: 400),
            targetSelectionCount: 100
        )

        XCTAssertEqual(plan.candidateCount, 48)
    }

    func testSmallRemainingTargetNeverExceedsFinalBatchCapacity() {
        var photos = makePhotos(count: 40)
        for index in 0..<10 {
            photos[index].decision = .keep
        }

        let plan = LocalAestheticCandidatePlanner.makePlan(
            for: photos,
            targetSelectionCount: 12
        )

        XCTAssertEqual(plan.remainingSelectionCount, 2)
        XCTAssertEqual(plan.candidateCount, 4)
        XCTAssertNoThrow(
            try AIFinalSelectionRunPlanner.makePlan(
                candidateLocalPhotoIDs: plan.localPhotoIDs,
                targetWinnerCount: plan.remainingSelectionCount
            )
        )
    }

    func testNoCandidatesWhenHumanSelectionAlreadyMeetsTarget() {
        var photos = makePhotos(count: 20)
        for index in 0..<12 {
            photos[index].decision = .keep
        }

        let plan = LocalAestheticCandidatePlanner.makePlan(
            for: photos,
            targetSelectionCount: 12
        )

        XCTAssertEqual(plan.remainingSelectionCount, 0)
        XCTAssertTrue(plan.localPhotoIDs.isEmpty)
    }

    func testWeakOrUnknownCandidatesOnlyFillMinimumComparisonPool() {
        let plan = LocalAestheticCandidatePlanner.makePlan(
            for: makePhotos(count: 100),
            targetSelectionCount: 12
        )

        XCTAssertEqual(plan.candidateCount, 24)
        XCTAssertLessThan(plan.candidateCount, 48)
    }

    func testCandidateIDsRemainInChronologicalOrder() {
        var photos = Array(makePhotos(count: 30).reversed())
        photos[5].localRecommendations = [winner(groupID: "winner")]

        let plan = LocalAestheticCandidatePlanner.makePlan(
            for: photos,
            targetSelectionCount: 3
        )
        let datesByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.captureDate!) })
        let dates = plan.localPhotoIDs.compactMap { datesByID[$0] }

        XCTAssertEqual(dates, dates.sorted())
    }

    func testOnlyBestRepresentativeFromCandidateFamilyEntersAI() {
        var photos = makePhotos(count: 12)
        photos[0].similarityGroup = SimilarityGroupMembership(id: "similar-1", position: 1, count: 2)
        photos[1].similarityGroup = SimilarityGroupMembership(id: "similar-1", position: 2, count: 2)
        photos[0].localRecommendations = [recommendation(groupID: "similar-1", rank: 2)]
        photos[1].localRecommendations = [recommendation(groupID: "similar-1", rank: 1)]

        let plan = LocalAestheticCandidatePlanner.makePlan(for: photos, targetSelectionCount: 2)

        XCTAssertFalse(plan.localPhotoIDSet.contains(photos[0].id))
        XCTAssertTrue(plan.localPhotoIDSet.contains(photos[1].id))
        XCTAssertEqual(plan.collapsedSiblingCount, 1)
    }

    func testStandalonePhotosKeepCandidateSeatsAlongsideGroupedRepresentatives() {
        var photos = makePhotos(count: 20)
        for index in 0..<10 {
            photos[index].similarityGroup = SimilarityGroupMembership(
                id: "similar-\(index / 2)",
                position: index % 2 + 1,
                count: 2
            )
            photos[index].localRecommendations = [
                recommendation(groupID: "similar-\(index / 2)", rank: index % 2 + 1)
            ]
        }

        let plan = LocalAestheticCandidatePlanner.makePlan(for: photos, targetSelectionCount: 2)

        XCTAssertGreaterThan(plan.groupedRepresentativeCount, 0)
        XCTAssertEqual(plan.standaloneEligibleCount, 10)
        XCTAssertGreaterThan(plan.standaloneSelectedCount, 0)
    }

    func testLockedKeeperBlocksItsFamilySiblingsFromAICandidates() {
        var photos = makePhotos(count: 12)
        photos[0].decision = .keep
        photos[0].similarityGroup = SimilarityGroupMembership(id: "similar-1", position: 1, count: 2)
        photos[1].similarityGroup = SimilarityGroupMembership(id: "similar-1", position: 2, count: 2)

        let plan = LocalAestheticCandidatePlanner.makePlan(for: photos, targetSelectionCount: 3)

        XCTAssertFalse(plan.localPhotoIDSet.contains(photos[1].id))
        XCTAssertEqual(plan.excludedByLockedKeeperCount, 1)
    }

    private func makePhotos(count: Int) -> [PhotoItem] {
        let root = URL(fileURLWithPath: "/fixtures")
        return (0..<count).map { offset in
            PhotoItem(
                url: root.appendingPathComponent(String(format: "IMG_%03d.jpg", offset + 1)),
                captureDate: Date(timeIntervalSince1970: TimeInterval(offset))
            )
        }
    }

    private func winner(groupID: String) -> GroupRecommendation {
        recommendation(groupID: groupID, rank: 1)
    }

    private func recommendation(groupID: String, rank: Int) -> GroupRecommendation {
        GroupRecommendation(
            kind: .similarity,
            groupID: groupID,
            rank: rank,
            groupSize: 2,
            explanation: "本地优先"
        )
    }
}
