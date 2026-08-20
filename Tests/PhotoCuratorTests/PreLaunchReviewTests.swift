import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import PhotoCurator

/// 上线前复核发现的三处状态泄漏 / 误导性文案。
@MainActor
final class PreLaunchReviewTests: XCTestCase {
    // MARK: - 分析完成后候选池缓存

    /// 分析期间界面会反复读取候选池，那时 `localAestheticCandidatePlan` 一律返回 nil，
    /// 于是"空集合"被写进缓存。分析结束时如果不作废缓存，
    /// "待评分"徽标和筛选会一直是 0，直到用户碰巧改了某个决定。
    func testCandidatePoolIsVisibleImmediatelyAfterAnalysisFinishes() async throws {
        // 照片要足够多，分析才会真正跨越若干帧——这正是界面反复读取候选池的时机。
        let folder = try makeTemporaryImageFolder(count: 40)
        defer { try? FileManager.default.removeItem(at: folder) }

        let library = makeLibrary()
        library.scan(folder: folder)
        // 网格每帧都会读这个属性。分析期间读到的是空集合，
        // 这里模拟"用户一直看着网格，直到分析结束"。
        // 结果必须真的被用掉：`_ = 属性` 会被编译器优化成不读取，缓存也就不会被写坏。
        // 用 Task.yield() 而不是 sleep：这样一定能读到"最后一批分析结果已合并、
        // 相似家族仍在计算"的那段时间——正是缓存被写成空集合又不再作废的窗口。
        var observedDuringAnalysis = 0
        let deadline = Date().addingTimeInterval(120)
        while library.isScanning || library.isAnalyzing || library.isGroupingCandidates,
              Date() < deadline {
            observedDuringAnalysis += library.localAestheticCandidatePhotoIDs.count
            await Task.yield()
        }
        XCTAssertEqual(observedDuringAnalysis, 0, "分析期间不应给出待评分池")

        XCTAssertFalse(
            library.localAestheticCandidatePhotoIDs.isEmpty,
            "分析完成后待评分池必须立刻可见，而不是等下一次人工操作"
        )
    }

    // MARK: - 照片类型不跨项目泄漏

    /// 新扫描的照片还没有人物/风景分类。如果上一个项目停在"人物"，
    /// 新项目会在整个分析期间显示空网格，而界面上没有任何解释。
    func testFreshScanResetsCurationScopeToAll() async throws {
        let first = try makeTemporaryImageFolder(count: 3)
        let second = try makeTemporaryImageFolder(count: 3)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let library = makeLibrary()
        library.scan(folder: first)
        await waitUntil { !library.isProjectNavigationLocked && !library.photos.isEmpty }
        library.curationScope = .people

        library.scan(folder: second)
        await waitUntil { !library.isScanning && !library.photos.isEmpty }

        XCTAssertEqual(library.curationScope, .all)
        XCTAssertFalse(
            library.photos(in: library.curationScope).isEmpty,
            "刚扫描完的项目必须有照片可见"
        )
    }

    // MARK: - 无候选时的说明

    /// 候选池为空和"保留目标为 0"是两件事，不能共用一句"保留目标必须至少为 1 张"。
    func testEmptyCandidatePoolIsNotReportedAsAnEmptyTarget() {
        XCTAssertThrowsError(
            try AIFinalSelectionRunPlanner.makePlan(
                candidateLocalPhotoIDs: [],
                targetWinnerCount: 6
            )
        ) { error in
            XCTAssertEqual(
                error as? AIFinalSelectionRunPlanError,
                .emptyCandidatePool,
                "候选池为空时不能谎报成保留目标为 0"
            )
        }
    }

    // MARK: - 一轮评分只锁自己那一类

