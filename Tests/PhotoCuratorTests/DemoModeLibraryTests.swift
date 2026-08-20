import Foundation
import XCTest

@testable import PhotoCurator

final class DemoModeLibraryTests: XCTestCase {
    private final class MemoryProjectStore: PhotoProjectPersisting {
        var catalog: PersistedPhotoProjectCatalog?
        private(set) var saveCallCount = 0

        func load() throws -> PersistedPhotoProjectCatalog? {
            catalog
        }

        func save(_ catalog: PersistedPhotoProjectCatalog) throws {
            saveCallCount += 1
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

    func testOnboardingPreferenceShowsOnceAndSkipsReviewDemo() throws {
        let suiteName = "PhotoCuratorTests.Onboarding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(
            OnboardingPreferenceStore.shouldPresent(
                isDemoModeActive: false,
                defaults: defaults
            )
        )
        XCTAssertFalse(
            OnboardingPreferenceStore.shouldPresent(
                isDemoModeActive: true,
                defaults: defaults
            )
        )

        OnboardingPreferenceStore.markCompleted(defaults: defaults)

        XCTAssertEqual(
            defaults.integer(
                forKey: OnboardingPreferenceStore.completedVersionKey
            ),
            OnboardingPreferenceStore.currentVersion
        )
        XCTAssertFalse(
            OnboardingPreferenceStore.shouldPresent(
                isDemoModeActive: false,
                defaults: defaults
            )
        )
    }

    func testMakeSessionBuildsValidatedFourPhotoSelection() throws {
        let directory = try makeDemoDirectory()

        let session = try DemoModeLibrary.makeSession(resourceDirectory: directory)

        XCTAssertEqual(session.photos.count, 8)
        XCTAssertEqual(session.startingPhotos.count, 8)
        XCTAssertTrue(
            session.startingPhotos.allSatisfy {
                $0.aestheticRecommendations.isEmpty
            }
        )
        XCTAssertEqual(session.finalSelectionPhotoIDs.count, 4)
        XCTAssertEqual(session.runProgress.phase, .completed)
        XCTAssertEqual(session.runProgress.completedBatchCount, 2)
        XCTAssertEqual(session.runProgress.totalBatchCount, 2)
        XCTAssertEqual(session.runProgress.completedPhotoCount, 8)
        XCTAssertEqual(
            session.photos.filter {
                $0.curationCategory == .people
            }.count,
            4
        )
        XCTAssertEqual(
            session.photos.filter {
                $0.curationCategory == .scenery
            }.count,
            4
        )
        XCTAssertEqual(
            Set(session.photos.filter {
                session.finalSelectionPhotoIDs.contains($0.id)
            }.map(\.filename)),
            Set([
                "demo-01-coastal-road.jpg",
                "demo-04-harbor.jpg",
                "demo-05-ocean-overlook.jpg",
                "demo-08-sunset-beach.jpg",
            ])
        )
        XCTAssertTrue(session.photos.allSatisfy { $0.decision == .undecided })
        XCTAssertTrue(session.photos.allSatisfy { $0.aestheticRecommendations.count == 1 })
        XCTAssertTrue(session.photos.allSatisfy {
            guard let recommendation = $0.aestheticRecommendations.first else {
                return false
            }
            return recommendation.dimensions.scores.allSatisfy {
                (0...100).contains($0)
            } && !recommendation.summary.isEmpty
        })
        for category in PhotoCurationCategory.allCases {
            let ranked = try XCTUnwrap(
                session.rankedPhotoIDsByCategory[category]
            )
            let selected = try XCTUnwrap(
                session.finalSelectionPhotoIDsByCategory[category]
            )
            XCTAssertEqual(
                Set(ranked.prefix(2)),
                selected
            )
        }
    }

    func testMakeSessionRejectsMissingResource() throws {
        let directory = try makeDemoDirectory(excludingLastPhoto: true)

        XCTAssertThrowsError(
            try DemoModeLibrary.makeSession(resourceDirectory: directory)
        ) { error in
            XCTAssertEqual(error as? DemoModeError, .resourcesUnavailable)
        }
    }

    @MainActor
    func testDemoLaunchSkipsKeychainAndPersistence() throws {
        let directory = try makeDemoDirectory()
        let store = MemoryProjectStore()
        var keyCheckCount = 0

        let viewModel = PhotoLibraryViewModel(
            projectStore: store,
            bookmarkAccess: TestBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in
                keyCheckCount += 1
                return true
            },
            launchesInDemoMode: true,
            demoResourceDirectory: directory
        )

