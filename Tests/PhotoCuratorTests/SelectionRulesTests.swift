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

    /// 导出数量由用户决定：低于保留目标不再阻止导出，只有"一张都没保留"才拒绝。
    func testCategorizedExportRejectsOnlyWhenNothingIsKept() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let exportParent = root.appendingPathComponent("export", isDirectory: true)
        try manager.createDirectory(at: exportParent, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        XCTAssertThrowsError(
            try ExportService.copyCategorized(photos: [], to: exportParent)
        ) { error in
            XCTAssertEqual(error as? ExportError, .emptySelection)
        }
        XCTAssertEqual(
            try manager.contentsOfDirectory(atPath: exportParent.path),
            [],
            "拒绝导出时不应留下任何目录"
        )
    }

    /// 只保留了人物、风景一张都没有时，仍然可以导出。
    func testCategorizedExportAllowsCountsBelowTarget() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        let exportParent = root.appendingPathComponent("export", isDirectory: true)
        try manager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: exportParent, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let peopleURL = sourceDirectory.appendingPathComponent("person.jpg")
        try Data("person".utf8).write(to: peopleURL)

        let destination = try ExportService.copyCategorized(
            photos: [
                PhotoItem(url: peopleURL, decision: .keep, curationCategory: .people)
            ],
            to: exportParent
        )

        XCTAssertTrue(
            manager.fileExists(atPath: destination.appendingPathComponent("人物/person.jpg").path)
        )
        // 空类别仍然建目录，保证导出结构稳定、清单字段可预期。
        XCTAssertEqual(
            try manager.contentsOfDirectory(
                atPath: destination.appendingPathComponent("风景").path
            ),
            []
        )
    }
}
