import XCTest

@testable import PhotoCurator

final class PhotoPreviewNavigatorTests: XCTestCase {
    func testMovesWithinCurrentFilteredPhotoOrder() {
        let photoIDs = ["photo-a", "photo-c", "photo-f"]

        XCTAssertEqual(
            PhotoPreviewNavigator.photoID(
                in: photoIDs,
                currentID: "photo-a",
                offset: 1
            ),
            "photo-c"
        )
        XCTAssertEqual(
            PhotoPreviewNavigator.photoID(
                in: photoIDs,
                currentID: "photo-f",
                offset: -1
            ),
            "photo-c"
        )
    }

    func testStopsAtPreviewBoundaries() {
        let photoIDs = ["photo-a", "photo-b"]

        XCTAssertNil(
            PhotoPreviewNavigator.photoID(
                in: photoIDs,
                currentID: "photo-a",
                offset: -1
            )
        )
        XCTAssertNil(
            PhotoPreviewNavigator.photoID(
                in: photoIDs,
                currentID: "photo-b",
                offset: 1
            )
        )
    }

    func testFallsBackToFirstPhotoWhenSelectionIsOutsideFilter() {
        XCTAssertEqual(
            PhotoPreviewNavigator.photoID(
                in: ["photo-a", "photo-b"],
                currentID: "photo-z",
                offset: 1
            ),
            "photo-a"
        )
    }
}
