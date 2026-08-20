import Foundation
import XCTest
@testable import PhotoCurator

/// 会话状态的归属：每一条都必须绑定到产生它的那个项目、那一轮、那个用途。
///
/// 用量文案自称"累计"却每轮清零，换类型评分时数字会当着用户的面倒退；
/// 文件面板共用 AppKit 的全局最后目录，导出一次就把"新建筛选项目"带偏。
///
/// 完成回执的项目级隔离由 PC-31 门禁按结构断言：它只能由真实 AI 评分或导出
/// 产生，两条路径在单元测试里都不可达（前者要打网络，后者要过文件面板），
/// 为了可测而给生产代码加设置入口不值得。
@MainActor
final class ProjectScopedNoticeTests: XCTestCase {
    /// 导出目录不能变成"新建筛选项目"的默认位置。
    ///
    /// AppKit 所有 NSOpenPanel 共用 `NSOSPLastRootDirectory`，导出一次之后再新建
    /// 项目，来源面板就停在导出目录里。两个用途各记各的，互不影响。
    func testExportDirectoryDoesNotBecomeTheSourcePanelDefault() {
        let library = makeLibrary()
        let exportDirectory = URL(
            fileURLWithPath: "/tmp/photo-curator-exports", isDirectory: true
        )

        library.rememberDirectory(exportDirectory, for: .export)

        XCTAssertEqual(
            library.defaultDirectory(for: .export), exportDirectory,
            "导出面板应回到上一次的导出位置"
        )
        XCTAssertNotEqual(
            library.defaultDirectory(for: .source), exportDirectory,
            "导出目录不该成为「新建筛选项目」的默认位置"
        )
    }

    /// 来源记的是上一级：每个日期文件夹是一项独立任务，下一个多半是它的兄弟。
    func testSourcePanelRemembersParentAndDoesNotLeakIntoExport() {
        let library = makeLibrary()
        let dateFolder = URL(fileURLWithPath: "/tmp/travel/2026-08-20", isDirectory: true)

        library.rememberDirectory(dateFolder, for: .source)

        XCTAssertEqual(
            library.defaultDirectory(for: .source),
            URL(fileURLWithPath: "/tmp/travel", isDirectory: true),
            "记住上一级，下次才看得到同级的其他日期文件夹"
        )
        XCTAssertNil(
            library.defaultDirectory(for: .export),
            "选过照片来源不应反过来污染导出面板"
        )
    }

    /// 用量数字每轮清零，所以文案不能自称"累计"。
    ///
    /// 人物评分完成显示 37,712/2,982，开始风景后这两个数会被本轮小计覆盖。
    /// 只要标签写着"累计"，用户看到的就是一次用量倒退。
    func testUsageSummaryDescribesCurrentRunNotCumulativeTotal() throws {
        var progress = AIFinalSelectionRunProgress()
        progress.inputTokens = 37_712
        progress.outputTokens = 2_982

        let summary = try XCTUnwrap(progress.usageSummary)
        XCTAssertTrue(summary.contains("本轮"), "应说明这是本轮用量：\(summary)")
        XCTAssertFalse(
            summary.contains("累计"),
            "数字每轮清零，自称累计等于承诺了一个界面给不出的数：\(summary)"
        )
    }

    // MARK: - 辅助

    private func makeLibrary() -> PhotoLibraryViewModel {
        PhotoLibraryViewModel(
            projectStore: NullStoreNotice(),
            bookmarkAccess: PassthroughBookmarksNotice(),
            apiKeyConfigurationCheck: { _ in false },
            modelVerificationCheck: { _ in false }
        )
    }

}

private struct NullStoreNotice: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? { nil }
    func save(_ catalog: PersistedPhotoProjectCatalog) throws {}
}

private struct PassthroughBookmarksNotice: SecurityScopedBookmarkAccessing {
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