    /// 用户报告：评分过程中照片类型完全切不动。根因是一个全局开关，
    /// 而人物和风景本来就是两条独立赛道——另一类的浏览、决定和目标调整都不该受影响。
    func testActiveRunLocksOnlyItsOwnCategory() {
        XCTAssertTrue(
            AIFinalSelectionRunLock.isLocked(category: .scenery, runningCategory: .scenery)
        )
        XCTAssertFalse(
            AIFinalSelectionRunLock.isLocked(category: .people, runningCategory: .scenery),
            "风景正在评分时，人物照片必须仍可操作"
        )
        XCTAssertTrue(
            AIFinalSelectionRunLock.isLocked(category: nil, runningCategory: .scenery),
            "尚未分类的照片随时可能归入正在评分的类型，按锁定处理"
        )
        for category in PhotoCurationCategory.allCases {
            XCTAssertFalse(
                AIFinalSelectionRunLock.isLocked(category: category, runningCategory: nil),
                "没有任务在跑时不允许锁住任何东西"
            )
        }
        XCTAssertFalse(
            AIFinalSelectionRunLock.isLocked(category: nil, runningCategory: nil)
        )
    }

    /// 没有任务在跑时，界面上的决定按钮不能因为“可能有任务”而一直置灰。
    func testDecisionsAreAvailableWithoutAnActiveRun() async throws {
        let folder = try makeTemporaryImageFolder(count: 3)
        defer { try? FileManager.default.removeItem(at: folder) }

        let library = makeLibrary()
        library.scan(folder: folder)
        await waitUntil { !library.isProjectNavigationLocked && !library.photos.isEmpty }

        XCTAssertTrue(library.canDecideSelectedPhoto)
        library.markSelected(as: .keep)
        XCTAssertEqual(library.keepers.count, 1)
        XCTAssertTrue(library.canUndo)
        library.undo()
        XCTAssertTrue(library.keepers.isEmpty)
        XCTAssertFalse(library.canUndo)
    }

    // MARK: - 导出边界

    /// 导出到项目目录内部会做两件坏事：往只读的原图目录里写东西，
    /// 以及让下一次扫描把副本当成新照片，同一张照片变成两张。
    func testExportDestinationInsideProjectFolderIsRejected() async throws {
        let folder = try makeTemporaryImageFolder(count: 2)
        defer { try? FileManager.default.removeItem(at: folder) }

        let library = makeLibrary()
        library.scan(folder: folder)
        await waitUntil { !library.isProjectNavigationLocked && !library.photos.isEmpty }

        XCTAssertTrue(library.isInsideActiveProjectFolder(folder))
        XCTAssertTrue(
            library.isInsideActiveProjectFolder(
                folder.appendingPathComponent("导出", isDirectory: true)
            )
        )
        XCTAssertFalse(
            library.isInsideActiveProjectFolder(FileManager.default.temporaryDirectory)
        )
        // 同级的兄弟目录不算内部：仅仅路径前缀相同不构成包含关系。
        XCTAssertFalse(
            library.isInsideActiveProjectFolder(
                URL(fileURLWithPath: folder.path + "-export", isDirectory: true)
            )
        )
    }

    /// 清单里的类别目录名是中文，没有 BOM 的话用户在 Excel 里打开就是乱码。
    func testExportManifestCSVCarriesUTF8BOM() throws {
        let source = try makeTemporaryImageFolder(count: 1)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-csv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        var photo = PhotoItem(url: source.appendingPathComponent("photo-0.jpg"))
        photo.curationCategory = .scenery
        photo.decision = .keep

        let exportURL = try ExportService.copyCategorized(
            photos: [photo],
            to: destination
        )
        let csv = try Data(contentsOf: exportURL.appendingPathComponent("selection.csv"))

        XCTAssertEqual(Array(csv.prefix(3)), [0xEF, 0xBB, 0xBF], "selection.csv 缺少 UTF-8 BOM")
        let text = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(text.contains(PhotoCurationCategory.scenery.title))
    }

    // MARK: - 采纳之后再淘汰

