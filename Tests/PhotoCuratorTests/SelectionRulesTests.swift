import XCTest
@testable import PhotoCurator

final class SelectionRulesTests: XCTestCase {
    func testKeepersOnlyIncludesKeptPhotos() {
        let root = URL(fileURLWithPath: "/fixtures")
        let photos = [
            PhotoItem(url: root.appendingPathComponent("keep.jpg"), decision: .keep),
            PhotoItem(url: root.appendingPathComponent("reject.jpg"), decision: .reject),
            PhotoItem(url: root.appendingPathComponent("pending.jpg"), decision: .undecided),
        ]

        XCTAssertEqual(SelectionRules.keepers(in: photos).map(\.filename), ["keep.jpg"])
    }

    func testDecisionsHaveStableUserFacingTitles() {
        XCTAssertEqual(PhotoDecision.keep.title, "保留")
        XCTAssertEqual(PhotoDecision.reject.title, "淘汰")
        XCTAssertEqual(PhotoDecision.undecided.title, "待定")
    }

    func testSelectionTargetReportsUnderExactAndOverStates() {
        XCTAssertEqual(SelectionTarget.status(keptCount: 3, targetCount: 5), .needsMore(2))
        XCTAssertEqual(SelectionTarget.status(keptCount: 5, targetCount: 5), .exact)
        XCTAssertEqual(SelectionTarget.status(keptCount: 7, targetCount: 5), .tooMany(2))
        XCTAssertEqual(SelectionTarget.status(keptCount: 0, targetCount: 0), .exact)
    }

    func testExportCopiesOnlyRetainedPhotosAndPreservesSource() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let exportParent = root.appendingPathComponent("export", isDirectory: true)
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: exportParent, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let keptURL = source.appendingPathComponent("kept.jpg")
        let rejectedURL = source.appendingPathComponent("rejected.jpg")
        let keptData = Data("keep-content".utf8)
        try keptData.write(to: keptURL)
        try Data("reject-content".utf8).write(to: rejectedURL)

        let destination = try ExportService.copy(
            photos: [
                PhotoItem(url: keptURL, decision: .keep),
            ],
            to: exportParent,
            expectedCount: 1,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(try Data(contentsOf: keptURL), keptData, "源文件必须保持不变")
        XCTAssertTrue(manager.fileExists(atPath: destination.appendingPathComponent("kept.jpg").path))
        XCTAssertFalse(manager.fileExists(atPath: destination.appendingPathComponent("rejected.jpg").path))

        let manifestData = try Data(contentsOf: destination.appendingPathComponent("selection.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ExportManifest.self, from: manifestData)
        XCTAssertEqual(manifest.exportedCount, 1)
        XCTAssertEqual(manifest.filenames, ["kept.jpg"])
    }

    func testExportRejectsWrongSelectionCountBeforeCreatingDirectory() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let exportParent = root.appendingPathComponent("export", isDirectory: true)
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: exportParent, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let photoURL = source.appendingPathComponent("kept.jpg")
        try Data("keep-content".utf8).write(to: photoURL)

        XCTAssertThrowsError(
            try ExportService.copy(
                photos: [PhotoItem(url: photoURL, decision: .keep)],
                to: exportParent,
                expectedCount: 2
            )
        ) { error in
            XCTAssertEqual(error as? ExportError, .selectionCountMismatch(expected: 2, actual: 1))
        }
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: exportParent.path), [])
    }

    func testCategorizedExportCreatesPeopleAndSceneryFolders() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let source = root.appendingPathComponent(
            "source",
            isDirectory: true
        )
        let exportParent = root.appendingPathComponent(
            "export",
            isDirectory: true
        )
        try manager.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try manager.createDirectory(
            at: exportParent,
            withIntermediateDirectories: true
        )
        defer { try? manager.removeItem(at: root) }

        let peopleURL = source.appendingPathComponent("person.jpg")
        let sceneryURL = source.appendingPathComponent("view.jpg")
        let peopleData = Data("person-source".utf8)
        let sceneryData = Data("scenery-source".utf8)
        try peopleData.write(to: peopleURL)
        try sceneryData.write(to: sceneryURL)

        let destination = try ExportService.copyCategorized(
            photos: [
                PhotoItem(
                    url: peopleURL,
                    decision: .keep,
                    curationCategory: .people
                ),
                PhotoItem(
                    url: sceneryURL,
                    decision: .keep,
                    curationCategory: .scenery
                ),
            ],
            to: exportParent,
            targets: PhotoSelectionTargets(
                people: 1,
                scenery: 1
            ),
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(try Data(contentsOf: peopleURL), peopleData)
        XCTAssertEqual(try Data(contentsOf: sceneryURL), sceneryData)
        XCTAssertTrue(
            manager.fileExists(
                atPath: destination.appendingPathComponent(
                    "人物/person.jpg"
                ).path
            )
        )
        XCTAssertTrue(
            manager.fileExists(
                atPath: destination.appendingPathComponent(
                    "风景/view.jpg"
                ).path
            )
        )
        let manifestData = try Data(
            contentsOf: destination.appendingPathComponent(
                "selection.json"
            )
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            CategorizedExportManifest.self,
            from: manifestData
        )
        XCTAssertEqual(manifest.exportedCount, 2)
        XCTAssertEqual(
            Set(manifest.groups.map(\.category)),
            Set(PhotoCurationCategory.allCases)
        )
    }

    func testCategorizedExportRejectsOneCategoryMismatchBeforeWriting() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let exportParent = root.appendingPathComponent(
            "export",
            isDirectory: true
        )
        try manager.createDirectory(
            at: exportParent,
            withIntermediateDirectories: true
        )
        defer { try? manager.removeItem(at: root) }

        XCTAssertThrowsError(
            try ExportService.copyCategorized(
                photos: [],
                to: exportParent,
                targets: PhotoSelectionTargets(
                    people: 1,
                    scenery: 0
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ExportError,
                .categorySelectionCountMismatch(
                    category: .people,
                    expected: 1,
                    actual: 0
                )
            )
        }
        XCTAssertEqual(
            try manager.contentsOfDirectory(
                atPath: exportParent.path
            ),
            []
        )
    }
}
