import XCTest
@testable import PhotoCurator

/// 教学期间不得显示完成回执横幅：任务条已经在讲下一步。
@MainActor
final class GuideBannerTests: XCTestCase {
    func testCompletionNoticeIsHiddenWhileGuideIsRunning() throws {
        let library = PhotoLibraryViewModel(
            projectStore: NullStoreBanner(),
            bookmarkAccess: PassthroughBookmarksBanner(),
            apiKeyConfigurationCheck: { _ in false }
        )
        library.startDemoMode()
        library.completeDemoAnalysisImmediately()
        library.curationScope = .people
        library.completeDemoAIScoringImmediately()

        XCTAssertNotNil(
            library.completionNotice,
            "回执仍要照常产生：它负责把网格带到该类型的“已AI评分”"
        )
        XCTAssertNotNil(library.firstCurationGuideStep)
        XCTAssertNil(
            library.visibleCompletionNotice,
            "教学进行中不得渲染回执横幅"
        )
    }
}

private struct NullStoreBanner: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? { nil }
    func save(_ catalog: PersistedPhotoProjectCatalog) throws {}
}

private struct PassthroughBookmarksBanner: SecurityScopedBookmarkAccessing {
    func makeReadOnlyBookmark(for folderURL: URL) throws -> Data {
        Data(folderURL.standardizedFileURL.path.utf8)
    }
    func resolve(_ bookmarkData: Data) throws -> ResolvedProjectBookmark {
        guard let path = String(data: bookmarkData, encoding: .utf8) else {
            throw ProjectPersistenceError.inaccessibleBookmark
        }
        return ResolvedProjectBookmark(
            url: URL(fileURLWithPath: path, isDirectory: true), isStale: false
        )
    }
    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}
