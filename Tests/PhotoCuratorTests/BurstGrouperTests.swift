import XCTest
@testable import PhotoCurator

final class BurstGrouperTests: XCTestCase {
    func testGroupsConsecutivePhotosWithinThreeSeconds() {
        let start = Date(timeIntervalSince1970: 1_000)
        let root = URL(fileURLWithPath: "/fixtures")
        let photos = [
            PhotoItem(url: root.appendingPathComponent("01.jpg"), captureDate: start),
            PhotoItem(url: root.appendingPathComponent("02.jpg"), captureDate: start.addingTimeInterval(2)),
            PhotoItem(url: root.appendingPathComponent("03.jpg"), captureDate: start.addingTimeInterval(5)),
            PhotoItem(url: root.appendingPathComponent("04.jpg"), captureDate: start.addingTimeInterval(12)),
        ]

        let grouped = BurstGrouper.assigningGroups(to: photos)

        XCTAssertEqual(BurstGrouper.groupCount(in: grouped), 1)
        XCTAssertEqual(BurstGrouper.groupedPhotoCount(in: grouped), 3)
        XCTAssertEqual(grouped[0].burstGroup?.position, 1)
        XCTAssertEqual(grouped[1].burstGroup?.position, 2)
        XCTAssertEqual(grouped[2].burstGroup?.position, 3)
        XCTAssertEqual(grouped[2].burstGroup?.count, 3)
        XCTAssertNil(grouped[3].burstGroup)
    }

    func testDoesNotGroupUnknownOrIsolatedCaptureDates() {
        let start = Date(timeIntervalSince1970: 1_000)
        let root = URL(fileURLWithPath: "/fixtures")
        let photos = [
            PhotoItem(url: root.appendingPathComponent("unknown.jpg")),
            PhotoItem(url: root.appendingPathComponent("early.jpg"), decision: .keep, captureDate: start),
            PhotoItem(url: root.appendingPathComponent("late.jpg"), decision: .reject, captureDate: start.addingTimeInterval(10)),
        ]

        let grouped = BurstGrouper.assigningGroups(to: photos)

        XCTAssertEqual(BurstGrouper.groupCount(in: grouped), 0)
        XCTAssertTrue(grouped.allSatisfy { $0.burstGroup == nil })
        XCTAssertEqual(grouped[1].decision, .keep, "分组不能覆盖人工决定")
        XCTAssertEqual(grouped[2].decision, .reject, "分组不能覆盖人工决定")
    }
}