        XCTAssertTrue(viewModel.isDemoModeActive)
        XCTAssertFalse(viewModel.isAIModelKeyConfigured)
        XCTAssertEqual(keyCheckCount, 0)
        XCTAssertEqual(viewModel.projects.count, 1)
        XCTAssertEqual(viewModel.activeProjectID, DemoModeLibrary.projectID)
        XCTAssertEqual(viewModel.photos.count, 8)
        XCTAssertEqual(viewModel.targetSelectionCount, 4)
        // 教学从本地分析开始——那是真实用户导入文件夹后最先看到的一屏。
        XCTAssertEqual(viewModel.firstCurationGuideStep, .analyzePhotos)
        XCTAssertTrue(viewModel.isAnalyzing)
        viewModel.completeDemoAnalysisImmediately()
        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertEqual(viewModel.firstCurationGuideStep, .choosePeople)
        XCTAssertEqual(viewModel.curationScope, .all)
        XCTAssertTrue(viewModel.aiFinalSelectionPhotoIDs.isEmpty)
        XCTAssertEqual(viewModel.localAestheticCandidatePhotoIDs.count, 8)
        XCTAssertTrue(
            viewModel.photos.allSatisfy {
                $0.aestheticRecommendations.isEmpty
            }
        )
        XCTAssertNil(store.catalog)
        XCTAssertFalse(viewModel.canUndo)

        // 真实流程里 AI评分 不要求先手动保留任何照片：分析完就能直接评。
        viewModel.curationScope = .people
        XCTAssertEqual(viewModel.firstCurationGuideStep, .runPeopleAIScoring)
        XCTAssertEqual(viewModel.demoScorableCategory, .people)

        viewModel.completeDemoAIScoringImmediately()
        // 两类都评完之后，教学落在"采纳风景结果"。
        XCTAssertEqual(viewModel.firstCurationGuideStep, .acceptSceneryResults)
        // 评分、采纳和导出的入口分别在侧栏和底部命令条，大图盖着它们时必须先关掉；
        // 只有"查看评分"那一步恰恰要留在大图里。
        for step in [
            FirstCurationGuideStep.runPeopleAIScoring,
            .acceptPeopleResults,
            .switchSceneryAndScore,
            .acceptSceneryResults,
            .exportCopies,
        ] {
            XCTAssertTrue(
                step.shouldClosePhotoPreview,
                "\(step) 的入口不在大图里，必须先关掉大图"
            )
        }
        XCTAssertFalse(
            FirstCurationGuideStep.viewScore.shouldClosePhotoPreview
        )
        XCTAssertEqual(
            viewModel.statusMessage,
            "风景离线评分完成。点底部的“采纳”，把风景结果也变成保留。"
        )
        XCTAssertEqual(viewModel.aiFinalSelectionPhotoIDs.count, 4)
        for category in PhotoCurationCategory.allCases {
            XCTAssertEqual(
                (viewModel.aiFinalSelectionPhotoIDsByCategory[category] ?? [])
                    .count,
                2,
                "\(category) 应各自产出 2 张推荐"
            )
        }
        XCTAssertTrue(viewModel.localAestheticCandidatePhotoIDs.isEmpty)
        XCTAssertEqual(
            viewModel.photos.filter {
                !$0.aestheticRecommendations.isEmpty
            }.count,
            8
        )
        // 教学不再要求先手动保留一张：分析完就能直接评分。
        XCTAssertTrue(
            viewModel.photos.allSatisfy { $0.decision == .undecided },
            "AI评分 不该以任何人工决定为前置条件"
        )

        viewModel.curationScope = .scenery
        // 对同一张照片重复设置同一分类，不得清空既有评分。
        let sceneryPhotoID = try XCTUnwrap(
            viewModel.photos.first { $0.curationCategory == .scenery }?.id
        )
        viewModel.select(sceneryPhotoID)
        let scoreCountBeforeRepeatedCategory =
            viewModel.selectedPhoto?.aestheticRecommendations.count
        let finalIDsBeforeRepeatedCategory =
            viewModel.aiFinalSelectionPhotoIDs
        viewModel.setSelectedCurationCategory(.scenery)
        XCTAssertEqual(
            viewModel.selectedPhoto?.aestheticRecommendations.count,
            scoreCountBeforeRepeatedCategory
        )
        XCTAssertEqual(
            viewModel.aiFinalSelectionPhotoIDs,
            finalIDsBeforeRepeatedCategory
        )
        // 两类都评完之后教学停在"采纳风景结果"；采纳一次即推进到导出。
        XCTAssertEqual(viewModel.firstCurationGuideStep, .acceptSceneryResults)
        // 这个测试用 completeDemoAIScoringImmediately 一次评完两类，跳过了
        // 第 5 步的人物采纳，所以这里回到"全部"一次性采纳 4 张。
        viewModel.curationScope = .all
        XCTAssertEqual(viewModel.pendingAIFinalSelectionAcceptanceCount, 4)
        viewModel.acceptPendingAIFinalSelection()
        // 采纳同样是一次可撤销的人工决定——最终决定始终能收回。
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertEqual(viewModel.firstCurationGuideStep, .exportCopies)
        XCTAssertEqual(viewModel.keepers.count, 4)
        XCTAssertTrue(viewModel.canExport)

