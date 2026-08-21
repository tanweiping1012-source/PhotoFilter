import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import PhotoCurator

/// 停止之后重新开始，不能把已经评过分（也就是已经付过钱）的照片再送一遍。
///
/// v0.8.0 的真实体验里：18 张候选跑到 1/18 时点"停止"，侧栏已经显示"待评分 17 张"，
/// 但开始按钮和发送确认框仍然是 18 张，进度回到 0/18——第一张被重新发送、重新计费。
/// 原因是"待评分"减去了已评分照片，而真正生成运行计划的那条路径没有减。
@MainActor
final class AIFinalSelectionResumeTests: XCTestCase {
    /// 评过一张之后，新的运行计划只包含剩下的那些。
    func testResumingOnlyPlansUnscoredCandidates() async throws {
        let fixture = try await makeScoringReadyLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        let category = fixture.category

        let firstPlan = try XCTUnwrap(
            library.aiFinalSelectionRunPlan(for: category),
            "前提：应当能为\(category.title)排出一轮评分计划"
        )
        let allCandidateIDs = firstPlan.coveredPhotoIDs
        XCTAssertGreaterThan(allCandidateIDs.count, 1, "前提：候选要多于 1 张")

        let scoredID = try score(
            firstGroupOf: firstPlan,
            in: library,
            category: category
        )

        let resumedPlan = try XCTUnwrap(
            library.aiFinalSelectionRunPlan(for: category),
            "还有没评分的候选时，必须还能继续"
        )
        XCTAssertFalse(
            resumedPlan.coveredPhotoIDs.contains(scoredID),
            "已经付过费的照片不能被重新发送"
        )
        XCTAssertEqual(
            resumedPlan.coveredPhotoIDs,
            allCandidateIDs.subtracting([scoredID]),
            "继续这一轮应当正好覆盖剩下的候选"
        )
        XCTAssertEqual(
            resumedPlan.candidatePhotoCount,
            allCandidateIDs.count - 1
        )
    }

    /// 按钮和发送确认框上的数字必须是"这次要发送多少张"。
    func testStartControlCountsOnlyWhatWillBeSent() async throws {
        let fixture = try await makeScoringReadyLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        let category = fixture.category

        let before = library.aiFinalSelectionAvailability(for: category)
        XCTAssertTrue(before.canStart)
        XCTAssertEqual(before.alreadyScoredPhotoCount, 0)
        let totalCandidateCount = before.candidatePhotoCount

        let plan = try XCTUnwrap(library.aiFinalSelectionRunPlan(for: category))
        _ = try score(firstGroupOf: plan, in: library, category: category)

        let after = library.aiFinalSelectionAvailability(for: category)
        XCTAssertTrue(after.canStart, "还有剩余候选时必须能继续")
        XCTAssertEqual(
            after.candidatePhotoCount,
            totalCandidateCount - 1,
            "按钮上的张数必须减去已经评过的那张"
        )
        XCTAssertEqual(after.alreadyScoredPhotoCount, 1)

        library.prepareAIFinalSelectionRun(for: category)
        XCTAssertTrue(library.showAIFinalSelectionRunConfirmation)
        XCTAssertEqual(
            library.pendingAIFinalSelectionRunPlan?.candidatePhotoCount,
            totalCandidateCount - 1,
            "确认框说的张数就是会计费的张数"
        )
        XCTAssertEqual(library.pendingAIFinalSelectionResumedScoreCount, 1)
    }

    /// 候选全部评完之后，入口不能再拿同一批照片去花一次钱。
    func testFullyScoredPoolCannotBeChargedAgain() async throws {
        let fixture = try await makeScoringReadyLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        let category = fixture.category

        var guardCount = 0
        while let plan = library.aiFinalSelectionRunPlan(for: category), guardCount < 64 {
            _ = try score(firstGroupOf: plan, in: library, category: category)
            guardCount += 1
        }
        XCTAssertGreaterThan(guardCount, 1, "前提：应当评过不止一张")

        let availability = library.aiFinalSelectionAvailability(for: category)
        XCTAssertFalse(availability.canStart, "候选都有分了就不该再发送一遍")
        XCTAssertEqual(availability.candidatePhotoCount, 0)
        XCTAssertNotNil(availability.blockedReason, "置灰必须给出原因")

        library.prepareAIFinalSelectionRun(for: category)
        XCTAssertFalse(
            library.showAIFinalSelectionRunConfirmation,
            "没有要发送的照片时不该弹发送确认框"
        )
    }

    /// 换过模型的旧分数不能复用：省下的钱会变成一个由两套标准拼出来的错误名次。
    func testScoresFromAnotherModelAreNotReused() async throws {
        let fixture = try await makeScoringReadyLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        let category = fixture.category

        let plan = try XCTUnwrap(library.aiFinalSelectionRunPlan(for: category))
        let allCandidateIDs = plan.coveredPhotoIDs
        _ = try score(firstGroupOf: plan, in: library, category: category)
        XCTAssertEqual(
            library.aiFinalSelectionAvailability(for: category).alreadyScoredPhotoCount,
            1
        )

        library.selectedAIPreviewSize =
            library.selectedAIPreviewSize == .large ? .small : .large

        let replan = try XCTUnwrap(library.aiFinalSelectionRunPlan(for: category))
        XCTAssertEqual(
            replan.coveredPhotoIDs,
            allCandidateIDs,
            "换了预览尺寸就必须整池重评"
        )
        XCTAssertEqual(
            library.aiFinalSelectionAvailability(for: category).alreadyScoredPhotoCount,
            0
        )
    }

