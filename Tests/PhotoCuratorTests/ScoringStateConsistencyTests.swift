import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import PhotoCurator

/// 评分状态与界面文案的一致性。
///
/// 这两条都是"改了数据但没同步派生状态"：一处忘了作废缓存，一处用了无条件文案。
@MainActor
final class ScoringStateConsistencyTests: XCTestCase {
    // MARK: - P2-1 演示评分完成后不该还有待评分

    /// 离线演示里每张卡都已经有 AI 分数，侧栏却仍显示"待评分 N 张"，
    /// 甚至同一张卡同时出现 AI 分和"待评分"。
    func testDemoScoringClearsPendingCandidates() {
        let library = makeLibrary()
        library.startDemoMode()
        library.completeDemoAnalysisImmediately()

        // 界面每帧都会读它；这一读把候选集合写进缓存。
        let beforeCount = library.localAestheticCandidatePhotoIDs.count
        XCTAssertGreaterThan(beforeCount, 0, "前提：演示开始时应当有待评分照片")

        library.completeDemoAIScoringImmediately()

        XCTAssertTrue(
            library.localAestheticCandidatePhotoIDs.isEmpty,
            "8 张全部评分完成后，待评分应为 0"
        )
        XCTAssertEqual(
            library.photos.filter { !$0.aestheticRecommendations.isEmpty }.count,
            8
        )
    }

    /// 更强的表述：任何一张已有评分的照片，都不能同时还在待评分集合里。
    func testNoPhotoIsBothScoredAndPending() {
        let library = makeLibrary()
        library.startDemoMode()
        library.completeDemoAnalysisImmediately()
        _ = library.localAestheticCandidatePhotoIDs.count
        library.completeDemoAIScoringImmediately()

        let pending = library.localAestheticCandidatePhotoIDs
        let scored = library.photos.filter { !$0.aestheticRecommendations.isEmpty }
        for photo in scored {
            XCTAssertFalse(
                pending.contains(photo.id),
                "\(photo.filename) 同时显示 AI 分与“待评分”"
            )
        }
    }

    // MARK: - P2-4 没有评分结果时不该说结果被重置

    /// 真实项目一次 AI 都没跑过时改分类，状态栏仍声称
    /// "人物与风景的评分结果已重新等待确认"——用户会以为自己弄丢了什么。
    func testCategoryChangeWithoutAnyScoresDoesNotClaimResetResults() async throws {
        let folder = try makeTemporaryImageFolder(count: 3)
        defer { try? FileManager.default.removeItem(at: folder) }

        let library = makeLibrary()
        library.scan(folder: folder)
        await waitUntil { !library.isProjectNavigationLocked && !library.photos.isEmpty }
        XCTAssertTrue(
            library.photos.allSatisfy { $0.aestheticRecommendations.isEmpty },
            "前提：本项目没有任何 AI 评分"
        )

        let target = try XCTUnwrap(library.photos.first)
        let newCategory: PhotoCurationCategory =
            target.curationCategory == .people ? .scenery : .people
        library.setCurationCategory(newCategory, for: target.id)

        XCTAssertFalse(
            library.statusMessage.contains("评分结果"),
            "没有任何评分时不应提及评分结果：\(library.statusMessage)"
        )
        XCTAssertTrue(
            library.statusMessage.contains(newCategory.title),
            "至少要说清楚归到了哪一类：\(library.statusMessage)"
        )
    }

    /// 确实存在评分时，仍然必须如实告知需要重新确认。
    func testCategoryChangeWithScoresStillWarnsAboutReset() {
        let library = makeLibrary()
        library.startDemoMode()
        library.completeDemoAnalysisImmediately()
        library.completeDemoAIScoringImmediately()

        let scored = library.photos.first { !$0.aestheticRecommendations.isEmpty }
        let target = try? XCTUnwrap(scored)
        guard let target else { return XCTFail("演示应当产出评分照片") }
        let newCategory: PhotoCurationCategory =
            target.curationCategory == .people ? .scenery : .people
        library.setCurationCategory(newCategory, for: target.id)

        XCTAssertTrue(
            library.statusMessage.contains("评分"),
            "有评分被清除时必须说明：\(library.statusMessage)"
        )
    }

    // MARK: - 辅助

    private func makeLibrary() -> PhotoLibraryViewModel {
        PhotoLibraryViewModel(
            projectStore: NullStore2(),
            bookmarkAccess: PassthroughBookmarks2(),
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
            .appendingPathComponent("photo-curator-consistency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<count {
            let url = root.appendingPathComponent("photo-\(index).jpg")
            let side = 256
            let context = try XCTUnwrap(
                CGContext(
                    data: nil, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )
            )
            for row in 0..<8 {
                for column in 0..<8 {
                    context.setFillColor(
                        gray: (row + column + index).isMultiple(of: 2) ? 0.1 : 0.9,
                        alpha: 1
                    )
                    context.fill(
                        CGRect(
                            x: column * side / 8, y: row * side / 8,
                            width: side / 8, height: side / 8
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
        return root
    }
}

private struct NullStore2: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? { nil }
    func save(_ catalog: PersistedPhotoProjectCatalog) throws {}
}

private struct PassthroughBookmarks2: SecurityScopedBookmarkAccessing {
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