        viewModel.recordDemoExportCompleted()
        XCTAssertEqual(viewModel.firstCurationGuideStep, .completed)

        viewModel.prepareForTermination()
        XCTAssertNil(store.catalog)
        XCTAssertEqual(keyCheckCount, 0)

        viewModel.finishFirstCurationGuide()
        XCTAssertFalse(viewModel.isDemoModeActive)
        XCTAssertNil(viewModel.firstCurationGuideStep)
        XCTAssertTrue(viewModel.projects.isEmpty)
        XCTAssertTrue(viewModel.photos.isEmpty)
    }

    @MainActor
    func testDemoAIScoringRunsOfflineRequestWindows() async throws {
        let directory = try makeDemoDirectory()
        let viewModel = PhotoLibraryViewModel(
            projectStore: MemoryProjectStore(),
            bookmarkAccess: TestBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in
                XCTFail("Offline tutorial must not inspect Keychain state.")
                return false
            },
            launchesInDemoMode: true,
            demoResourceDirectory: directory
        )
        viewModel.completeDemoAnalysisImmediately()
        viewModel.curationScope = .people

        // 第 3 步：教学必须驱动侧栏那个真实入口，而且只对人物可用——
        // 真实流程就是一类评一次，一次评两类会教出一个不存在的流程。
        XCTAssertEqual(viewModel.demoScorableCategory, .people)
        XCTAssertTrue(
            viewModel.aiFinalSelectionAvailability(for: .people).canStart
        )
        XCTAssertFalse(
            viewModel.aiFinalSelectionAvailability(for: .scenery).canStart
        )

        // 并且要走一遍真实的发送确认框：第一次真实评分要花钱，
        // 用户不该到那一刻才第一次见到它。
        viewModel.prepareAIFinalSelectionRun(for: .people)
        XCTAssertTrue(viewModel.showAIFinalSelectionRunConfirmation)
        viewModel.submitConfirmedAIFinalSelectionRun()

        XCTAssertTrue(viewModel.isRunningDemoAIScoring)
        await waitUntil {
            viewModel.firstCurationGuideStep == .viewScore
        }
        XCTAssertFalse(viewModel.isRunningDemoAIScoring)
        XCTAssertEqual(viewModel.demoAIScoringCompletedPhotoCount, 4)
        XCTAssertTrue(
            (viewModel.aiFinalSelectionPhotoIDsByCategory[.scenery] ?? [])
                .isEmpty,
            "只评了人物，风景不该出现推荐结果"
        )
        // 完成回执与真实流程一致，网格会被带到该类型的"已AI评分"。
        XCTAssertNotNil(viewModel.completionNotice)

        // 看完评分、采纳人物结果之后，才轮到风景。
        XCTAssertNil(viewModel.demoScorableCategory)
        viewModel.confirmDemoScoreReview()
        XCTAssertEqual(viewModel.firstCurationGuideStep, .acceptPeopleResults)
        viewModel.acceptPendingAIFinalSelection()
        XCTAssertEqual(viewModel.firstCurationGuideStep, .switchSceneryAndScore)
        // 采纳做的事就是 decision = .keep——"保留"是流程的产出，不是评分的前置条件。
        XCTAssertEqual(viewModel.keepers(in: .people).count, 2)

        XCTAssertNil(viewModel.demoScorableCategory)
        viewModel.curationScope = .scenery
        XCTAssertEqual(viewModel.demoScorableCategory, .scenery)

        viewModel.prepareAIFinalSelectionRun(for: .scenery)
        XCTAssertTrue(viewModel.showAIFinalSelectionRunConfirmation)
        viewModel.submitConfirmedAIFinalSelectionRun()
        await waitUntil {
            viewModel.firstCurationGuideStep == .acceptSceneryResults
        }

