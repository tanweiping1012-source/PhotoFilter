import Foundation
import XCTest
@testable import PhotoCurator

final class PhotoProjectTests: XCTestCase {
    func testProjectUsesParentAndFolderAsReadableName() {
        let project = PhotoProject(folderURL: URL(fileURLWithPath: "/fixtures/20260802美国/2"))

        XCTAssertEqual(project.displayName, "20260802美国 / 2")
    }

    func testCatalogFindsStandardizedFolderAndRemovalDoesNotTouchOtherProjects() {
        let first = PhotoProject(folderURL: URL(fileURLWithPath: "/fixtures/trip-a/./day-1"))
        let second = PhotoProject(folderURL: URL(fileURLWithPath: "/fixtures/trip-b/day-2"))
        let projects = [first, second]

        XCTAssertEqual(
            PhotoProjectCatalog.project(
                for: URL(fileURLWithPath: "/fixtures/trip-a/day-1"),
                in: projects
            )?.id,
            first.id
        )
        XCTAssertEqual(PhotoProjectCatalog.removing(first.id, from: projects), [second])
    }
}
