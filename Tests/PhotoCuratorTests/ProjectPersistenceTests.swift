import Foundation
import XCTest
@testable import PhotoCurator

final class ProjectPersistenceTests: XCTestCase {
    private final class MemoryProjectStore: PhotoProjectPersisting {
        var catalog: PersistedPhotoProjectCatalog?

        func load() throws -> PersistedPhotoProjectCatalog? {
            catalog
        }

        func save(_ catalog: PersistedPhotoProjectCatalog) throws {
            self.catalog = catalog
        }
    }

    private final class TestBookmarkAccess: SecurityScopedBookmarkAccessing {
        private(set) var activeURLs: Set<URL> = []

        func makeReadOnlyBookmark(for folderURL: URL) throws -> Data {
            Data(folderURL.standardizedFileURL.path.utf8)
        }

        func resolve(_ bookmarkData: Data) throws -> ResolvedProjectBookmark {
            guard let path = String(data: bookmarkData, encoding: .utf8) else {
                throw ProjectPersistenceError.inaccessibleBookmark
            }
            return ResolvedProjectBookmark(
                url: URL(fileURLWithPath: path, isDirectory: true),
                isStale: false
            )
        }

        func startAccessing(_ url: URL) -> Bool {
            activeURLs.insert(url.standardizedFileURL)
            return true
        }

        func stopAccessing(_ url: URL) {
            activeURLs.remove(url.standardizedFileURL)
        }
    }

    func testDiskStoreRoundTripsOnlyMinimalProjectState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("projects.json")
        let store = PhotoProjectDiskStore(fileURL: fileURL)
        let projectID = UUID()
        let project = PersistedPhotoProject(
            id: projectID,
            bookmarkData: Data("opaque-bookmark".utf8),
            displayName: "美国 / 2",
            createdAt: Date(timeIntervalSince1970: 100),
            lastOpenedAt: Date(timeIntervalSince1970: 200),
            lastKnownPhotoCount: 430,
            targetSelectionCount: 12,
            selectionTargets: PhotoSelectionTargets(
                people: 5,
                scenery: 7
            ),
            decisionsByRelativePath: [
                "DSCF6554.JPG": .keep,
                "nested/DSCF6607.JPG": .reject,
            ],
            categoryOverridesByRelativePath: [
                "DSCF6554.JPG": .people,
            ],
            selectedRelativePath: "DSCF6554.JPG"
        )
        let catalog = PersistedPhotoProjectCatalog(
            activeProjectID: projectID,
            projects: [project]
        )

        try store.save(catalog)

