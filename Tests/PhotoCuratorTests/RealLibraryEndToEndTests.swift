import Foundation
import XCTest
@testable import PhotoCurator

/// 用真实旅行照片跑一遍完整本地流程：扫描 → 分析 → 相似家族 → 待评分池 → 分类导出。
/// 默认跳过；只有显式提供照片目录时才运行：
///
///     PHOTO_BENCH_DIR=/path/to/photos swift test --filter RealLibraryEndToEnd
///
/// 全程只读用户目录，导出写入临时目录，不联网、不读取 Keychain。
@MainActor
final class RealLibraryEndToEndTests: XCTestCase {
    /// 目录在测试方法里解析，而不是 `setUpWithError`。
    ///
    /// `setUpWithError` 覆写的是 XCTestCase 上 nonisolated 的方法，在里面写 `@MainActor`
    /// 存储属性只有部分 Swift 版本允许——本机 6.2 能过，CI 的 6.1.2 直接报
    /// “main actor-isolated property can not be mutated from a nonisolated context”。
    private func resolveLibraryURL() throws -> URL {
        guard let directory = ProcessInfo.processInfo.environment["PHOTO_BENCH_DIR"] else {
            throw XCTSkip("未设置 PHOTO_BENCH_DIR，跳过真实照片端到端测试。")
        }
        return URL(fileURLWithPath: directory, isDirectory: true)
    }

    func testFullLocalCurationFlowOnRealLibrary() async throws {
        let libraryURL = try resolveLibraryURL()
        let store = MemoryProjectStore()
        let library = PhotoLibraryViewModel(
            projectStore: store,
            bookmarkAccess: PassthroughBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in false },
            modelVerificationCheck: { _ in false }
        )

        let sourceFingerprint = try fingerprint(of: libraryURL)
        let scanStart = Date()
        library.scan(folder: libraryURL)
        await waitUntil(timeout: 600) { !library.isScanning && !library.photos.isEmpty }
        let visibleAfter = Date().timeIntervalSince(scanStart)
        let photoCount = library.photos.count

        await waitUntil(timeout: 1200) { !library.isAnalyzing && !library.isGroupingCandidates }
        let analyzedAfter = Date().timeIntervalSince(scanStart)

        let peopleCount = library.photos.filter { $0.curationCategory == .people }.count
        let sceneryCount = library.photos.filter { $0.curationCategory == .scenery }.count
        let similarFamilies = SimilarityGrouper.groupCount(in: library.photos)
        let groupedPhotos = SimilarityGrouper.groupedPhotoCount(in: library.photos)
        let riskPhotos = library.photos.filter { !($0.technicalQuality?.risks.isEmpty ?? true) }.count
        let sharpnessRisk = library.photos.filter {
            $0.technicalQuality?.risks.contains(.lowSharpness) ?? false
        }.count
        let withCaptureDate = library.photos.filter { $0.captureDate != nil }.count
        let withHash = library.photos.filter { $0.perceptualHash != nil }.count

        print(
            """
            [E2E] photos=\(photoCount) \
            gridVisibleAfter=\(String(format: "%.1f", visibleAfter))s \
            analysisDoneAfter=\(String(format: "%.1f", analyzedAfter))s \
            people=\(peopleCount) scenery=\(sceneryCount) \
            similarFamilies=\(similarFamilies) photosInFamilies=\(groupedPhotos) \
            technicalRisks=\(riskPhotos) sharpnessRisks=\(sharpnessRisk) \
            captureDate=\(withCaptureDate)/\(photoCount) hash=\(withHash)/\(photoCount)
            """
        )

        XCTAssertGreaterThan(photoCount, 0)
        XCTAssertEqual(peopleCount + sceneryCount, photoCount, "每张照片都必须有类型")
        XCTAssertEqual(withHash, photoCount, "所有照片都应产出感知指纹")
        XCTAssertEqual(withCaptureDate, photoCount, "所有照片都应有拍摄时间")

        // 待评分池：容量是上限而不是配额，且同一相似家族最多一个代表。
        let familyIndex = CandidateFamilyIndex(photos: library.photos)
        for category in PhotoCurationCategory.allCases {
            guard let plan = library.localAestheticCandidatePlan(for: category) else { continue }
            let conflicts = familyIndex.conflicts(in: plan.localPhotoIDSet)
            print("[E2E] \(category.rawValue) 候选池=\(plan.candidateCount) 家族冲突=\(conflicts.count)")
            XCTAssertTrue(conflicts.isEmpty, "\(category.rawValue) 待评分池出现同一相似家族的多张照片")
            XCTAssertLessThanOrEqual(
                plan.candidateCount,
                LocalAestheticCandidatePlanner.absoluteMaximumCandidateCount
            )
        }

        // 人工保留到目标数量，然后按人物/风景分类复制导出。
        library.updateTargetSelectionCount(2, for: .people)
        library.updateTargetSelectionCount(2, for: .scenery)
        for category in PhotoCurationCategory.allCases {
            let ids = library.photos
                .filter { $0.curationCategory == category }
                .prefix(2)
                .map(\.id)
            XCTAssertEqual(ids.count, 2, "\(category.rawValue) 照片不足，无法完成导出验证")
            for id in ids {
                library.select(id)
                library.markSelected(as: .keep)
            }
        }

        let exportParent = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportParent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportParent) }

        let exportURL = try ExportService.copyCategorized(
            photos: library.photos.filter { $0.decision == .keep },
            to: exportParent
        )

        let peopleDirectory = exportURL.appendingPathComponent(PhotoCurationCategory.people.title)
        let sceneryDirectory = exportURL.appendingPathComponent(PhotoCurationCategory.scenery.title)
        XCTAssertEqual(try imageCount(in: peopleDirectory), 2)
        XCTAssertEqual(try imageCount(in: sceneryDirectory), 2)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: exportURL.appendingPathComponent("selection.json").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: exportURL.appendingPathComponent("selection.csv").path)
        )
        print("[E2E] 导出目录=\(exportURL.lastPathComponent)")

        // 最重要的不变量：原目录一个字节都不能变。
        XCTAssertEqual(
            try fingerprint(of: libraryURL),
            sourceFingerprint,
            "原照片目录在筛选与导出后被修改了"
        )
    }

    /// 目录内每个文件的“名字 + 大小 + 修改时间”，用于验证源目录只读。
    private func fingerprint(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .map { url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            return "\(url.lastPathComponent)|\(values.fileSize ?? -1)|\(modified)"
        }
        .sorted()
    }

    private func imageCount(in directory: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).count
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

private final class MemoryProjectStore: PhotoProjectPersisting {
    var catalog: PersistedPhotoProjectCatalog?

    func load() throws -> PersistedPhotoProjectCatalog? { catalog }

    func save(_ catalog: PersistedPhotoProjectCatalog) throws { self.catalog = catalog }
}

/// 测试进程不在沙箱内，直接放行 security scope 调用。
private struct PassthroughBookmarkAccess: SecurityScopedBookmarkAccessing {
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
