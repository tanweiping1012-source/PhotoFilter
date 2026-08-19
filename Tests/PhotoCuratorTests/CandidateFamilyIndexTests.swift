import Foundation
import XCTest
@testable import PhotoCurator

final class CandidateFamilyIndexTests: XCTestCase {
    func testLegacyTimeGroupCannotBridgeVisualSimilarityFamilies() {
        let root = URL(fileURLWithPath: "/fixtures")
        let photos = [
            PhotoItem(
                url: root.appendingPathComponent("a.jpg"),
                burstGroup: BurstGroupMembership(id: "burst-1", position: 1, count: 2)
            ),
            PhotoItem(
                url: root.appendingPathComponent("b.jpg"),
                burstGroup: BurstGroupMembership(id: "burst-1", position: 2, count: 2),
                similarityGroup: SimilarityGroupMembership(id: "similar-1", position: 1, count: 2)
            ),
            PhotoItem(
                url: root.appendingPathComponent("c.jpg"),
                similarityGroup: SimilarityGroupMembership(id: "similar-1", position: 2, count: 2)
            ),
            PhotoItem(url: root.appendingPathComponent("standalone.jpg")),
        ]

        let index = CandidateFamilyIndex(photos: photos)

        XCTAssertNil(
            index.familyID(for: photos[0].id),
            "旧时间标记不能再建立或扩展候选家族"
        )
        XCTAssertEqual(
            index.familyID(for: photos[1].id),
            index.familyID(for: photos[2].id)
        )
        XCTAssertNil(index.familyID(for: photos[3].id))
        XCTAssertEqual(
            index.conflicts(in: Set(photos.prefix(3).map(\.id))),
            [[photos[1].id, photos[2].id].sorted()]
        )
    }
}
