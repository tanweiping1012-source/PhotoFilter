import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import XCTest
@testable import PhotoCurator

/// 覆盖本轮修复引入的行为：单次解码流水线、可取消分析、schema 迁移、
/// 导出目录命名与跨时区拍摄时间。
final class AnalysisAndPersistenceFixTests: XCTestCase {
    // MARK: - 分析流水线

    func testPipelineSupportsHEICAndTIFFExtensions() {
        XCTAssertTrue(PhotoAnalysisPipeline.supportedExtensions.contains("heic"))
        XCTAssertTrue(PhotoAnalysisPipeline.supportedExtensions.contains("heif"))
        XCTAssertTrue(PhotoAnalysisPipeline.supportedExtensions.contains("tiff"))
        XCTAssertFalse(PhotoAnalysisPipeline.supportedExtensions.contains("mov"))
    }

    /// HEIC 是 iPhone 的默认格式；TIFF 常见于导出。两者都必须能真正解码出指纹与技术质量，
    /// 而不只是出现在扩展名白名单里。
    func testAnalyzesHEICAndTIFFContent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for (type, ext) in [("public.heic", "heic"), ("public.tiff", "tiff")] {
            let url = root.appendingPathComponent("sample.\(ext)")
            try writeImage(to: url, type: type)

            let result = PhotoAnalysisPipeline.analyze(url)

            XCTAssertNotNil(result.perceptualHash, "\(ext) 没有产出感知指纹")
            XCTAssertNotNil(result.technicalQuality, "\(ext) 没有产出技术质量")
            XCTAssertGreaterThan(result.technicalQuality?.sharpness ?? 0, 0)
        }
    }

    private func writeImage(to url: URL, type: String, blurRadius: Double = 0) throws {
        let side = 512
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
        // 画一组方块，保证有真实边缘可供清晰度与指纹计算。
        for row in 0..<8 {
            for column in 0..<8 {
                let isDark = (row + column).isMultiple(of: 2)
                context.setFillColor(gray: isDark ? 0.12 : 0.88, alpha: 1)
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
        var image = try XCTUnwrap(context.makeImage())
        if blurRadius > 0 {
            image = try blurring(image, radius: blurRadius)
        }
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil),
            "系统不支持写出 \(type)"
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// 清晰度指标必须真的区分“对上焦”和“糊了”，而不是只反映画面细节多少。
    func testBlurredCopyScoresLowerThanTheSharpOriginal() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sharpURL = root.appendingPathComponent("sharp.jpg")
        let blurredURL = root.appendingPathComponent("blurred.jpg")
        try writeImage(to: sharpURL, type: "public.jpeg")
        try writeImage(to: blurredURL, type: "public.jpeg", blurRadius: 6)

        let sharp = try XCTUnwrap(PhotoAnalysisPipeline.analyze(sharpURL).technicalQuality?.sharpness)
        let blurred = try XCTUnwrap(PhotoAnalysisPipeline.analyze(blurredURL).technicalQuality?.sharpness)

        XCTAssertGreaterThan(
            sharp,
            blurred * 1.5,
            "同一画面模糊后清晰度应明显下降：sharp=\(sharp) blurred=\(blurred)"
        )
    }

    func testImageURLsSkipsUnsupportedAndHiddenFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("day-2", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("a.JPG"))
        try Data().write(to: root.appendingPathComponent("b.heic"))
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        try Data().write(to: root.appendingPathComponent(".hidden.jpg"))
        try Data().write(to: nested.appendingPathComponent("c.png"))

        let urls = PhotoAnalysisPipeline.imageURLs(in: root)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["a.JPG", "b.heic", "c.png"])
    }

    /// 取消必须真的停止后台解码，而不是照跑完再丢弃结果。
    func testAnalysisStopsProducingResultsAfterCancellation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = try (0..<12).map { index -> URL in
            let url = root.appendingPathComponent("photo-\(index).jpg")
            try Data().write(to: url)
            return url
        }

        let counter = BatchCounter()
        let task = Task {
            await PhotoAnalysisPipeline.analyze(urls: urls, batchSize: 1, laneCount: 1) { results in
                await counter.add(results.count)
                await counter.waitForCancellationSignal()
            }
        }
        await counter.waitUntilFirstBatch()
        task.cancel()
        await counter.releaseCancellationSignal()
        await task.value

        let analyzed = await counter.total
        XCTAssertLessThan(analyzed, urls.count, "取消后不应继续分析剩余照片")
    }

    // MARK: - AI评分入口

    /// 入口不能因为"目标调高一张"就整个消失：不可用时必须给出可执行的原因。
    @MainActor
    func testAIStartIsBlockedWithAnActionableReasonInsteadOfVanishing() {
        let library = PhotoLibraryViewModel(
            projectStore: NullProjectStore(),
            bookmarkAccess: NullBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in false },
            modelVerificationCheck: { _ in false }
        )

        let availability = library.aiFinalSelectionAvailability(for: .people)

        XCTAssertFalse(availability.canStart)
        XCTAssertNotNil(
            availability.blockedReason,
            "不能开始时必须说明原因，而不是让入口消失"
        )
    }

    // MARK: - 持久化迁移

    func testOlderCatalogIsMigratedInsteadOfDiscarded() throws {
        let legacyProject = PersistedPhotoProject(
            schemaVersion: 1,
            id: UUID(),
            bookmarkData: Data("/tmp/trip".utf8),
            displayName: "京都",
            createdAt: Date(timeIntervalSince1970: 0),
            targetSelectionCount: 9,
            selectionTargets: nil,
            decisionsByRelativePath: ["DSCF0001.JPG": .keep]
        )
        let catalog = PersistedPhotoProjectCatalog(
            activeProjectID: legacyProject.id,
            projects: [legacyProject]
        )

        let migrated = try ProjectCatalogMigrator.migrated(catalog)

        XCTAssertEqual(migrated.projects.count, 1)
        XCTAssertEqual(migrated.projects[0].decisionsByRelativePath["DSCF0001.JPG"], .keep)
        // 旧版本只有一个总目标，迁移后必须补出人物/风景两个目标。
        XCTAssertEqual(
            migrated.projects[0].selectionTargets,
            PhotoSelectionTargets(legacyTotal: 9)
        )
    }

    func testFutureSchemaIsStillRejected() {
        let futureProject = PersistedPhotoProject(
            schemaVersion: PersistedPhotoProject.currentSchemaVersion + 1,
            id: UUID(),
            bookmarkData: Data(),
            displayName: "未来版本",
            createdAt: Date()
        )
        let catalog = PersistedPhotoProjectCatalog(
            activeProjectID: nil,
            projects: [futureProject]
        )

        XCTAssertThrowsError(try ProjectCatalogMigrator.migrated(catalog)) { error in
            XCTAssertEqual(error as? ProjectPersistenceError, .unsupportedSchema)
        }
    }

    // MARK: - 导出命名

    /// 系统日历是日本和历时，默认 DateFormatter 会写出“0007…”这样的年份。
    func testExportTimestampIgnoresANonGregorianSystemCalendar() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = ExportService.exportTimestamp(from: date)

        XCTAssertEqual(expected.count, 15)
        XCTAssertTrue(expected.hasPrefix("2023"), "导出目录名必须使用公历年份，实际为 \(expected)")
    }

    // MARK: - 跨时区拍摄时间

    func testEXIFOffsetIsUsedWhenPresent() throws {
        let tokyo = try XCTUnwrap(
            PhotoMetadataReader.parseEXIFDate("2025:07:27 09:00:00", offset: "+09:00")
        )
        let utc = try XCTUnwrap(
            PhotoMetadataReader.parseEXIFDate("2025:07:27 00:00:00", offset: "+00:00")
        )

        XCTAssertEqual(tokyo, utc, "同一绝对时刻的两种本地写法应该解析成同一个时间点")
    }

    func testMalformedEXIFOffsetFallsBackToLocalTime() {
        XCTAssertNil(PhotoMetadataReader.timeZone(fromEXIFOffset: "+9"))
        XCTAssertNil(PhotoMetadataReader.timeZone(fromEXIFOffset: "09:00"))
        XCTAssertNil(PhotoMetadataReader.timeZone(fromEXIFOffset: "+99:00"))
        XCTAssertEqual(
            PhotoMetadataReader.timeZone(fromEXIFOffset: "-05:30"),
            TimeZone(secondsFromGMT: -(5 * 3600 + 30 * 60))
        )
    }

    private func blurring(_ image: CGImage, radius: Double) throws -> CGImage {
        let input = CIImage(cgImage: image)
        let filter = try XCTUnwrap(CIFilter(name: "CIGaussianBlur"))
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        let output = try XCTUnwrap(filter.outputImage)
        let context = CIContext()
        // 裁回原始尺寸：高斯模糊会把画布向外扩展。
        return try XCTUnwrap(context.createCGImage(output, from: input.extent))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-fix-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private struct NullProjectStore: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? { nil }
    func save(_ catalog: PersistedPhotoProjectCatalog) throws {}
}