    /// 排序的全集是整个候选池：继续评分产出的名次必须覆盖两段分数。
    func testMergedScoresRankAcrossTheWholeCandidatePool() throws {
        let dimensions: [String: AestheticScoreDimensions] = [
            "a": makeDimensions(base: 40),
            "b": makeDimensions(base: 90),
            "c": makeDimensions(base: 65),
        ]
        // "a" 在停止前就评过，"b"/"c" 是继续之后新评的。
        let resumed = [AIFinalSelectionScore(photoID: "a", dimensions: dimensions["a"]!)]
        let fresh = ["b", "c"].map {
            AIFinalSelectionScore(photoID: $0, dimensions: dimensions[$0]!)
        }

        let ranked = try AIFinalSelectionRunValidator.rankedCandidatePhotoIDs(
            scores: resumed + fresh,
            candidatePhotoIDs: ["a", "b", "c"],
            weights: .balanced
        )
        XCTAssertEqual(ranked, ["b", "c", "a"])

        // 只用新评的那两张去排，必须被判定为"没覆盖全部候选"而不是悄悄生效。
        XCTAssertThrowsError(
            try AIFinalSelectionRunValidator.rankedCandidatePhotoIDs(
                scores: fresh,
                candidatePhotoIDs: ["a", "b", "c"],
                weights: .balanced
            )
        ) { error in
            XCTAssertEqual(
                error as? AIFinalSelectionRunValidationError,
                .incompleteCandidateScores
            )
        }
    }

    // MARK: - 辅助

    private struct Fixture {
        let library: PhotoLibraryViewModel
        let category: PhotoCurationCategory
        let folder: URL

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// 扫描一批合成照片，等本地分析跑完，并把 Key/模型校验都置为通过。
    /// 全程不联网、不读取 Keychain：注入的两个闭包直接返回 true。
    private func makeScoringReadyLibrary() async throws -> Fixture {
        let folder = try makeTemporaryImageFolder(count: 8)
        let library = PhotoLibraryViewModel(
            projectStore: ResumeNullStore(),
            bookmarkAccess: ResumePassthroughBookmarks(),
            apiKeyConfigurationCheck: { _ in true },
            modelVerificationCheck: { _ in true }
        )
        library.scan(folder: folder)
        await waitUntil { !library.isScanning && !library.photos.isEmpty }
        await waitUntil { !library.isAnalyzing && !library.isGroupingCandidates }
        library.refreshAIConfiguration()

        for category in PhotoCurationCategory.allCases {
            library.updateTargetSelectionCount(2, for: category)
        }
        guard let category = PhotoCurationCategory.allCases.first(where: {
            (library.localAestheticCandidatePlan(for: $0)?.candidateCount ?? 0) > 1
        }) else {
            try? FileManager.default.removeItem(at: folder)
            throw XCTSkip("合成照片没有产出足够的候选，跳过。")
        }
        library.curationScope = PhotoCurationScope(category)
        return Fixture(library: library, category: category, folder: folder)
    }

    /// 把计划里第一组照片当作"已经评完并付过费"写进照片自己身上。
    /// 走的是真实的 `applyAestheticReview`，所以分数来源也会按真实路径一并记录。
    @discardableResult
    private func score(
        firstGroupOf plan: AIFinalSelectionRunPlan,
        in library: PhotoLibraryViewModel,
        category: PhotoCurationCategory
    ) throws -> String {
        let group = try XCTUnwrap(plan.groups.first)
        let request = AestheticReviewRequestBuilder.make(
            scope: group.scope,
            localPhotoIDs: group.localPhotoIDs
        )
        let response = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: request.requestID,
            scope: request.scope,
            reviews: request.photos.enumerated().map { offset, input in
                AestheticReviewEntry(
                    photoID: input.photoID,
                    dimensions: makeDimensions(base: 70 + offset),
                    reasons: ["光线干净", "主体清楚"],
                    summary: "画面完整，可以保留。"
                )
            }
        )
        try library.applyAestheticReview(
            response,
            for: request,
            localPhotoIDs: group.localPhotoIDs,
            origin: AIFinalSelectionScoreOrigin(
                modelID: library.selectedAIModelID,
                previewSize: library.selectedAIPreviewSize
            )
        )
        return try XCTUnwrap(group.localPhotoIDs.first)
    }

    private func makeDimensions(base: Int) -> AestheticScoreDimensions {
        AestheticScoreDimensions(
            moment: base,
            composition: base,
            subject: base,
            lighting: base,
            storytelling: base
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
            .appendingPathComponent(
                "photo-curator-resume-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
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
                        gray: (row &* (index &+ 1) &+ column).isMultiple(of: 2) ? 0.1 : 0.9,
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
                CGImageDestinationCreateWithURL(
                    url as CFURL, "public.jpeg" as CFString, 1, nil
                )
            )
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        return root
    }
}

private struct ResumeNullStore: PhotoProjectPersisting {
    func load() throws -> PersistedPhotoProjectCatalog? { nil }
    func save(_ catalog: PersistedPhotoProjectCatalog) throws {}
}

private struct ResumePassthroughBookmarks: SecurityScopedBookmarkAccessing {
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