        XCTAssertEqual(try store.load(), catalog)
        let storedText = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(storedText.contains("/Users/"))
        XCTAssertFalse(storedText.contains("sk-"))
    }

    func testRelativePathIsStableAndRejectsFilesOutsideProjectRoot() {
        let root = URL(fileURLWithPath: "/fixtures/trip/day-2", isDirectory: true)

        XCTAssertEqual(
            ProjectRelativePath.make(
                for: root.appendingPathComponent("nested/DSCF6607.JPG"),
                relativeTo: root
            ),
            "nested/DSCF6607.JPG"
        )
        XCTAssertNil(
            ProjectRelativePath.make(
                for: URL(fileURLWithPath: "/fixtures/other/DSCF6607.JPG"),
                relativeTo: root
            )
        )
    }

    func testUnavailableProjectKeepsReadableNameWithoutPersistingPlainPath() {
        let project = PhotoProject(
            id: UUID(),
            folderURL: nil,
            displayName: "美国 / 2",
            createdAt: Date(),
            photoCount: 430,
            accessState: .needsAuthorization
        )

        XCTAssertEqual(project.displayName, "美国 / 2")
        XCTAssertEqual(project.accessState, .needsAuthorization)
        XCTAssertNil(project.folderURL)
    }

    @MainActor
    func testViewModelRestoresTargetAndRelativeDecisionsAcrossLaunches() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-relaunch-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstPhoto = root.appendingPathComponent("DSCF0001.JPG")
        let secondPhoto = root.appendingPathComponent("DSCF0002.JPG")
        try Data().write(to: firstPhoto)
        try Data().write(to: secondPhoto)

        let store = MemoryProjectStore()
        let bookmarkAccess = TestBookmarkAccess()
        let firstLaunch = PhotoLibraryViewModel(
            projectStore: store,
            bookmarkAccess: bookmarkAccess
        )
        firstLaunch.scan(folder: root)
        await waitUntil { firstLaunch.photos.count == 2 && !firstLaunch.isAnalyzing }
        firstLaunch.targetSelectionCount = 1
        firstLaunch.select(firstPhoto.standardizedFileURL.path)
        firstLaunch.setSelectedCurationCategory(.people)
        firstLaunch.markSelected(as: .keep)
        firstLaunch.prepareForTermination()

        XCTAssertEqual(store.catalog?.projects.first?.targetSelectionCount, 1)
        XCTAssertEqual(
            store.catalog?.projects.first?.selectionTargets,
            PhotoSelectionTargets(people: 1, scenery: 0)
        )
        XCTAssertEqual(store.catalog?.projects.first?.decisionsByRelativePath["DSCF0001.JPG"], .keep)
        XCTAssertEqual(
            store.catalog?.projects.first?
                .categoryOverridesByRelativePath?["DSCF0001.JPG"],
            .people
        )
        XCTAssertTrue(bookmarkAccess.activeURLs.isEmpty)

        let secondLaunch = PhotoLibraryViewModel(
            projectStore: store,
            bookmarkAccess: bookmarkAccess
        )
        await waitUntil { secondLaunch.photos.count == 2 && !secondLaunch.isAnalyzing }

        XCTAssertEqual(secondLaunch.projects.count, 1)
        XCTAssertEqual(secondLaunch.targetSelectionCount, 1)
        XCTAssertEqual(secondLaunch.photos.first(where: { $0.filename == "DSCF0001.JPG" })?.decision, .keep)
        XCTAssertEqual(
            secondLaunch.photos.first(where: {
                $0.filename == "DSCF0001.JPG"
            })?.curationCategory,
            .people
        )
        XCTAssertEqual(secondLaunch.selectedPhoto?.filename, "DSCF0001.JPG")

        guard let restoredProjectID = secondLaunch.activeProjectID else {
            return XCTFail("The restored project should be active.")
        }
        secondLaunch.requestDeleteProject(restoredProjectID)
        secondLaunch.confirmDeleteProject()

        XCTAssertTrue(secondLaunch.projects.isEmpty)
        XCTAssertTrue(store.catalog?.projects.isEmpty == true)
        XCTAssertNil(store.catalog?.activeProjectID)
        XCTAssertTrue(bookmarkAccess.activeURLs.isEmpty)
    }

    @MainActor
    func testActiveProjectCanBeDeletedWhileScanIsRunning() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "photo-curator-delete-during-scan-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MemoryProjectStore()
        let bookmarkAccess = TestBookmarkAccess()
        let library = PhotoLibraryViewModel(
            projectStore: store,
            bookmarkAccess: bookmarkAccess
        )

        library.scan(folder: root)

        let projectID = try XCTUnwrap(library.activeProjectID)
        XCTAssertTrue(library.isProjectNavigationLocked)

        library.requestDeleteProject(projectID)

        XCTAssertTrue(library.showProjectDeletionConfirmation)
        XCTAssertEqual(library.pendingProjectDeletion?.id, projectID)

        library.confirmDeleteProject()

        XCTAssertTrue(library.projects.isEmpty)
        XCTAssertNil(library.activeProjectID)
        XCTAssertFalse(library.isScanning)
        XCTAssertFalse(library.isAnalyzing)
        XCTAssertTrue(store.catalog?.projects.isEmpty == true)
        XCTAssertTrue(bookmarkAccess.activeURLs.isEmpty)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for asynchronous project restoration.")
    }
}
