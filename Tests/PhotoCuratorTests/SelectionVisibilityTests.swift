import Foundation
import XCTest
@testable import PhotoCurator

/// 「选中项必须始终可见」这条不变量。
///
/// `selectedPhotoID` 是全库概念，而底部检查条、决定命令和菜单快捷键都作用在它身上。
/// 一旦它不在当前网格里，用户就会在**看不见照片的情况下**改掉那张照片的保留/淘汰——
/// 这不是导航别扭，是静默的错误决定。
@MainActor
final class SelectionVisibilityTests: XCTestCase {
    func testSelectionIsClearedWhenNothingIsVisible() {
        let library = makeLibrary()
        library.updateVisiblePhotos(["a", "b", "c"])
        library.select("b")
        XCTAssertEqual(library.selectedPhotoID, "b")

        library.updateVisiblePhotos([])

        XCTAssertNil(
            library.selectedPhotoID,
            "可见集合为空时必须清空选中，否则底部仍能操作一张看不见的照片"
        )
        XCTAssertFalse(library.isSelectionVisible)
    }

    func testSelectionMovesToFirstWhenItLeavesTheVisibleSet() {
        let library = makeLibrary()
        library.updateVisiblePhotos(["a", "b", "c"])
        library.select("c")

        // 切换类型/筛选后是完全不同的一批照片。
        library.updateVisiblePhotos(["x", "y"])

        XCTAssertEqual(library.selectedPhotoID, "x")
        XCTAssertTrue(library.isSelectionVisible)
    }

    func testSelectionSurvivesWhenStillVisible() {
        let library = makeLibrary()
        library.updateVisiblePhotos(["a", "b", "c"])
        library.select("b")

        // 集合变化但仍包含当前选中项：不能把用户的位置抢走。
        library.updateVisiblePhotos(["b", "c", "d"])

        XCTAssertEqual(library.selectedPhotoID, "b")
    }

    /// 异步评分结果让空集合变成非空时，也要自动接上，而不是停在"没有选中项"。
    func testSelectionIsRestoredWhenResultsArriveLater() {
        let library = makeLibrary()
        library.updateVisiblePhotos([])
        XCTAssertNil(library.selectedPhotoID)

        library.updateVisiblePhotos(["r1", "r2"])

        XCTAssertEqual(library.selectedPhotoID, "r1")
    }

    /// 决定命令（底部按钮与菜单快捷键共用）必须在选中项不可见时禁用。
    func testDecisionsAreDisabledWhileSelectionIsInvisible() {
        let library = makeLibrary()
        library.updateVisiblePhotos(["a"])
        library.select("a")
        XCTAssertTrue(library.canDecideSelectedPhoto)

        library.updateVisiblePhotos([])

        XCTAssertFalse(
            library.canDecideSelectedPhoto,
            "看不见的照片不允许被淘汰或保留"
        )
    }

    private func makeLibrary() -> PhotoLibraryViewModel {
        PhotoLibraryViewModel(
            projectStore: NullStore(),
            bookmarkAccess: NullBookmarks(),
            apiKeyConfigurationCheck: { _ in false },
            modelVerificationCheck: { _ in false }
        )
    }
}

private struct NullStore: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? { nil }
    func save(_ catalog: PersistedPhotoProjectCatalog) throws {}
}

private struct NullBookmarks: SecurityScopedBookmarkAccessing {
    func makeReadOnlyBookmark(for folderURL: URL) throws -> Data { Data() }
    func resolve(_ bookmarkData: Data) throws -> ResolvedProjectBookmark {
        throw ProjectPersistenceError.inaccessibleBookmark
    }
    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}