        XCTAssertEqual(viewModel.demoAIScoringCompletedPhotoCount, 8)
        XCTAssertEqual(viewModel.aiFinalSelectionPhotoIDs.count, 4)
    }

    /// 教学不再强制"先保留一张"，但用户随时可以自己保留。
    /// 离线结果必须和真实评分一样尊重人工决定——否则教学会演示出一个
    /// "AI 会覆盖你的决定"的假象，而这恰恰是这个 App 承诺不做的事。
    @MainActor
    func testDemoScoringKeepsManualKeeperInRecommendations() throws {
        let directory = try makeDemoDirectory()
        let viewModel = PhotoLibraryViewModel(
            projectStore: MemoryProjectStore(),
            bookmarkAccess: TestBookmarkAccess(),
            apiKeyConfigurationCheck: { _ in false },
            launchesInDemoMode: true,
            demoResourceDirectory: directory
        )
        viewModel.completeDemoAnalysisImmediately()
        viewModel.curationScope = .people

        // 挑一张 AI 本来不会推荐的人物照片，人工保留它。
        let peopleIDs = viewModel.photos
            .filter { $0.curationCategory == .people }
            .map(\.id)
        let sessionPicks = try XCTUnwrap(
            DemoModeLibrary
                .makeSession(resourceDirectory: directory)
                .finalSelectionPhotoIDsByCategory[.people]
        )
        let manualKeeperID = try XCTUnwrap(
            peopleIDs.first { !sessionPicks.contains($0) }
        )
        viewModel.mark(photoID: manualKeeperID, as: .keep)

        viewModel.completeDemoAIScoringImmediately()

        XCTAssertTrue(
            (viewModel.aiFinalSelectionPhotoIDsByCategory[.people] ?? [])
                .contains(manualKeeperID),
            "人工保留的照片必须留在推荐结果里，AI 不得覆盖人工决定"
        )
        XCTAssertEqual(
            (viewModel.aiFinalSelectionPhotoIDsByCategory[.people] ?? []).count,
            2,
            "人物仍应收敛到目标张数"
        )
    }

    @MainActor
    func testSwitchingFromDemoRestoresOnlyPersistentProject() async throws {
        let demoDirectory = try makeDemoDirectory()
        let realDirectory = try makeRealProjectDirectory()
        let store = MemoryProjectStore()
        let bookmarkAccess = TestBookmarkAccess()
        var keyCheckCount = 0
        let viewModel = PhotoLibraryViewModel(
            projectStore: store,
            bookmarkAccess: bookmarkAccess,
            apiKeyConfigurationCheck: { _ in
                keyCheckCount += 1
                return true
            },
            launchesInDemoMode: false
        )
        viewModel.scan(folder: realDirectory)
        await waitUntil {
            viewModel.photos.count == 1
                && !viewModel.isScanning
                && !viewModel.isAnalyzing
        }
        guard let realProjectID = viewModel.activeProjectID else {
            return XCTFail("Expected a persistent project.")
        }
        let keyChecksBeforeDemo = keyCheckCount

        viewModel.startDemoMode(resourceDirectory: demoDirectory)
        // 分析进行中会锁住项目导航，这正是真实流程的行为；测试直接跳到完成态。
        viewModel.completeDemoAnalysisImmediately()

        XCTAssertTrue(viewModel.isDemoModeActive)
        XCTAssertEqual(keyCheckCount, keyChecksBeforeDemo)
        XCTAssertEqual(store.catalog?.activeProjectID, realProjectID)
        XCTAssertEqual(store.catalog?.projects.count, 1)
        XCTAssertFalse(
            store.catalog?.projects.contains {
                $0.id == DemoModeLibrary.projectID
            } ?? true
        )

        viewModel.activateProject(realProjectID)

        XCTAssertFalse(viewModel.isDemoModeActive)
        XCTAssertNil(viewModel.firstCurationGuideStep)
        XCTAssertEqual(viewModel.activeProjectID, realProjectID)
        XCTAssertEqual(viewModel.projects.count, 1)
        XCTAssertFalse(viewModel.projects.contains { $0.id == DemoModeLibrary.projectID })
        XCTAssertEqual(store.catalog?.activeProjectID, realProjectID)
        XCTAssertEqual(keyCheckCount, keyChecksBeforeDemo + 1)
    }

    private func makeDemoDirectory(excludingLastPhoto: Bool = false) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-demo-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let filenames = excludingLastPhoto
            ? DemoModeLibrary.filenames.dropLast()
            : DemoModeLibrary.filenames[...]
        for filename in filenames {
            try Data([0x44, 0x45, 0x4D, 0x4F]).write(
                to: directory.appendingPathComponent(filename)
            )
        }
        return directory
    }

    private func makeRealProjectDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-real-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("real-photo.jpg"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
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
        XCTAssertTrue(condition(), "Timed out waiting for asynchronous project analysis.")
    }
}
