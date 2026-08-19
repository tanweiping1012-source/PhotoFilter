import AppKit
import Foundation

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published private(set) var photos: [PhotoItem] = []
    @Published private(set) var projects: [PhotoProject] = []
    @Published private(set) var activeProjectID: UUID?
    @Published private(set) var isDemoModeActive = false
    @Published private(set) var firstCurationGuideStep: FirstCurationGuideStep?
    @Published private(set) var isRunningDemoAIScoring = false
    @Published private(set) var demoAIScoringCompletedBatchCount = 0
    @Published private(set) var demoAIScoringCompletedPhotoCount = 0
    @Published var curationScope: PhotoCurationScope = .all {
        didSet {
            guard curationScope != oldValue else { return }
            advanceDemoForCurationScope()
        }
    }
    @Published var selectedPhotoID: String?
    @Published private(set) var selectedFolder: URL?
    @Published private(set) var isScanning = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isGroupingCandidates = false
    @Published private(set) var analysisCompleted = 0
    @Published private(set) var analysisTotal = 0
    @Published private(set) var selectionTargets =
        PhotoSelectionTargets.default {
        didSet {
            guard selectionTargets != oldValue else { return }
            persistActiveProjectState()
        }
    }
    @Published private(set) var statusMessage = String(localized: "选择一个旅行照片文件夹开始筛选。")
    @Published var showExportConfirmation = false
    @Published private(set) var pendingExportDirectory: URL?
    @Published var showAIFinalSelectionRunConfirmation = false
    @Published var showProjectDeletionConfirmation = false
    @Published private(set) var pendingProjectDeletion: PhotoProject?
    @Published var selectedAIModelID: AIModelID {
        didSet {
            guard selectedAIModelID != oldValue else { return }
            AIModelSelectionStore.save(selectedAIModelID)
            refreshAIConfiguration()
        }
    }
    @Published var selectedAIPreviewSize: AIReviewPreviewSize {
        didSet {
            guard selectedAIPreviewSize != oldValue else { return }
            AIReviewPreviewSizeStore.save(selectedAIPreviewSize)
        }
    }
    @Published private(set) var isAIModelKeyConfigured = false
    @Published private(set) var latestAIUsageMessage: String?
    /// 人物与风景分别保存完整 AI评分流程经过类别内排序后的结果。
    @Published private(set)
    var aiFinalSelectionPhotoIDsByCategory:
        [PhotoCurationCategory: Set<String>] = [:]
    @Published private(set) var aiFinalSelectionRunProgress = AIFinalSelectionRunProgress()
    @Published private(set)
    var aiFinalSelectionRunProgressByCategory:
        [PhotoCurationCategory: AIFinalSelectionRunProgress] = [:]
    @Published private(set) var pendingAIFinalSelectionRunPlan: AIFinalSelectionRunPlan?

    private var undoStack: [DecisionUndoEntry] = []
    private let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]
    private var analysisSessionID: UUID?
    private let analysisBatchSize = 32
    private var lastAestheticReviewAt: Date?
    private var aiFinalSelectionRunContext: AIFinalSelectionRunContext?
    private var aiFinalSelectionRunTask: Task<Void, Never>?
    private var aiFinalSelectionRunTaskID: UUID?
    private var pendingAIFinalSelectionModelSnapshot: AIModelDescriptor?
    private var pendingAIFinalSelectionPreviewSizeSnapshot: AIReviewPreviewSize?
    private var pendingAIFinalSelectionCategorySnapshot:
        PhotoCurationCategory?
    private var demoModeSession: DemoModeSession?
    private var demoAIScoringTask: Task<Void, Never>?
    private var demoGuidedKeeperPhotoID: String?
    private var projectSnapshots: [UUID: PhotoProjectSnapshot] = [:]
    private var persistedProjects: [UUID: PersistedPhotoProject] = [:]
    private var startedSecurityScopes: [UUID: URL] = [:]
    private let projectStore: any PhotoProjectPersisting
    private let bookmarkAccess: any SecurityScopedBookmarkAccessing
    private let apiKeyConfigurationCheck: (AIProviderID) -> Bool
    private let modelVerificationCheck: (AIModelDescriptor) -> Bool
    private var lastPersistentActiveProjectID: UUID?
    private var isRestoringPersistedState = false

    private struct DecisionUndoEntry {
        let previousDecisionsByPhotoID: [String: PhotoDecision]
    }

    private struct PhotoProjectSnapshot {
        let photos: [PhotoItem]
        let selectedPhotoID: String?
        let selectionTargets: PhotoSelectionTargets
        let statusMessage: String
        let latestAIUsageMessage: String?
        let aiFinalSelectionPhotoIDsByCategory:
            [PhotoCurationCategory: Set<String>]
        let aiFinalSelectionRunProgress: AIFinalSelectionRunProgress
        let aiFinalSelectionRunProgressByCategory:
            [PhotoCurationCategory: AIFinalSelectionRunProgress]
    }

    private struct AIFinalSelectionRunContext {
        let runID: UUID
        let plan: AIFinalSelectionRunPlan
        let model: AIModelDescriptor
        let previewSize: AIReviewPreviewSize
        let category: PhotoCurationCategory
        let lockedKeeperPhotoIDs: [String]
        let targetSelectionCount: Int
        var nextBatchIndex = 0
        var scoredCandidates: [AIFinalSelectionScore] = []
    }

    init(
        projectStore: any PhotoProjectPersisting = PhotoProjectDiskStore(),
        bookmarkAccess: any SecurityScopedBookmarkAccessing = SystemSecurityScopedBookmarkAccess(),
        initialAIModelID: AIModelID = AIModelSelectionStore.load(),
        initialAIPreviewSize: AIReviewPreviewSize = AIReviewPreviewSizeStore.load(),
        apiKeyConfigurationCheck: @escaping (AIProviderID) -> Bool = AIProviderKeyStore.hasSavedKey,
        modelVerificationCheck: @escaping (AIModelDescriptor) -> Bool = {
            AIModelVerificationStore.isVerified($0)
        },
        launchesInDemoMode: Bool = ProcessInfo.processInfo.arguments.contains("--review-demo"),
        demoResourceDirectory: URL? = nil
    ) {
        self.projectStore = projectStore
        self.bookmarkAccess = bookmarkAccess
        self.selectedAIModelID = initialAIModelID
        self.selectedAIPreviewSize = initialAIPreviewSize
        self.apiKeyConfigurationCheck = apiKeyConfigurationCheck
        self.modelVerificationCheck = modelVerificationCheck
        restorePersistedProjects()
        if launchesInDemoMode {
            cancelProjectWork()
            isScanning = false
            isAnalyzing = false
            isGroupingCandidates = false
            startDemoMode(
                resourceDirectory: demoResourceDirectory ?? DemoModeLibrary.resourceDirectory()
            )
        } else if activeProjectID != nil {
            refreshAIConfiguration()
        }
    }

    var selectedAIModel: AIModelDescriptor {
        AIModelCatalog.model(for: selectedAIModelID)
    }

    var isAIConfigurationLocked: Bool {
        isAIFinalSelectionRunActive
    }

    var selectedPhoto: PhotoItem? {
        guard let selectedPhotoID else { return nil }
        return photos.first { $0.id == selectedPhotoID }
    }

    var activeProject: PhotoProject? {
        guard let activeProjectID else { return nil }
        return projects.first { $0.id == activeProjectID }
    }

    func isDemoProject(_ project: PhotoProject) -> Bool {
        project.id == DemoModeLibrary.projectID
    }

    var isProjectNavigationLocked: Bool {
        isScanning
            || isAnalyzing
            || isAIFinalSelectionRunActive
            || isRunningDemoAIScoring
    }

    /// 旧调用点和旧项目迁移继续使用总目标；新界面按人物/风景分别编辑。
    var targetSelectionCount: Int {
        get { selectionTargets.total }
        set {
            selectionTargets = PhotoSelectionTargets(
                legacyTotal: newValue
            )
        }
    }

    var aiFinalSelectionPhotoIDs: Set<String> {
        aiFinalSelectionPhotoIDsByCategory.values.reduce(into: []) {
            $0.formUnion($1)
        }
    }

    var keepers: [PhotoItem] {
        SelectionRules.keepers(in: photos)
    }

    func photos(in scope: PhotoCurationScope) -> [PhotoItem] {
        photos.filter { scope.includes($0.curationCategory) }
    }

    func targetSelectionCount(
        for category: PhotoCurationCategory
    ) -> Int {
        selectionTargets[category]
    }

    func updateTargetSelectionCount(
        _ count: Int,
        for category: PhotoCurationCategory
    ) {
        guard !isAIFinalSelectionRunActive, !isDemoModeActive else {
            return
        }
        var updated = selectionTargets
        updated[category] = count
        selectionTargets = updated
    }

    func keepers(
        in category: PhotoCurationCategory
    ) -> [PhotoItem] {
        keepers.filter { $0.curationCategory == category }
    }

    func counts(
        in category: PhotoCurationCategory
    ) -> (keep: Int, reject: Int, undecided: Int) {
        photos
            .filter { $0.curationCategory == category }
            .reduce(into: (keep: 0, reject: 0, undecided: 0)) {
                result, photo in
                switch photo.decision {
                case .keep: result.keep += 1
                case .reject: result.reject += 1
                case .undecided: result.undecided += 1
                }
            }
    }

    func selectionTargetStatus(
        for category: PhotoCurationCategory
    ) -> SelectionTargetStatus {
        SelectionTarget.status(
            keptCount: keepers(in: category).count,
            targetCount: selectionTargets[category]
        )
    }

    var similarityGroupCount: Int {
        SimilarityGrouper.groupCount(in: photos)
    }

    var similarPhotoCount: Int {
        SimilarityGrouper.groupedPhotoCount(in: photos)
    }

    var technicalRiskPhotoCount: Int {
        photos.filter { !($0.technicalQuality?.risks.isEmpty ?? true) }.count
    }

    var aestheticRecommendationGroupCount: Int {
        Set(photos.flatMap { photo in
            photo.aestheticRecommendations.map { "\($0.scope.kind.rawValue)-\($0.scope.groupID)" }
        }).count
    }

    var aiGlobalRankingPhotoIDs: [String] {
        PhotoCurationCategory.allCases.flatMap {
            aiGlobalRankingPhotoIDs(for: $0)
        }
    }

    func aiGlobalRankingPhotoIDs(
        for category: PhotoCurationCategory
    ) -> [String] {
        photos.compactMap { photo -> (PhotoItem, AestheticRecommendation)? in
            guard photo.curationCategory == category else {
                return nil
            }
            guard let recommendation = photo.aestheticRecommendations.last(
                where: {
                    $0.scope.kind == .finalSelection
                        && $0.scope.category == category
                }
            ) else {
                return nil
            }
            return (photo, recommendation)
        }.sorted { lhs, rhs in
            AestheticScoreRanking.precedes(
                lhs.1,
                photoID: lhs.0.id,
                rhs.1,
                photoID: rhs.0.id
            )
        }.map(\.0.id)
    }

    func aiGlobalRank(for photoID: String) -> Int? {
        guard let photo = photos.first(where: { $0.id == photoID }),
              let category = photo.curationCategory,
              aiFinalSelectionRunProgress(for: category).phase
                == .completed,
              let index = aiGlobalRankingPhotoIDs(
                  for: category
              ).firstIndex(
                  of: photoID
              ) else {
            return nil
        }
        return index + 1
    }

    var selectionTargetStatus: SelectionTargetStatus {
        SelectionTarget.status(keptCount: keepers.count, targetCount: targetSelectionCount)
    }

    private var selectionProgressMessage: String {
        String(
            localized:
                "人物 \(keepers(in: .people).count)/\(selectionTargets.people)，风景 \(keepers(in: .scenery).count)/\(selectionTargets.scenery)"
        )
    }

    var keeperDiversityConflicts: [[String]] {
        CandidateFamilyIndex(photos: photos).conflicts(in: Set(keepers.map(\.id)))
    }

    func keeperDiversityConflicts(
        in category: PhotoCurationCategory
    ) -> [[String]] {
        CandidateFamilyIndex(photos: photos).conflicts(
            in: Set(keepers(in: category).map(\.id))
        )
    }

    var keeperDiversityConflictCount: Int {
        keeperDiversityConflicts.count
    }

    var canExport: Bool {
        !isAnalyzing
            && PhotoCurationCategory.allCases.allSatisfy {
                selectionTargetStatus(for: $0).isExact
            }
    }

    var canUndo: Bool {
        !undoStack.isEmpty && !isAIFinalSelectionRunActive
    }

    var pendingAIFinalSelectionAcceptanceCount: Int {
        pendingAIFinalSelectionPhotoIDs.count
    }

    private var pendingAIFinalSelectionPhotoIDs: Set<String> {
        let scopedIDs: Set<String>
        if let category = curationScope.category {
            scopedIDs =
                aiFinalSelectionPhotoIDsByCategory[category] ?? []
        } else {
            scopedIDs = aiFinalSelectionPhotoIDs
        }
        return photos.filter {
            scopedIDs.contains($0.id) && $0.decision == .undecided
        }.reduce(into: Set<String>()) { $0.insert($1.id) }
    }

    func aiFinalSelectionPhotoIDs(
        for category: PhotoCurationCategory
    ) -> Set<String> {
        aiFinalSelectionPhotoIDsByCategory[category] ?? []
    }

    func aiFinalSelectionRunProgress(
        for category: PhotoCurationCategory
    ) -> AIFinalSelectionRunProgress {
        if aiFinalSelectionRunContext?.category == category {
            return aiFinalSelectionRunProgress
        }
        return aiFinalSelectionRunProgressByCategory[category]
            ?? AIFinalSelectionRunProgress()
    }

    var displayedAIFinalSelectionRunProgress:
        AIFinalSelectionRunProgress {
        guard !isDemoModeActive else {
            return aiFinalSelectionRunProgress
        }
        if let category = curationScope.category {
            return aiFinalSelectionRunProgress(for: category)
        }
        if isAIFinalSelectionRunActive {
            return aiFinalSelectionRunProgress
        }
        let progresses = PhotoCurationCategory.allCases.compactMap {
            aiFinalSelectionRunProgressByCategory[$0]
        }
        guard !progresses.isEmpty else {
            return AIFinalSelectionRunProgress()
        }
        let completedPhotos = progresses.reduce(0) {
            $0 + $1.completedPhotoCount
        }
        let candidatePhotos = progresses.reduce(0) {
            $0 + $1.candidatePhotoCount
        }
        let completedTargets = progresses.reduce(0) {
            $0 + $1.targetWinnerCount
        }
        let allCompleted = progresses.count
            == PhotoCurationCategory.allCases.count
            && progresses.allSatisfy { $0.phase == .completed }
        return AIFinalSelectionRunProgress(
            phase: allCompleted ? .completed : .idle,
            completedPhotoCount: completedPhotos,
            candidatePhotoCount: candidatePhotos,
            targetWinnerCount: completedTargets
        )
    }

    var failedAIFinalSelectionPhotoRangeLabel: String? {
        guard aiFinalSelectionRunProgress.phase == .failed,
              let context = aiFinalSelectionRunContext,
              let range = context.plan.photoRange(
                  forGroupAt: context.nextBatchIndex
              ) else {
            return nil
        }
        return photoRangeLabel(range)
    }

    var analysisProgress: Double {
        guard analysisTotal > 0 else { return 0 }
        return Double(analysisCompleted) / Double(analysisTotal)
    }

    var analysisProgressLabel: String? {
        guard isAnalyzing else { return nil }
        if isGroupingCandidates {
            return String(localized: "正在识别相似照片…")
        }
        return String(localized: "正在本地分析 \(analysisCompleted) / \(analysisTotal) 张")
    }

    /// 只在当前人物或风景范围内计算待评分池。
    var localAestheticCandidatePlan: LocalAestheticCandidatePlan? {
        guard let category = curationScope.category else {
            return nil
        }
        return localAestheticCandidatePlan(for: category)
    }

    func localAestheticCandidatePlan(
        for category: PhotoCurationCategory
    ) -> LocalAestheticCandidatePlan? {
        guard !photos.isEmpty, !isAnalyzing else { return nil }
        return LocalAestheticCandidatePlanner.makePlan(
            for: photos.filter {
                $0.curationCategory == category
            },
            targetSelectionCount: selectionTargets[category]
        )
    }

    var localAestheticCandidatePhotoIDs: Set<String> {
        let candidateIDs: Set<String>
        if let category = curationScope.category {
            candidateIDs =
                localAestheticCandidatePlan(for: category)?
                    .localPhotoIDSet ?? []
        } else {
            candidateIDs = PhotoCurationCategory.allCases.reduce(
                into: Set<String>()
            ) { result, category in
                result.formUnion(
                    localAestheticCandidatePlan(for: category)?
                        .localPhotoIDSet ?? []
                )
            }
        }
        let scoredPhotoIDs = Set(
            photos
                .filter { photo in
                    photo.aestheticRecommendations.contains {
                        $0.scope.kind == .finalSelection
                            && $0.scope.category
                                == photo.curationCategory
                    }
                }
                .map(\.id)
        )
        return candidateIDs.subtracting(scoredPhotoIDs)
    }

    /// 所有候选独立评分完成后统一全局排序，再取剩余目标数量。
    var aiFinalSelectionRunPlan: AIFinalSelectionRunPlan? {
        guard let category = curationScope.category else {
            return nil
        }
        return aiFinalSelectionRunPlan(for: category)
    }

    func aiFinalSelectionRunPlan(
        for category: PhotoCurationCategory
    ) -> AIFinalSelectionRunPlan? {
        guard let candidatePlan =
                localAestheticCandidatePlan(for: category),
              candidatePlan.remainingSelectionCount > 0,
              keeperDiversityConflicts(in: category).isEmpty else {
            return nil
        }
        return try? AIFinalSelectionRunPlanner.makePlan(
            candidateLocalPhotoIDs: candidatePlan.localPhotoIDs,
            targetWinnerCount: candidatePlan.remainingSelectionCount,
            category: category
        )
    }

    var isAIFinalSelectionRunActive: Bool {
        aiFinalSelectionRunContext != nil
    }

    var canPrepareAIFinalSelectionRun: Bool {
        !isDemoModeActive
            && isAIModelKeyConfigured
            && !isAnalyzing
            && !isAIFinalSelectionRunActive
            && aiFinalSelectionRunPlan != nil
    }

    var pendingAIFinalSelectionModel: AIModelDescriptor {
        pendingAIFinalSelectionModelSnapshot ?? selectedAIModel
    }

    var pendingAIFinalSelectionPreviewSize: AIReviewPreviewSize {
        pendingAIFinalSelectionPreviewSizeSnapshot ?? selectedAIPreviewSize
    }

    var remainingAestheticReviewCooldown: Int {
        guard let lastAestheticReviewAt else { return 0 }
        let remaining = AIReviewConfiguration.minimumReviewInterval - Date().timeIntervalSince(lastAestheticReviewAt)
        return max(0, Int(remaining.rounded(.up)))
    }

    var counts: (keep: Int, reject: Int, undecided: Int) {
        photos.reduce(into: (keep: 0, reject: 0, undecided: 0)) { result, photo in
            switch photo.decision {
            case .keep: result.keep += 1
            case .reject: result.reject += 1
            case .undecided: result.undecided += 1
            }
        }
    }

    func startDemoMode(resourceDirectory: URL? = DemoModeLibrary.resourceDirectory()) {
        guard !isProjectNavigationLocked else {
            statusMessage = String(localized: "请等待当前分析完成，或先停止 AI 任务，再进入示例筛选。")
            return
        }
        guard let resourceDirectory else {
            statusMessage = DemoModeError.resourcesUnavailable.localizedDescription
            return
        }

        let session: DemoModeSession
        do {
            session = try DemoModeLibrary.makeSession(resourceDirectory: resourceDirectory)
        } catch {
            statusMessage = String(localized: "无法进入示例筛选：\(error.localizedDescription)")
            return
        }

        if activeProjectID != DemoModeLibrary.projectID {
            saveActiveProjectSnapshot()
            if let activeProjectID, persistedProjects[activeProjectID] != nil {
                lastPersistentActiveProjectID = activeProjectID
            }
        }
        cancelProjectWork()
        projectSnapshots.removeValue(forKey: DemoModeLibrary.projectID)
        projects.removeAll { $0.id == DemoModeLibrary.projectID }

        var project = PhotoProject(
            id: DemoModeLibrary.projectID,
            folderURL: session.resourceDirectory,
            displayName: String(localized: "第一次筛选 / 海岸公路旅行"),
            createdAt: Date(timeIntervalSince1970: 1_720_000_000),
            photoCount: session.photos.count,
            accessState: .available
        )
        project.isAnalysisComplete = true
        projects.insert(project, at: 0)
        activeProjectID = project.id
        isDemoModeActive = true
        curationScope = .all
        firstCurationGuideStep = .choosePeople
        demoModeSession = session
        isRunningDemoAIScoring = false
        demoAIScoringCompletedBatchCount = 0
        demoAIScoringCompletedPhotoCount = 0
        demoGuidedKeeperPhotoID = nil
        isAIModelKeyConfigured = false
        selectedFolder = session.resourceDirectory
        photos = session.startingPhotos
        selectedPhotoID = session.startingPhotos.first?.id
        selectionTargets = session.selectionTargets
        aiFinalSelectionPhotoIDsByCategory = [:]
        aiFinalSelectionRunProgressByCategory = [:]
        aiFinalSelectionRunProgress = AIFinalSelectionRunProgress(
            totalBatchCount: session.runProgress.totalBatchCount,
            candidatePhotoCount: session.runProgress.candidatePhotoCount,
            targetWinnerCount: session.runProgress.targetWinnerCount
        )
        latestAIUsageMessage = nil
        undoStack = []
        isScanning = false
        isAnalyzing = false
        isGroupingCandidates = false
        analysisCompleted = session.startingPhotos.count
        analysisTotal = session.startingPhotos.count
        statusMessage = String(
            localized:
                "示例筛选已准备：4 张人物、4 张风景，各保留 2 张。先选择“人物”。"
        )
    }

    private func advanceDemoForCurationScope() {
        guard isDemoModeActive else { return }
        if firstCurationGuideStep == .choosePeople,
           curationScope == .people {
            selectedPhotoID = photos.first {
                $0.curationCategory == .people
            }?.id
            firstCurationGuideStep = .inspectPhoto
            statusMessage = String(
                localized:
                    "人物照片已单独显示。现在打开任意一张人物照片检查大图。"
            )
        } else if firstCurationGuideStep == .switchToScenery,
                  curationScope == .scenery {
            selectedPhotoID = photos.first {
                $0.curationCategory == .scenery
                    && !$0.aestheticRecommendations.isEmpty
            }?.id
            firstCurationGuideStep = .viewScore
            statusMessage = String(
                localized:
                    "风景照片拥有独立排序。现在打开一张风景照片查看评分。"
            )
        }
    }

    func recordDemoPhotoPreviewOpened() {
        guard isDemoModeActive,
              firstCurationGuideStep == .inspectPhoto,
              let selectedPhotoID,
              photos.contains(where: { $0.id == selectedPhotoID }) else {
            return
        }
        demoGuidedKeeperPhotoID = selectedPhotoID
        if selectedPhoto?.decision == .keep {
            firstCurationGuideStep = .runAIScoring
        } else {
            firstCurationGuideStep = .keepPhoto
        }
        statusMessage = String(localized: "大图用于检查细节；现在将这张照片标记为保留。")
    }

    func recordDemoScoreReviewFinished() {
        confirmDemoScoreReview()
    }

    func confirmDemoScoreReview() {
        guard isDemoModeActive,
              firstCurationGuideStep == .viewScore,
              selectedPhoto?.aestheticRecommendations.isEmpty == false else {
            return
        }
        curationScope = .all
        firstCurationGuideStep = .acceptResults
        statusMessage = String(localized: "评分只提供解释和排序；请到“评分优先”确认最终结果。")
    }

    func startDemoAIScoring() {
        guard isDemoModeActive,
              firstCurationGuideStep == .runAIScoring,
              !isRunningDemoAIScoring,
              let session = demoModeSession,
              let guidedKeeperPhotoID = demoGuidedKeeperPhotoID,
              photos.first(where: { $0.id == guidedKeeperPhotoID })?.decision
                == .keep else {
            return
        }
        isRunningDemoAIScoring = true
        demoAIScoringCompletedBatchCount = 0
        demoAIScoringCompletedPhotoCount = 0
        aiFinalSelectionRunProgress.phase = .running
        aiFinalSelectionRunProgress.completedBatchCount = 0
        aiFinalSelectionRunProgress.completedPhotoCount = 0
        statusMessage = String(localized: "正在演示 AI评分：使用内置固定结果，不联网、不读取 Keychain。")

        demoAIScoringTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for batchNumber in 1...session.runProgress.totalBatchCount {
                    try await Task.sleep(for: .milliseconds(450))
                    try Task.checkCancellation()
                    self.applyDemoAIScoringBatch(
                        batchNumber,
                        session: session
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func completeDemoAIScoringImmediately() {
        guard isDemoModeActive, let session = demoModeSession else { return }
        for batchNumber in 1...session.runProgress.totalBatchCount {
            applyDemoAIScoringBatch(batchNumber, session: session)
        }
    }

    private func applyDemoAIScoringBatch(
        _ batchNumber: Int,
        session: DemoModeSession
    ) {
        guard (1...session.runProgress.totalBatchCount).contains(batchNumber) else {
            return
        }
        let groupID = session.scoreScopes[batchNumber - 1].groupID
        let scoredPhotoByID = Dictionary(
            uniqueKeysWithValues: session.photos.map { ($0.id, $0) }
        )
        for index in photos.indices {
            guard let scoredPhoto = scoredPhotoByID[photos[index].id],
                  let recommendation = scoredPhoto.aestheticRecommendations.first(
                      where: { $0.scope.groupID == groupID }
                  ) else {
                continue
            }
            photos[index].aestheticRecommendations.removeAll {
                $0.scope == recommendation.scope
            }
            photos[index].aestheticRecommendations.append(recommendation)
        }

        demoAIScoringCompletedBatchCount = max(
            demoAIScoringCompletedBatchCount,
            batchNumber
        )
        aiFinalSelectionRunProgress.completedBatchCount =
            demoAIScoringCompletedBatchCount
        demoAIScoringCompletedPhotoCount = photos.filter {
            !$0.aestheticRecommendations.isEmpty
        }.count
        aiFinalSelectionRunProgress.completedPhotoCount =
            demoAIScoringCompletedPhotoCount

        if demoAIScoringCompletedBatchCount
            == session.runProgress.totalBatchCount {
            isRunningDemoAIScoring = false
            demoAIScoringTask = nil
            aiFinalSelectionPhotoIDsByCategory =
                demoFinalSelectionPhotoIDsByCategory(
                for: session
            )
            aiFinalSelectionRunProgress = session.runProgress
            for category in PhotoCurationCategory.allCases {
                aiFinalSelectionRunProgressByCategory[category] =
                    AIFinalSelectionRunProgress(
                        phase: .completed,
                        completedPhotoCount: session.startingPhotos
                            .filter {
                                $0.curationCategory == category
                            }.count,
                        candidatePhotoCount: session.startingPhotos
                            .filter {
                                $0.curationCategory == category
                            }.count,
                        targetWinnerCount:
                            session.selectionTargets[category]
                    )
            }
            firstCurationGuideStep = .switchToScenery
            statusMessage = String(localized: "离线 AI评分完成，已返回照片网格。现在点击顶部“风景”。")
        } else {
            statusMessage = String(
                localized: "离线 AI评分：已评估 \(demoAIScoringCompletedPhotoCount) / \(session.runProgress.candidatePhotoCount) 张。"
            )
        }
    }

    private func demoFinalSelectionPhotoIDsByCategory(
        for session: DemoModeSession
    ) -> [PhotoCurationCategory: Set<String>] {
        guard let guidedKeeperPhotoID = demoGuidedKeeperPhotoID,
              let category = photos.first(where: {
                  $0.id == guidedKeeperPhotoID
              })?.curationCategory else {
            return session.finalSelectionPhotoIDsByCategory
        }
        let remainingIDs =
            session.rankedPhotoIDsByCategory[category, default: []]
                .filter {
            $0 != guidedKeeperPhotoID
        }
        var result = session.finalSelectionPhotoIDsByCategory
        result[category] = Set(
            [guidedKeeperPhotoID]
                + Array(
                    remainingIDs.prefix(
                        max(
                            0,
                            session.selectionTargets[category] - 1
                        )
                    )
                )
        )
        return result
    }

    func recordDemoExportCompleted() {
        guard isDemoModeActive,
              firstCurationGuideStep == .exportCopies else {
            return
        }
        firstCurationGuideStep = .completed
        statusMessage = String(
            localized: "第一次筛选已完成。点击“结束新手引导”返回。"
        )
    }

    func finishFirstCurationGuide() {
        guard isDemoModeActive,
              firstCurationGuideStep == .completed else {
            return
        }
        exitDemoMode()
    }

    func exitDemoMode() {
        guard isDemoModeActive else { return }
        let returnProjectID = lastPersistentActiveProjectID
        lastPersistentActiveProjectID = nil
        cancelProjectWork()
        projectSnapshots.removeValue(forKey: DemoModeLibrary.projectID)
        projects.removeAll { $0.id == DemoModeLibrary.projectID }
        activeProjectID = nil
        isDemoModeActive = false
        resetWorkspace()

        if let returnProjectID,
           projects.contains(where: { $0.id == returnProjectID }) {
            activateProject(returnProjectID)
        } else {
            statusMessage = String(localized: "已退出示例筛选。选择一个旅行照片文件夹开始筛选。")
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "选择旅行照片文件夹")
        panel.message = String(localized: "照片只会在本机读取；原图不会被修改。")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        openProject(folder: folder)
    }

    /// 测试和受控入口保留 `scan` 名称；一次扫描对应一个会话项目。
    func scan(folder: URL) {
        openProject(folder: folder)
    }

    func activateProject(_ projectID: UUID) {
        guard projectID != activeProjectID,
              let project = projects.first(where: { $0.id == projectID }) else { return }
        guard !isProjectNavigationLocked else {
            statusMessage = String(localized: "请等待当前分析完成，或先停止 AI 任务，再切换项目。")
            return
        }

        guard let folderURL = project.folderURL, project.accessState == .available else {
            reauthorizeProject(projectID)
            return
        }

        saveActiveProjectSnapshot()
        let wasDemoModeActive = isDemoModeActive
        activeProjectID = projectID
        if isDemoProject(project) {
            isDemoModeActive = true
            isAIModelKeyConfigured = false
            if let snapshot = projectSnapshots.removeValue(forKey: projectID) {
                restoreProjectSnapshot(snapshot, folder: folderURL)
            } else {
                startDemoMode(resourceDirectory: folderURL)
            }
            return
        }

        if wasDemoModeActive {
            demoAIScoringTask?.cancel()
            demoAIScoringTask = nil
            demoModeSession = nil
            firstCurationGuideStep = nil
            isRunningDemoAIScoring = false
            demoAIScoringCompletedBatchCount = 0
            demoAIScoringCompletedPhotoCount = 0
            projectSnapshots.removeValue(forKey: DemoModeLibrary.projectID)
            projects.removeAll { $0.id == DemoModeLibrary.projectID }
        }
        isDemoModeActive = false
        lastPersistentActiveProjectID = projectID
        refreshAIConfiguration()
        persistedProjects[projectID]?.lastOpenedAt = Date()
        if let snapshot = projectSnapshots.removeValue(forKey: projectID) {
            restoreProjectSnapshot(snapshot, folder: folderURL)
        } else {
            if let persisted = persistedProjects[projectID] {
                selectionTargets = persisted.selectionTargets
                    ?? PhotoSelectionTargets(
                        legacyTotal: persisted.targetSelectionCount
                    )
            } else {
                selectionTargets = .default
            }
            startScan(folder: folderURL, projectID: projectID)
        }
        persistProjectCatalog()
    }

    func requestDeleteProject(_ projectID: UUID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        pendingProjectDeletion = project
        showProjectDeletionConfirmation = true
    }

    func confirmDeleteProject() {
        guard let project = pendingProjectDeletion else { return }
        pendingProjectDeletion = nil
        showProjectDeletionConfirmation = false
        if isDemoProject(project) {
            exitDemoMode()
            return
        }
        projectSnapshots.removeValue(forKey: project.id)
        persistedProjects.removeValue(forKey: project.id)
        if lastPersistentActiveProjectID == project.id {
            lastPersistentActiveProjectID = nil
        }
        stopSecurityScope(for: project.id)
        projects = PhotoProjectCatalog.removing(project.id, from: projects)
        ThumbnailCache.shared.removeAll()

        if activeProjectID == project.id {
            cancelProjectWork()
            activeProjectID = nil
            resetWorkspace()
        }
        persistProjectCatalog()
        statusMessage = String(localized: "项目已从 App 中删除，缩略图缓存已释放；原照片没有被删除或修改。")
    }

    func cancelProjectDeletion() {
        pendingProjectDeletion = nil
        showProjectDeletionConfirmation = false
    }

    private func openProject(folder: URL) {
        if let existingProject = PhotoProjectCatalog.project(for: folder, in: projects) {
            if existingProject.id == activeProjectID {
                statusMessage = String(localized: "该文件夹已经是当前项目。")
            } else {
                activateProject(existingProject.id)
            }
            return
        }
        guard !isProjectNavigationLocked else {
            statusMessage = String(localized: "请等待当前分析完成，或先停止 AI 任务，再新建项目。")
            return
        }

        saveActiveProjectSnapshot()
        if isDemoModeActive {
            projectSnapshots.removeValue(forKey: DemoModeLibrary.projectID)
            projects.removeAll { $0.id == DemoModeLibrary.projectID }
        }
        let project = PhotoProject(folderURL: folder)
        guard let bookmarkData = try? bookmarkAccess.makeReadOnlyBookmark(for: folder) else {
            statusMessage = String(localized: "无法保存该文件夹的安全授权，请重新选择文件夹。")
            return
        }
        beginSecurityScope(for: project.id, url: folder)
        persistedProjects[project.id] = PersistedPhotoProject(
            id: project.id,
            bookmarkData: bookmarkData,
            displayName: project.displayName,
            createdAt: project.createdAt,
            targetSelectionCount: 12,
            selectionTargets: .default
        )
        projects.insert(project, at: 0)
        activeProjectID = project.id
        isDemoModeActive = false
        lastPersistentActiveProjectID = project.id
        refreshAIConfiguration()
        selectionTargets = .default
        persistProjectCatalog()
        startScan(folder: folder, projectID: project.id)
    }

    private func startScan(folder: URL, projectID: UUID) {
        aiFinalSelectionRunTask?.cancel()
        aiFinalSelectionRunTask = nil
        aiFinalSelectionRunTaskID = nil
        aiFinalSelectionRunContext = nil
        pendingAIFinalSelectionRunPlan = nil
        pendingAIFinalSelectionModelSnapshot = nil
        pendingAIFinalSelectionPreviewSizeSnapshot = nil
        showAIFinalSelectionRunConfirmation = false
        aiFinalSelectionRunProgress = AIFinalSelectionRunProgress()
        aiFinalSelectionRunProgressByCategory = [:]
        let sessionID = UUID()
        analysisSessionID = sessionID
        selectedFolder = folder.standardizedFileURL
        photos = []
        aiFinalSelectionPhotoIDsByCategory = [:]
        selectedPhotoID = nil
        undoStack = []
        isScanning = true
        isAnalyzing = false
        isGroupingCandidates = false
        analysisCompleted = 0
        analysisTotal = 0
        statusMessage = String(localized: "正在扫描 \(activeProject?.displayName ?? folder.lastPathComponent)…")

        let extensions = supportedExtensions
        let restoredDecisions = persistedProjects[projectID]?.decisionsByRelativePath ?? [:]
        let restoredCategoryOverrides =
            persistedProjects[projectID]?
                .categoryOverridesByRelativePath ?? [:]
        let restoredSelectedRelativePath = persistedProjects[projectID]?.selectedRelativePath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = Self.imageURLs(in: folder, supportedExtensions: extensions)
            let items = urls.map { url in
                let relativePath = ProjectRelativePath.make(for: url, relativeTo: folder)
                let restoredCategory = relativePath.flatMap {
                    restoredCategoryOverrides[$0]
                }
                return PhotoItem(
                    url: url,
                    decision: relativePath.flatMap {
                        restoredDecisions[$0]
                    } ?? .undecided,
                    curationCategory: restoredCategory,
                    isCurationCategoryUserAssigned:
                        restoredCategory != nil
                )
            }
            DispatchQueue.main.async {
                guard let self, self.analysisSessionID == sessionID else { return }
                self.photos = items
                self.updateProject(projectID) { project in
                    project.photoCount = items.count
                    project.isAnalysisComplete = false
                }
                self.selectedPhotoID = restoredSelectedRelativePath.flatMap { selectedPath in
                    items.first { item in
                        ProjectRelativePath.make(for: item.url, relativeTo: folder) == selectedPath
                    }?.id
                } ?? items.first?.id
                self.isScanning = false
                guard !items.isEmpty else {
                    self.statusMessage = String(localized: "没有找到 JPG、JPEG、PNG 或 WebP 图片。")
                    self.updateProject(projectID) { $0.isAnalysisComplete = true }
                    self.persistActiveProjectState()
                    return
                }

                self.analysisTotal = items.count
                self.isAnalyzing = true
                self.statusMessage = String(localized: "已显示 \(items.count) 张照片；分析会在后台逐步完成。现在即可开始手动选片。")
                self.persistActiveProjectState()
                self.startAnalysis(of: items, sessionID: sessionID)
            }
        }
    }

    func select(_ photoID: String) {
        selectedPhotoID = photoID
    }

    func setCurationCategory(
        _ category: PhotoCurationCategory,
        for photoID: String
    ) {
        guard !isAIFinalSelectionRunActive,
              let index = photos.firstIndex(where: {
                  $0.id == photoID
              }) else {
            return
        }
        guard photos[index].curationCategory != category else {
            if !photos[index].isCurationCategoryUserAssigned {
                photos[index].isCurationCategoryUserAssigned = true
                persistActiveProjectState()
            }
            return
        }
        photos[index].curationCategory = category
        photos[index].isCurationCategoryUserAssigned = true
        photos[index].aestheticRecommendations = []
        aiFinalSelectionPhotoIDsByCategory = [:]
        aiFinalSelectionRunProgressByCategory = [:]
        persistActiveProjectState()
        statusMessage = String(
            localized:
                "已将 \(photos[index].filename) 归为\(category.title)。人物与风景的评分结果已重新等待确认。"
        )
    }

    func setSelectedCurationCategory(
        _ category: PhotoCurationCategory
    ) {
        guard let selectedPhotoID else { return }
        setCurationCategory(category, for: selectedPhotoID)
    }

    func markSelected(as decision: PhotoDecision) {
        guard let selectedPhotoID else { return }
        mark(photoID: selectedPhotoID, as: decision)
    }

    func mark(photoID: String, as decision: PhotoDecision) {
        guard !isAIFinalSelectionRunActive else {
            statusMessage = String(localized: "AI评分进行中；请先停止本轮任务再修改人工决定。")
            return
        }
        if isDemoModeActive {
            if firstCurationGuideStep == .choosePeople {
                statusMessage = String(
                    localized: "请先在照片类型中选择“人物”。"
                )
                return
            }
            if firstCurationGuideStep == .inspectPhoto {
                statusMessage = String(
                    localized: "请先打开一张照片检查大图。"
                )
                return
            }
        }
        guard let index = photos.firstIndex(where: { $0.id == photoID }), photos[index].decision != decision else {
            return
        }
        storeUndoState(previousDecisionsByPhotoID: [photoID: photos[index].decision])
        photos[index].decision = decision
        persistActiveProjectState()
        statusMessage = String(
            localized:
                "已将 \(photos[index].filename) 标记为\(decision.title)。\(selectionProgressMessage)"
        )
        if isDemoModeActive,
           firstCurationGuideStep == .keepPhoto,
           decision == .keep {
            demoGuidedKeeperPhotoID = photoID
            firstCurationGuideStep = .runAIScoring
            statusMessage = String(localized: "人工决定已保留；下一步运行不联网的 AI评分演示。")
        }
    }

    func undo() {
        guard !isAIFinalSelectionRunActive else {
            statusMessage = String(localized: "AI评分进行中；请先停止本轮任务再撤销人工决定。")
            return
        }
        guard let previous = undoStack.popLast() else {
            statusMessage = String(localized: "没有可以撤销的操作。")
            return
        }
        for (photoID, decision) in previous.previousDecisionsByPhotoID {
            guard let index = photos.firstIndex(where: { $0.id == photoID }) else { continue }
            photos[index].decision = decision
        }
        persistActiveProjectState()
        statusMessage = String(
            localized:
                "已撤销上一次标记操作。\(selectionProgressMessage)"
        )
    }

    func acceptPendingAIFinalSelection() {
        guard !isAIFinalSelectionRunActive else { return }
        let pendingIDs = Array(pendingAIFinalSelectionPhotoIDs)
        guard !pendingIDs.isEmpty else {
            statusMessage = String(localized: "当前没有待确认的 AI评分结果。")
            return
        }
        let pendingIDSet = Set(pendingIDs)
        for category in PhotoCurationCategory.allCases {
            let pendingCategoryCount = photos.filter {
                pendingIDSet.contains($0.id)
                    && $0.curationCategory == category
            }.count
            guard keepers(in: category).count + pendingCategoryCount
                    <= selectionTargets[category] else {
                statusMessage = String(
                    localized:
                        "采纳后会超过\(category.title)目标 \(selectionTargets[category]) 张，请先调整已有保留项。"
                )
                return
            }
        }

        let previous = Dictionary(uniqueKeysWithValues: pendingIDs.map { ($0, PhotoDecision.undecided) })
        storeUndoState(previousDecisionsByPhotoID: previous)
        for index in photos.indices where pendingIDSet.contains(photos[index].id) {
            photos[index].decision = .keep
        }
        persistActiveProjectState()
        statusMessage = String(
            localized:
                "已采纳 \(pendingIDs.count) 张 AI评分结果。人物 \(keepers(in: .people).count)/\(selectionTargets.people)，风景 \(keepers(in: .scenery).count)/\(selectionTargets.scenery)。"
        )
        if isDemoModeActive,
           firstCurationGuideStep == .acceptResults {
            firstCurationGuideStep = .exportCopies
        }
    }

    /// 未来的云端适配器调用此入口。它会在主线程再次校验契约，且永远不覆盖人工 keep/reject。
    func applyAestheticReview(
        _ response: AestheticReviewResponse,
        for request: AestheticReviewRequest,
        localPhotoIDs: [String]
    ) throws {
        let updated = try AestheticReviewApplier.applying(
            response,
            for: request,
            localPhotoIDs: localPhotoIDs,
            to: photos
        )
        photos = updated
        statusMessage = String(localized: "已载入 \(localPhotoIDs.count) 张照片的 AI评分。最终取舍仍由你决定。")
    }

    func refreshAIConfiguration() {
        guard !isDemoModeActive else {
            isAIModelKeyConfigured = false
            return
        }
        isAIModelKeyConfigured = selectedAIModel.isReady
            && apiKeyConfigurationCheck(selectedAIModel.providerID)
            && modelVerificationCheck(selectedAIModel)
    }

    /// 只准备固定批次快照并展示确认弹窗；此方法不会读取图片、Keychain 或发送网络请求。
    func prepareAIFinalSelectionRun() {
        guard selectedAIModel.isReady else {
            statusMessage = String(localized: "请先在 AI评分设置中完成自定义接口和模型 ID 配置。")
            return
        }
        guard isAIModelKeyConfigured else {
            statusMessage = String(localized: "请先在 AI评分设置中验证\(selectedAIModel.providerAndModelDisplayName)及其 API Key。")
            return
        }
        guard !isAIFinalSelectionRunActive else {
            statusMessage = String(localized: "已有 AI评分任务正在运行。")
            return
        }
        guard let category = curationScope.category else {
            statusMessage = String(
                localized:
                    "请先在“照片类型”中选择人物或风景，再开始该类型的 AI评分。"
            )
            return
        }
        let conflicts = keeperDiversityConflicts(in: category)
        guard conflicts.isEmpty else {
            statusMessage = String(
                localized:
                    "\(category.title)中已有 \(conflicts.count) 组相似照片被同时保留；请先确认是否都要保留。"
            )
            return
        }
        guard let plan = aiFinalSelectionRunPlan else {
            statusMessage = String(localized: "当前待评分照片无法安全收敛到目标张数；请调整保留目标。")
            return
        }
        pendingAIFinalSelectionRunPlan = plan
        pendingAIFinalSelectionModelSnapshot = selectedAIModel
        pendingAIFinalSelectionPreviewSizeSnapshot = selectedAIPreviewSize
        pendingAIFinalSelectionCategorySnapshot = category
        showAIFinalSelectionRunConfirmation = true
    }

    /// 只从批量确认弹窗调用。确认后才读取 Keychain，并逐批生成已锁定尺寸的内存预览。
    func submitConfirmedAIFinalSelectionRun() {
        guard let plan = pendingAIFinalSelectionRunPlan,
              let model = pendingAIFinalSelectionModelSnapshot,
              let previewSize =
                pendingAIFinalSelectionPreviewSizeSnapshot,
              let category =
                pendingAIFinalSelectionCategorySnapshot else {
            return
        }
        showAIFinalSelectionRunConfirmation = false
        pendingAIFinalSelectionRunPlan = nil
        pendingAIFinalSelectionModelSnapshot = nil
        pendingAIFinalSelectionPreviewSizeSnapshot = nil
        pendingAIFinalSelectionCategorySnapshot = nil
        guard !isAIFinalSelectionRunActive else { return }
        guard let apiKey = readAPIKeyForReview(model: model) else { return }

        aiFinalSelectionPhotoIDsByCategory[category] = []
        let candidatePhotoIDs = plan.coveredPhotoIDs
        for index in photos.indices
        where candidatePhotoIDs.contains(photos[index].id) {
            photos[index].aestheticRecommendations.removeAll {
                $0.scope.kind == .finalSelection
                    && $0.scope.category == category
            }
        }
        aiFinalSelectionRunContext = AIFinalSelectionRunContext(
            runID: UUID(),
            plan: plan,
            model: model,
            previewSize: previewSize,
            category: category,
            lockedKeeperPhotoIDs: keepers(in: category).map(\.id),
            targetSelectionCount: selectionTargets[category]
        )
        aiFinalSelectionRunProgress = AIFinalSelectionRunProgress(
            phase: .running,
            completedBatchCount: 0,
            totalBatchCount: plan.requestCount,
            completedPhotoCount: 0,
            candidatePhotoCount: plan.candidatePhotoCount,
            targetWinnerCount: plan.targetWinnerCount,
            inputTokens: 0,
            outputTokens: 0,
            waitingSeconds: 0,
            failureMessage: nil
        )
        statusMessage = String(
            localized:
                "\(category.title) AI评分已开始：共 \(plan.candidatePhotoCount) 张；格式异常会自动重试 1 次，仍失败则停止。"
        )
        startAIFinalSelectionRunTask(apiKey: apiKey)
    }

    /// 暂停只影响后续照片；若当前网络请求已发出，会先安全接收并校验当前结果。
    func pauseAIFinalSelectionRun() {
        guard aiFinalSelectionRunProgress.phase == .running else { return }
        aiFinalSelectionRunProgress.phase = .paused
        statusMessage = String(localized: "AI评分已暂停；不会继续评估后面的照片。")
    }

    func resumeAIFinalSelectionRun() {
        guard aiFinalSelectionRunProgress.phase == .paused else { return }
        aiFinalSelectionRunProgress.phase = .running
        statusMessage = String(localized: "AI评分已继续。")
    }

    func retryFailedAIFinalSelectionRun() {
        guard aiFinalSelectionRunProgress.phase == .failed,
              let context = aiFinalSelectionRunContext,
              aiFinalSelectionRunTask == nil,
              let apiKey = readAPIKeyForReview(model: context.model) else {
            return
        }
        let failedRangeLabel = failedAIFinalSelectionPhotoRangeLabel
        aiFinalSelectionRunProgress.phase = .running
        aiFinalSelectionRunProgress.failureMessage = nil
        if let label = failedRangeLabel {
            statusMessage = String(localized: "正在重新评估第 \(label) 张。")
        } else {
            statusMessage = String(localized: "正在重新评估失败的照片。")
        }
        startAIFinalSelectionRunTask(apiKey: apiKey)
    }

    func stopAIFinalSelectionRun() {
        guard let context = aiFinalSelectionRunContext else {
            return
        }
        aiFinalSelectionRunProgress.phase = .stopped
        aiFinalSelectionRunProgress.waitingSeconds = 0
        aiFinalSelectionRunProgressByCategory[context.category] =
            aiFinalSelectionRunProgress
        aiFinalSelectionRunTask?.cancel()
        aiFinalSelectionRunTask = nil
        aiFinalSelectionRunTaskID = nil
        aiFinalSelectionRunContext = nil
        statusMessage = String(localized: "AI评分已停止；已完成照片的评分仍保留，但不会形成最终结果。")
    }

    private func startAIFinalSelectionRunTask(apiKey: String) {
        guard let runID = aiFinalSelectionRunContext?.runID else { return }
        aiFinalSelectionRunTaskID = runID
        aiFinalSelectionRunTask = Task { [weak self] in
            guard let self else { return }
            await self.executeAIFinalSelectionRun(apiKey: apiKey, runID: runID)
        }
    }

    private func executeAIFinalSelectionRun(apiKey: String, runID: UUID) async {
        defer {
            if aiFinalSelectionRunTaskID == runID {
                aiFinalSelectionRunTask = nil
                aiFinalSelectionRunTaskID = nil
            }
        }
        do {
            while let context = aiFinalSelectionRunContext,
                  context.runID == runID,
                  context.nextBatchIndex < context.plan.groups.count {
                try await waitForAIFinalSelectionBatchSlot(runID: runID)
                try Task.checkCancellation()

                let batchIndex = context.nextBatchIndex
                let group = context.plan.groups[batchIndex]
                guard let photoRange = context.plan.photoRange(
                    forGroupAt: batchIndex
                ) else {
                    throw CancellationError()
                }
                let request = AestheticReviewRequestBuilder.make(
                    scope: group.scope,
                    localPhotoIDs: group.localPhotoIDs
                )
                let rangeLabel = photoRangeLabel(photoRange)
                statusMessage = String(localized: "正在评估第 \(rangeLabel) 张，共 \(context.plan.candidatePhotoCount) 张；正在生成\(context.previewSize.displayName)安全图片…")
                let previews = try await makeAestheticReviewPreviews(
                    candidateGroup: group,
                    request: request,
                    previewSize: context.previewSize
                )
                let result = try await requestAIFinalSelectionReview(
                    request: request,
                    previews: previews,
                    apiKey: apiKey,
                    model: context.model,
                    previewSize: context.previewSize,
                    runID: runID,
                    photoRange: photoRange,
                    totalPhotoCount: context.plan.candidatePhotoCount
                )
                guard aiFinalSelectionRunContext?.runID == runID else {
                    throw CancellationError()
                }
                try applyAestheticReview(
                    result.response,
                    for: request,
                    localPhotoIDs: group.localPhotoIDs
                )
                let scoredPhotos = try AIFinalSelectionRunValidator.scoredPhotos(
                    from: result.response,
                    request: request,
                    localPhotoIDs: group.localPhotoIDs
                )

                guard var updatedContext = aiFinalSelectionRunContext,
                      updatedContext.runID == runID,
                      updatedContext.nextBatchIndex == batchIndex else {
                    throw CancellationError()
                }
                updatedContext.scoredCandidates.append(
                    contentsOf: scoredPhotos
                )
                updatedContext.nextBatchIndex += 1
                aiFinalSelectionRunContext = updatedContext
                aiFinalSelectionRunProgress.completedBatchCount = updatedContext.nextBatchIndex
                aiFinalSelectionRunProgress.completedPhotoCount =
                    photoRange.upperBound
                aiFinalSelectionRunProgress.inputTokens += result.usage.inputTokens ?? 0
                aiFinalSelectionRunProgress.outputTokens += result.usage.outputTokens ?? 0
                latestAIUsageMessage = aiFinalSelectionRunProgress.usageSummary
                statusMessage = String(localized: "AI评分已评估 \(photoRange.upperBound) / \(updatedContext.plan.candidatePhotoCount) 张。")
            }
            try completeAIFinalSelectionRun(runID: runID)
        } catch is CancellationError {
            guard aiFinalSelectionRunContext?.runID == runID else { return }
            if aiFinalSelectionRunProgress.phase != .stopped {
                aiFinalSelectionRunProgress.phase = .stopped
                aiFinalSelectionRunContext = nil
                statusMessage = String(localized: "AI评分已停止；不会形成不完整的评分结果。")
            }
        } catch {
            guard let context = aiFinalSelectionRunContext,
                  context.runID == runID else {
                return
            }
            aiFinalSelectionRunProgress.phase = .failed
            aiFinalSelectionRunProgress.waitingSeconds = 0
            aiFinalSelectionRunProgress.failureMessage = error.localizedDescription
            aiFinalSelectionRunProgressByCategory[context.category] =
                aiFinalSelectionRunProgress
            statusMessage = String(localized: "AI评分失败并停止：\(error.localizedDescription)")
        }
    }

    private func requestAIFinalSelectionReview(
        request: AestheticReviewRequest,
        previews: [AestheticReviewPreview],
        apiKey: String,
        model: AIModelDescriptor,
        previewSize: AIReviewPreviewSize,
        runID: UUID,
        photoRange: ClosedRange<Int>,
        totalPhotoCount: Int
    ) async throws -> AestheticReviewResult {
        var completedRetryCount = 0

        while true {
            try Task.checkCancellation()
            guard aiFinalSelectionRunContext?.runID == runID else {
                throw CancellationError()
            }
            lastAestheticReviewAt = Date()
            do {
                return try await AestheticReviewClient(model: model).review(
                    request: request,
                    previews: previews,
                    previewSize: previewSize,
                    apiKey: apiKey
                )
            } catch {
                guard AIFinalSelectionRetryPolicy.shouldRetry(
                    error,
                    completedRetryCount: completedRetryCount
                ) else {
                    throw error
                }
                completedRetryCount += 1
                let rangeLabel = photoRangeLabel(photoRange)
                statusMessage = String(localized: "第 \(rangeLabel) 张的评分格式异常；将在冷却后自动重试（\(completedRetryCount)/\(AIFinalSelectionRetryPolicy.maximumAutomaticRetryCount)）。")
                try await waitForAIFinalSelectionBatchSlot(runID: runID)
                statusMessage = String(localized: "正在重新评估第 \(rangeLabel) 张，共 \(totalPhotoCount) 张…")
            }
        }
    }

    private func photoRangeLabel(
        _ range: ClosedRange<Int>
    ) -> String {
        range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
    }

    private func waitForAIFinalSelectionBatchSlot(runID: UUID) async throws {
        while true {
            try Task.checkCancellation()
            guard aiFinalSelectionRunContext?.runID == runID else {
                throw CancellationError()
            }
            if aiFinalSelectionRunProgress.phase == .paused {
                aiFinalSelectionRunProgress.waitingSeconds = 0
                try await Task.sleep(for: .milliseconds(250))
                continue
            }
            guard aiFinalSelectionRunProgress.phase == .running else {
                throw CancellationError()
            }
            let remaining = remainingAestheticReviewCooldown
            aiFinalSelectionRunProgress.waitingSeconds = remaining
            if remaining == 0 { return }
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func completeAIFinalSelectionRun(runID: UUID) throws {
        guard let context = aiFinalSelectionRunContext,
              context.runID == runID else {
            throw CancellationError()
        }
        let rankedCandidatePhotoIDs =
            try AIFinalSelectionRunValidator.rankedCandidatePhotoIDs(
                scores: context.scoredCandidates,
                candidatePhotoIDs: context.plan.coveredPhotoIDs
            )
        let finalSelectionPhotoIDs = try AIFinalSelectionRunValidator.finalSelectionIDs(
            rankedCandidatePhotoIDs: rankedCandidatePhotoIDs,
            lockedKeeperPhotoIDs: context.lockedKeeperPhotoIDs,
            candidatePhotoIDs: context.plan.coveredPhotoIDs,
            targetSelectionCount: context.targetSelectionCount
        )
        guard CandidateFamilyIndex(photos: photos).conflicts(in: finalSelectionPhotoIDs).isEmpty else {
            throw AIFinalSelectionRunValidationError.duplicateCandidateFamily
        }
        aiFinalSelectionPhotoIDsByCategory[context.category] =
            finalSelectionPhotoIDs
        aiFinalSelectionRunProgress.phase = .completed
        aiFinalSelectionRunProgress.completedPhotoCount =
            context.plan.candidatePhotoCount
        aiFinalSelectionRunProgress.waitingSeconds = 0
        aiFinalSelectionRunProgressByCategory[context.category] =
            aiFinalSelectionRunProgress
        aiFinalSelectionRunContext = nil
        statusMessage = String(
            localized:
                "\(context.category.title) AI评分完成：已得到 \(finalSelectionPhotoIDs.count) 张评分优先照片。请在“评分优先”筛选中人工确认。"
        )
    }

    private func readAPIKeyForReview(
        model: AIModelDescriptor
    ) -> String? {
        guard model.isReady else {
            statusMessage = String(localized: "当前 AI 模型配置不完整，未发送请求。")
            return nil
        }
        do {
            guard let apiKey = try AIProviderKeyStore.read(for: model.providerID) else {
                refreshAIConfiguration()
                statusMessage = String(localized: "无法读取\(model.providerID.displayName) API Key，请在 AI 设置中重新保存。")
                return nil
            }
            return apiKey
        } catch {
            refreshAIConfiguration()
            statusMessage = String(localized: "无法读取\(model.providerID.displayName) API Key，请在 AI 设置中重新保存。")
            return nil
        }
    }

    func requestExport() {
        guard canExport else {
            statusMessage = String(
                localized:
                    "尚不能导出：人物 \(keepers(in: .people).count)/\(selectionTargets.people)，风景 \(keepers(in: .scenery).count)/\(selectionTargets.scenery)。"
            )
            return
        }

        let panel = NSOpenPanel()
        panel.title = String(localized: "选择精选照片的导出位置")
        panel.message = String(
            localized:
                "App 将复制人物 \(selectionTargets.people) 张、风景 \(selectionTargets.scenery) 张，并分别放入两个子目录；不会移动或删除原图。"
        )
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        pendingExportDirectory = directory
        showExportConfirmation = true
    }

    func exportKeepers() {
        guard let destinationParent = pendingExportDirectory, canExport else {
            pendingExportDirectory = nil
            showExportConfirmation = false
            statusMessage = String(
                localized:
                    "尚不能导出：人物和风景都必须达到各自保留目标。"
            )
            return
        }
        let exportPhotos = keepers
        pendingExportDirectory = nil
        showExportConfirmation = false
        statusMessage = String(localized: "正在安全复制 \(exportPhotos.count) 张精选照片…")
        let targets = selectionTargets

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let exportURL = try ExportService.copyCategorized(
                    photos: exportPhotos,
                    to: destinationParent,
                    targets: targets
                )
                DispatchQueue.main.async {
                    self?.statusMessage = String(localized: "导出完成：\(exportURL.lastPathComponent)。原图未被修改。")
                    self?.recordDemoExportCompleted()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusMessage = String(localized: "导出失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func storeUndoState(previousDecisionsByPhotoID: [String: PhotoDecision]) {
        undoStack.append(DecisionUndoEntry(previousDecisionsByPhotoID: previousDecisionsByPhotoID))
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    private func saveActiveProjectSnapshot() {
        persistActiveProjectState()
        guard let activeProjectID, !photos.isEmpty else { return }
        projectSnapshots[activeProjectID] = PhotoProjectSnapshot(
            photos: photos,
            selectedPhotoID: selectedPhotoID,
            selectionTargets: selectionTargets,
            statusMessage: statusMessage,
            latestAIUsageMessage: latestAIUsageMessage,
            aiFinalSelectionPhotoIDsByCategory:
                aiFinalSelectionPhotoIDsByCategory,
            aiFinalSelectionRunProgress: aiFinalSelectionRunProgress,
            aiFinalSelectionRunProgressByCategory:
                aiFinalSelectionRunProgressByCategory
        )
    }

    private func restoreProjectSnapshot(_ snapshot: PhotoProjectSnapshot, folder: URL) {
        cancelProjectWork()
        selectedFolder = folder
        photos = snapshot.photos
        selectedPhotoID = snapshot.selectedPhotoID ?? snapshot.photos.first?.id
        selectionTargets = snapshot.selectionTargets
        statusMessage = snapshot.statusMessage
        latestAIUsageMessage = snapshot.latestAIUsageMessage
        aiFinalSelectionPhotoIDsByCategory =
            snapshot.aiFinalSelectionPhotoIDsByCategory
        aiFinalSelectionRunProgress = snapshot.aiFinalSelectionRunProgress
        aiFinalSelectionRunProgressByCategory =
            snapshot.aiFinalSelectionRunProgressByCategory
        isScanning = false
        isAnalyzing = false
        isGroupingCandidates = false
        analysisCompleted = photos.count
        analysisTotal = photos.count
        undoStack = []
    }

    private func updateProject(_ projectID: UUID, change: (inout PhotoProject) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        change(&projects[index])
        if var persisted = persistedProjects[projectID] {
            persisted.displayName = projects[index].displayName
            persisted.lastKnownPhotoCount = projects[index].photoCount
            persistedProjects[projectID] = persisted
        }
        persistProjectCatalog()
    }

    private func cancelProjectWork() {
        analysisSessionID = UUID()
        aiFinalSelectionRunTask?.cancel()
        demoAIScoringTask?.cancel()
        aiFinalSelectionRunTask = nil
        demoAIScoringTask = nil
        aiFinalSelectionRunTaskID = nil
        aiFinalSelectionRunContext = nil
        pendingAIFinalSelectionRunPlan = nil
        pendingAIFinalSelectionModelSnapshot = nil
        pendingAIFinalSelectionPreviewSizeSnapshot = nil
        pendingAIFinalSelectionCategorySnapshot = nil
        showAIFinalSelectionRunConfirmation = false
        isRunningDemoAIScoring = false
    }

    private func resetWorkspace() {
        selectedFolder = nil
        photos = []
        selectedPhotoID = nil
        curationScope = .all
        selectionTargets = .default
        aiFinalSelectionPhotoIDsByCategory = [:]
        aiFinalSelectionRunProgress = AIFinalSelectionRunProgress()
        aiFinalSelectionRunProgressByCategory = [:]
        firstCurationGuideStep = nil
        demoModeSession = nil
        demoGuidedKeeperPhotoID = nil
        isRunningDemoAIScoring = false
        demoAIScoringCompletedBatchCount = 0
        demoAIScoringCompletedPhotoCount = 0
        latestAIUsageMessage = nil
        undoStack = []
        isScanning = false
        isAnalyzing = false
        isGroupingCandidates = false
        analysisCompleted = 0
        analysisTotal = 0
    }

    func prepareForTermination() {
        persistActiveProjectState()
        for projectID in Array(startedSecurityScopes.keys) {
            stopSecurityScope(for: projectID)
        }
    }

    private func restorePersistedProjects() {
        isRestoringPersistedState = true
        var refreshedBookmark = false
        defer {
            isRestoringPersistedState = false
            if refreshedBookmark {
                persistProjectCatalog()
            }
        }

        let catalog: PersistedPhotoProjectCatalog
        do {
            guard let loaded = try projectStore.load() else { return }
            catalog = loaded
        } catch {
            statusMessage = String(localized: "无法恢复项目状态；原照片未受影响。")
            return
        }

        var restoredProjects: [PhotoProject] = []
        for var persisted in catalog.projects {
            persistedProjects[persisted.id] = persisted
            do {
                let resolved = try bookmarkAccess.resolve(persisted.bookmarkData)
                guard canReadDirectory(resolved.url) || beginSecurityScope(for: persisted.id, url: resolved.url) else {
                    throw ProjectPersistenceError.inaccessibleBookmark
                }
                if startedSecurityScopes[persisted.id] == nil {
                    beginSecurityScope(for: persisted.id, url: resolved.url)
                }
                if resolved.isStale {
                    persisted.bookmarkData = try bookmarkAccess.makeReadOnlyBookmark(for: resolved.url)
                    persistedProjects[persisted.id] = persisted
                    refreshedBookmark = true
                }
                restoredProjects.append(
                    PhotoProject(
                        id: persisted.id,
                        folderURL: resolved.url,
                        displayName: persisted.displayName,
                        createdAt: persisted.createdAt,
                        photoCount: persisted.lastKnownPhotoCount,
                        accessState: .available
                    )
                )
            } catch {
                restoredProjects.append(
                    PhotoProject(
                        id: persisted.id,
                        folderURL: nil,
                        displayName: persisted.displayName,
                        createdAt: persisted.createdAt,
                        photoCount: persisted.lastKnownPhotoCount,
                        accessState: .needsAuthorization
                    )
                )
            }
        }
        projects = restoredProjects

        guard let requestedActiveID = catalog.activeProjectID,
              let project = projects.first(where: {
                  $0.id == requestedActiveID && $0.accessState == .available
              }),
              let folderURL = project.folderURL else {
            if !projects.isEmpty {
                statusMessage = String(localized: "已恢复项目列表；需要时点按项目重新授权或继续筛选。")
            }
            return
        }

        activeProjectID = requestedActiveID
        lastPersistentActiveProjectID = requestedActiveID
        if let persisted = persistedProjects[requestedActiveID] {
            selectionTargets = persisted.selectionTargets
                ?? PhotoSelectionTargets(
                    legacyTotal: persisted.targetSelectionCount
                )
        } else {
            selectionTargets = .default
        }
        startScan(folder: folderURL, projectID: requestedActiveID)
    }

    private func reauthorizeProject(_ projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "重新授权照片文件夹")
        panel.message = String(localized: "请重新选择“\(projects[index].displayName)”对应的照片文件夹。")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard let bookmarkData = try? bookmarkAccess.makeReadOnlyBookmark(for: folder) else {
            statusMessage = String(localized: "无法保存新的文件夹授权，请重试。")
            return
        }

        saveActiveProjectSnapshot()
        stopSecurityScope(for: projectID)
        beginSecurityScope(for: projectID, url: folder)
        projects[index].reconnect(to: folder)
        var persisted = persistedProjects[projectID] ?? PersistedPhotoProject(
            id: projectID,
            bookmarkData: bookmarkData,
            displayName: projects[index].displayName,
            createdAt: projects[index].createdAt
        )
        persisted.bookmarkData = bookmarkData
        persisted.displayName = projects[index].displayName
        persisted.lastOpenedAt = Date()
        persistedProjects[projectID] = persisted
        activeProjectID = projectID
        isDemoModeActive = false
        lastPersistentActiveProjectID = projectID
        refreshAIConfiguration()
        selectionTargets = persisted.selectionTargets
            ?? PhotoSelectionTargets(
                legacyTotal: persisted.targetSelectionCount
            )
        persistProjectCatalog()
        startScan(folder: folder, projectID: projectID)
    }

    private func persistActiveProjectState() {
        guard !isRestoringPersistedState,
              let activeProjectID,
              let project = projects.first(where: { $0.id == activeProjectID }),
              let folderURL = project.folderURL,
              var persisted = persistedProjects[activeProjectID] else {
            return
        }

        persisted.displayName = project.displayName
        persisted.lastOpenedAt = Date()
        persisted.lastKnownPhotoCount = photos.isEmpty ? project.photoCount : photos.count
        persisted.targetSelectionCount = targetSelectionCount
        persisted.selectionTargets = selectionTargets
        if !photos.isEmpty {
            persisted.decisionsByRelativePath = Dictionary(uniqueKeysWithValues: photos.compactMap { photo in
                guard photo.decision != .undecided,
                      let relativePath = ProjectRelativePath.make(for: photo.url, relativeTo: folderURL) else {
                    return nil
                }
                return (relativePath, photo.decision)
            })
            persisted.selectedRelativePath = selectedPhoto.flatMap {
                ProjectRelativePath.make(for: $0.url, relativeTo: folderURL)
            }
            persisted.categoryOverridesByRelativePath = Dictionary(
                uniqueKeysWithValues: photos.compactMap { photo in
                    guard photo.isCurationCategoryUserAssigned,
                          let category = photo.curationCategory,
                          let relativePath = ProjectRelativePath.make(
                              for: photo.url,
                              relativeTo: folderURL
                          ) else {
                        return nil
                    }
                    return (relativePath, category)
                }
            )
        }
        persistedProjects[activeProjectID] = persisted
        persistProjectCatalog()
    }

    private func persistProjectCatalog() {
        guard !isRestoringPersistedState else { return }
        let persistedActiveProjectID = activeProjectID.flatMap {
            persistedProjects[$0] == nil ? nil : $0
        } ?? lastPersistentActiveProjectID.flatMap {
            persistedProjects[$0] == nil ? nil : $0
        }
        let catalog = PersistedPhotoProjectCatalog(
            activeProjectID: persistedActiveProjectID,
            projects: projects.compactMap { persistedProjects[$0.id] }
        )
        do {
            try projectStore.save(catalog)
        } catch {
            statusMessage = String(localized: "项目状态保存失败；原照片未受影响。")
        }
    }

    @discardableResult
    private func beginSecurityScope(for projectID: UUID, url: URL) -> Bool {
        if startedSecurityScopes[projectID] == url { return true }
        stopSecurityScope(for: projectID)
        guard bookmarkAccess.startAccessing(url) else { return false }
        startedSecurityScopes[projectID] = url
        return true
    }

    private func stopSecurityScope(for projectID: UUID) {
        guard let url = startedSecurityScopes.removeValue(forKey: projectID) else { return }
        bookmarkAccess.stopAccessing(url)
    }

    private func canReadDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) != nil
    }

    private func makeAestheticReviewPreviews(
        candidateGroup: AestheticReviewCandidateGroup,
        request: AestheticReviewRequest,
        previewSize: AIReviewPreviewSize
    ) async throws -> [AestheticReviewPreview] {
        let photoByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        guard candidateGroup.localPhotoIDs.count == request.photos.count else {
            throw AestheticReviewClientError.incompletePreviewSet
        }

        let inputs = try zip(request.photos, candidateGroup.localPhotoIDs).map { input, localPhotoID in
            guard let photo = photoByID[localPhotoID] else {
                throw AestheticReviewClientError.incompletePreviewSet
            }
            return (opaquePhotoID: input.photoID, url: photo.url)
        }
        let maximumPixelSize = previewSize.maximumPixelSize
        return try await Task.detached(priority: .userInitiated) {
            try inputs.map { input in
                AestheticReviewPreview(
                    opaquePhotoID: input.opaquePhotoID,
                    jpegData: try AIReviewPreviewEncoder.jpegData(
                        for: input.url,
                        maximumPixelSize: maximumPixelSize
                    )
                )
            }
        }.value
    }

    private func startAnalysis(of items: [PhotoItem], sessionID: UUID) {
        let urls = items.map(\.url)
        let batchSize = analysisBatchSize
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard !urls.isEmpty else { return }
            for start in stride(from: 0, to: urls.count, by: batchSize) {
                let end = min(start + batchSize, urls.count)
                let results = urls[start..<end].map(Self.analyze)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.analysisSessionID == sessionID else { return }
                    self.photos = PhotoAnalysisMerger.applying(results, to: self.photos)
                    self.analysisCompleted = min(self.analysisCompleted + results.count, self.analysisTotal)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.analysisSessionID == sessionID else { return }
                self.isGroupingCandidates = true
                self.finishCandidateGrouping(for: self.photos, sessionID: sessionID)
            }
        }
    }

    private func finishCandidateGrouping(for snapshot: [PhotoItem], sessionID: UUID) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let visualInput = snapshot.map { photo in
                var updated = photo
                updated.burstGroup = nil
                return updated
            }
            let groupedPhotos = SimilarityGrouper.assigningGroups(to: visualInput)
            let recommendedPhotos = LocalCandidateRanker.assigningRecommendations(to: groupedPhotos)
            let similarityGroups = Dictionary(uniqueKeysWithValues: recommendedPhotos.map { ($0.id, $0.similarityGroup) })
            let recommendations = Dictionary(uniqueKeysWithValues: recommendedPhotos.map { ($0.id, $0.localRecommendations) })

            DispatchQueue.main.async {
                guard let self, self.analysisSessionID == sessionID else { return }
                for index in self.photos.indices {
                    let photoID = self.photos[index].id
                    self.photos[index].burstGroup = nil
                    self.photos[index].similarityGroup = similarityGroups[photoID] ?? nil
                    self.photos[index].localRecommendations = recommendations[photoID] ?? []
                }
                self.isGroupingCandidates = false
                self.isAnalyzing = false
                if let activeProjectID = self.activeProjectID {
                    self.updateProject(activeProjectID) { project in
                        project.photoCount = self.photos.count
                        project.isAnalysisComplete = true
                    }
                }
                self.statusMessage = String(
                    localized:
                        "分析完成：发现 \(self.similarityGroupCount) 组相似照片和 \(self.technicalRiskPhotoCount) 张技术风险提示。"
                )
                self.persistActiveProjectState()
            }
        }
    }

    nonisolated private static func analyze(_ url: URL) -> PhotoAnalysisResult {
        let raster = LuminanceThumbnailReader.raster(for: url)
        return PhotoAnalysisResult(
            photoID: url.standardizedFileURL.path,
            captureDate: PhotoMetadataReader.captureDate(for: url),
            perceptualHash: raster.flatMap { PerceptualHasher.hash(from: $0) },
            technicalQuality: raster.map { TechnicalQualityAnalyzer.analyze($0) },
            curationCategory: PhotoCategoryClassifier.classify(url)
        )
    }

    nonisolated private static func imageURLs(in folder: URL, supportedExtensions: Set<String>) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var imageURLs: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isHidden != true,
                  supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }
            imageURLs.append(url)
        }
        return imageURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

}