private struct NullBookmarkAccess: SecurityScopedBookmarkAccessing {
    func makeReadOnlyBookmark(for folderURL: URL) throws -> Data { Data() }
    func resolve(_ bookmarkData: Data) throws -> ResolvedProjectBookmark {
        throw ProjectPersistenceError.inaccessibleBookmark
    }
    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}

private actor BatchCounter {
    private(set) var total = 0
    private var firstBatchContinuations: [CheckedContinuation<Void, Never>] = []
    private var cancellationContinuations: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private var sawFirstBatch = false

    func add(_ count: Int) {
        total += count
        if !sawFirstBatch {
            sawFirstBatch = true
            firstBatchContinuations.forEach { $0.resume() }
            firstBatchContinuations = []
        }
    }

    func waitUntilFirstBatch() async {
        guard !sawFirstBatch else { return }
        await withCheckedContinuation { firstBatchContinuations.append($0) }
    }

    /// 第一批结果停在这里，直到测试发出取消信号，保证取消发生在分析过程中。
    func waitForCancellationSignal() async {
        guard !isReleased else { return }
        await withCheckedContinuation { cancellationContinuations.append($0) }
    }

    func releaseCancellationSignal() {
        isReleased = true
        cancellationContinuations.forEach { $0.resume() }
        cancellationContinuations = []
    }
}