    /// 用户报告：先采纳全部评分结果，再淘汰其中两张，被淘汰的照片仍然会被导出。
    /// 这里用离线教学走完整条路径：评分 → 采纳 → 淘汰 → 导出，直接检查落盘结果。
    func testRejectingAnAcceptedPhotoRemovesItFromExport() throws {
        let library = makeLibrary()
        library.startDemoMode()
        library.completeDemoAIScoringImmediately()
        library.acceptPendingAIFinalSelection()

        let acceptedIDs = library.keepers.map(\.id)
        XCTAssertFalse(acceptedIDs.isEmpty, "采纳后应当有保留照片")

        // 淘汰其中一张已采纳的照片。
        let rejectedID = try XCTUnwrap(acceptedIDs.first)
        let rejectedName = try XCTUnwrap(
            library.photos.first { $0.id == rejectedID }?.filename
        )
        library.mark(photoID: rejectedID, as: .reject)

        XCTAssertFalse(
            library.keepers.map(\.id).contains(rejectedID),
            "被淘汰的照片不能还留在保留集合里"
        )
        XCTAssertEqual(library.keepers.count, acceptedIDs.count - 1)

        // 真正导出一次，检查磁盘上的结果。
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-reject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let exportURL = try ExportService.copyCategorized(
            photos: library.keepers,
            to: destination
        )
        let exported = FileManager.default
            .enumerator(at: exportURL, includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.lastPathComponent } ?? []

        XCTAssertFalse(
            exported.contains(rejectedName),
            "被淘汰的 \(rejectedName) 出现在导出目录里"
        )
    }

    /// 淘汰是对 AI 结果的否决：那张照片必须同时退出"评分优先"。
    /// 否则它一边显示"淘汰"、一边还挂在 AI 选出的名单里，用户会以为自己那一下没生效。
    func testRejectingRemovesPhotoFromTopScoredSet() throws {
        let library = makeLibrary()
        library.startDemoMode()
        library.completeDemoAIScoringImmediately()
        library.acceptPendingAIFinalSelection()

        let victim = try XCTUnwrap(library.keepers.first { $0.curationCategory == .scenery })
        XCTAssertTrue(
            library.aiFinalSelectionPhotoIDs(for: .scenery).contains(victim.id),
            "前提：这张本来在评分优先集合里"
        )
        let beforeCount = library.aiFinalSelectionPhotoIDs(for: .scenery).count

        library.mark(photoID: victim.id, as: .reject)

        XCTAssertFalse(
            library.aiFinalSelectionPhotoIDs(for: .scenery).contains(victim.id),
            "被淘汰的照片仍留在评分优先集合里"
        )
        XCTAssertEqual(library.aiFinalSelectionPhotoIDs(for: .scenery).count, beforeCount - 1)
        XCTAssertEqual(library.counts(in: .scenery).reject, 1)
        XCTAssertFalse(library.keepers.contains { $0.id == victim.id })
    }

    // MARK: - 辅助

    private func makeLibrary() -> PhotoLibraryViewModel {
        PhotoLibraryViewModel(
            projectStore: ReviewNullProjectStore(),
            bookmarkAccess: ReviewPassthroughBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in false },
            modelVerificationCheck: { _ in false }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 60,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func makeTemporaryImageFolder(count: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<count {
            try writeImage(to: root.appendingPathComponent("photo-\(index).jpg"), seed: index)
        }
        return root
    }

    private func writeImage(to url: URL, seed: Int) throws {
        let side = 256
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        for row in 0..<8 {
            for column in 0..<8 {
                let isDark = (row + column + seed).isMultiple(of: 2)
                context.setFillColor(gray: isDark ? 0.1 : 0.9, alpha: 1)
                context.fill(
                    CGRect(
                        x: column * side / 8,
                        y: row * side / 8,
                        width: side / 8,
                        height: side / 8
                    )
                )
            }
        }
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private struct ReviewNullProjectStore: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? { nil }
    func save(_ catalog: PersistedPhotoProjectCatalog) throws {}
}

private struct ReviewPassthroughBookmarkAccess: SecurityScopedBookmarkAccessing {
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

    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}
