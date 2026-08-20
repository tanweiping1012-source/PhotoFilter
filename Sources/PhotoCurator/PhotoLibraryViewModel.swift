import AppKit
import Foundation

/// 主链路上“这一步真的完成了”的可见回执。
///
/// 状态栏里的一行灰字会和扫描进度、分析进度挤在一起，用户读不到它。
/// 完成态必须自己占一块地方，说明发生了什么，并指出下一步在哪。
struct CurationCompletionNotice: Equatable, Identifiable {
    enum Kind: Equatable {
        case aiScoring(PhotoCurationCategory)
        case export(URL)
    }

    let id: UUID
    let kind: Kind
    let title: String
    let message: String
}

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    /// 当前需要展示的完成回执；用户确认或进入下一轮操作后清空。
    @Published private(set) var completionNotice: CurationCompletionNotice?

    @Published private(set) var photos: [PhotoItem] = [] {
        didSet {
            // 候选池与"待评分"集合都是从 photos 派生的。任何就地改写——分析结果合并、
            // 评分记录写入、人工决定、分类纠正——都必须让它们失效。
            //
            // 这里不逐个调用点去补，是因为已经漏过三次：相似家族计算结束时漏过一次
            // （"待评分"长期显示 0），演示评分逐批写入时漏过一次（评分完了还显示"待评分"），
            // 提交新一轮评分清除旧记录时也没有。把不变量放在源头，新增写入路径不必再记得接线。
            invalidateCandidatePlans()
        }
    }
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
    /// 当前网格里可见的照片顺序，由界面推送；见 `updateVisiblePhotos(_:)`。
    @Published private(set) var visiblePhotoIDs: [String] = []
    private var visiblePhotoIDSet: Set<String> = []
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
            invalidateCandidatePlans()
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
    private struct CachedCandidatePlan {
        let plan: LocalAestheticCandidatePlan?
    }

    private struct CachedCandidatePhotoIDs {
        let scope: PhotoCurationScope
        let photoIDs: Set<String>
    }

    private var cachedCandidatePlans: [PhotoCurationCategory: CachedCandidatePlan] = [:]
    private var cachedCandidatePhotoIDs: CachedCandidatePhotoIDs?
    /// 照片下标与相对路径的索引。按键路径上不允许再对整个数组做线性查找或重算相对路径。
    private var photoIndexByID: [String: Int] = [:]
    private var relativePathByPhotoID: [String: String] = [:]
    private var persistDebounceTask: Task<Void, Never>?
    private var hasPendingProjectStateChanges = false
    private let supportedExtensions = PhotoAnalysisPipeline.supportedExtensions
    private var analysisSessionID: UUID?
    private var scanTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var groupingTask: Task<Void, Never>?
    private let analysisBatchSize = 32
    private var lastAestheticReviewAt: Date?
    /// 被供应商限流后临时抬高的请求间隔；一轮任务结束或成功若干次后回落到基础间隔。
    private var adaptiveReviewInterval = AIReviewConfiguration.minimumReviewInterval
    private var aiFinalSelectionRunContext: AIFinalSelectionRunContext?
    private var aiFinalSelectionRunTask: Task<Void, Never>?
    private var aiFinalSelectionRunTaskID: UUID?
    private var pendingAIFinalSelectionModelSnapshot: AIModelDescriptor?
    private var pendingAIFinalSelectionPreviewSizeSnapshot: AIReviewPreviewSize?
    private var pendingAIFinalSelectionCategorySnapshot:
        PhotoCurationCategory?
    private var demoModeSession: DemoModeSession?
    private var demoAIScoringTask: Task<Void, Never>?
    private var demoAnalysisTask: Task<Void, Never>?
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
        let curationScope: PhotoCurationScope
        let selectionTargets: PhotoSelectionTargets
        let statusMessage: String
        let latestAIUsageMessage: String?
        /// 回执必须跟着项目走：它描述的是"这个项目刚发生了什么"。
        /// 作为全局单值时，真实项目评分完成后切到示例，示例第 1 步头上会顶着
        /// 真实项目的"风景 AI评分完成"，点"知道了"还会把真实项目的回执一起消掉。
        let completionNotice: CurationCompletionNotice?
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
            // 只在有项目时探测 Keychain：示例练习必须完全不接触 Keychain，
            // 而没有项目时 `isAIModelKeyConfigured` 不影响任何可见状态
            // （AI 设置页自己读取 Key 状态）。
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

    /// 项目入口被禁用的原因；可用时为 nil。
    ///
    /// 按钮置灰却不说明原因，等于把解释藏在一个永远点不到的地方——
    /// 原来那句提示只在点击时才写进状态栏，而按钮禁用时根本点不动。
    var projectNavigationLockReason: String? {
        if isAIFinalSelectionRunActive || isRunningDemoAIScoring {
            return String(localized: "AI评分进行中；停止本轮任务后即可新建或切换项目。")
        }
        if isScanning || isAnalyzing {
            return String(localized: "本地分析完成后即可新建或切换项目。")
        }
        return nil
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
        guard !isLockedByActiveAIFinalSelectionRun(category), !isDemoModeActive else {
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

    /// 导出多少张是用户的自由：只要有保留照片就能复制导出。
    /// 保留目标只用于显示进度和提示，不再作为导出闸门。
    var canExport: Bool {
        !isAnalyzing && !keepers.isEmpty
    }

    /// 保留数与目标不一致时，在确认弹窗里提示，但不阻止导出。
    var exportTargetDeviationNotice: String? {
        let deviations = PhotoCurationCategory.allCases.compactMap { category -> String? in
            let kept = keepers(in: category).count
            let target = selectionTargets[category]
            guard kept != target else { return nil }
            return String(localized: "\(category.title) \(kept)/\(target)")
        }
        guard !deviations.isEmpty else { return nil }
        return String(
            localized: "当前保留数与目标不同（\(deviations.formatted(.list(type: .and)))），仍可继续导出。"
        )
    }

    var canUndo: Bool {
        guard let previous = undoStack.last else { return false }
        return !previous.previousDecisionsByPhotoID.keys.contains(
            where: isPhotoLockedByActiveAIFinalSelectionRun
        )
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
        // 正在跑的任务优先：用户切到另一类浏览时，进度、暂停和停止必须继续跟着任务，
        // 否则一切换类型运行中的任务就"消失"了。
        if isAIFinalSelectionRunActive {
            return aiFinalSelectionRunProgress
        }
        if let category = curationScope.category {
            return aiFinalSelectionRunProgress(for: category)
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

    /// 待评分池的计算成本是 O(N log N)，而界面每次刷新都会读它。
    /// 因此结果缓存在这里，只有照片、决定、分类或目标变化时才作废重算。
    func localAestheticCandidatePlan(
        for category: PhotoCurationCategory
    ) -> LocalAestheticCandidatePlan? {
        guard !photos.isEmpty, !isAnalyzing else { return nil }
        if let cached = cachedCandidatePlans[category] {
            return cached.plan
        }
        let plan = LocalAestheticCandidatePlanner.makePlan(
            for: photos.filter {
                $0.curationCategory == category
            },
            targetSelectionCount: selectionTargets[category]
        )
        cachedCandidatePlans[category] = CachedCandidatePlan(plan: plan)
        return plan
    }

    /// 整体替换照片集合时同步重建索引，并作废依赖照片集合的缓存。
    /// 逐张修改（例如 `photos[index].decision`）不改变顺序与 id，不需要重建索引。
    private func replacePhotos(_ newPhotos: [PhotoItem]) {
        let orderChanged = newPhotos.count != photos.count
            || zip(newPhotos, photos).contains { $0.id != $1.id }
        photos = newPhotos
        if orderChanged {
            photoIndexByID = Dictionary(
                uniqueKeysWithValues: newPhotos.enumerated().map { ($0.element.id, $0.offset) }
            )
            rebuildRelativePathIndex()
        }
        invalidateCandidatePlans()
    }

    private func rebuildRelativePathIndex() {
        guard let folderURL = activeProject?.folderURL else {
            relativePathByPhotoID = [:]
            return
        }
        rebuildRelativePathIndex(folderURL: folderURL)
    }

    private func rebuildRelativePathIndex(folderURL: URL) {
        relativePathByPhotoID = Dictionary(
            uniqueKeysWithValues: photos.compactMap { photo in
                ProjectRelativePath.make(for: photo.url, relativeTo: folderURL)
                    .map { (photo.id, $0) }
            }
        )
    }

    private func photoIndex(for photoID: String) -> Int? {
        if let index = photoIndexByID[photoID],
           index < photos.count,
           photos[index].id == photoID {
            return index
        }
        return photos.firstIndex { $0.id == photoID }
    }

    /// 照片集合、人工决定、分类纠正或目标数量变化后必须调用，否则界面会读到过期的待评分池。
    func invalidateCandidatePlans() {
        cachedCandidatePlans = [:]
        cachedCandidatePhotoIDs = nil
    }

    var localAestheticCandidatePhotoIDs: Set<String> {
        if let cachedCandidatePhotoIDs,
           cachedCandidatePhotoIDs.scope == curationScope {
            return cachedCandidatePhotoIDs.photoIDs
        }
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
        let photoIDs = candidateIDs.subtracting(scoredPhotoIDs)
        cachedCandidatePhotoIDs = CachedCandidatePhotoIDs(
            scope: curationScope,
            photoIDs: photoIDs
        )
        return photoIDs
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

    /// AI评分入口的可用性与不可用原因。
    ///
    /// 入口本身永远存在——按钮消失会让用户以为功能不存在或界面出错。
    /// 不能开始时按钮置灰，并在下方给出可执行的原因。
    struct AIFinalSelectionAvailability {
        let canStart: Bool
        let candidatePhotoCount: Int
        /// 不能开始时的说明；能开始时为 nil。
        let blockedReason: String?
    }

    func aiFinalSelectionAvailability(
        for category: PhotoCurationCategory
    ) -> AIFinalSelectionAvailability {
        let candidateCount = localAestheticCandidatePlan(for: category)?.candidateCount ?? 0

        func blocked(_ reason: String) -> AIFinalSelectionAvailability {
            AIFinalSelectionAvailability(
                canStart: false,
                candidatePhotoCount: candidateCount,
                blockedReason: reason
            )
        }

        /// 结论已经写在按钮上时不再补充说明：多一段解释只会增加要读的东西，
        /// 却不会多给一个能做的动作。
        func blockedWithoutExplanation() -> AIFinalSelectionAvailability {
            AIFinalSelectionAvailability(
                canStart: false,
                candidatePhotoCount: candidateCount,
                blockedReason: nil
            )
        }

        if isDemoModeActive {
            // 教学必须驱动真实控件。以前这里一刀切拦住侧栏入口，教学只好另做一个
            // 只在教学期间存在的按钮——用户学完一套用完就消失的界面，回到真实流程
            // 时根本不知道 AI评分 在哪，眼前最显眼的前进按钮变成了"导出"。
            guard demoScorableCategory == category, !isRunningDemoAIScoring else {
                return blocked(String(localized: "示例练习不会联网评分。"))
            }
            return AIFinalSelectionAvailability(
                canStart: true,
                candidatePhotoCount: demoCandidatePhotoCount(for: category),
                blockedReason: nil
            )
        }
        if isAnalyzing {
            return blocked(String(localized: "本地分析完成后即可开始。"))
        }
        if isAIFinalSelectionRunActive {
            return blocked(String(localized: "已有 AI评分任务正在运行。"))
        }
        if !isAIModelKeyConfigured {
            return blocked(String(localized: "请先在 AI评分设置中配置并验证 API Key。"))
        }
        let conflicts = keeperDiversityConflicts(in: category)
        if !conflicts.isEmpty {
            return blocked(
                String(localized: "\(category.title)中有 \(conflicts.count) 组相似照片被同时保留，请每组只留一张。")
            )
        }
        guard let candidatePlan = localAestheticCandidatePlan(for: category) else {
            return blocked(String(localized: "\(category.title)没有可评分的照片。"))
        }
        let remaining = candidatePlan.remainingSelectionCount
        guard remaining > 0 else {
            return blocked(
                String(localized: "\(category.title)保留数已达目标 \(selectionTargets[category]) 张，无需再评分。")
            )
        }
        guard !candidatePlan.localPhotoIDs.isEmpty else {
            if candidatePlan.eligiblePhotoCount == 0 {
                return blocked(
                    String(localized: "\(category.title)的照片都已保留或淘汰，没有需要评分的照片。")
                )
            }
            // 剩下的都是已保留照片的同场景重复项。按钮上的"（0 张）"已经把结论说完了，
            // 再补一句就是要求用户先学会"相似分组"和"重复项不进候选池"两条内部规则，
            // 而他在这一刻什么也做不了——解释反而让功能更难懂。这里静默阻止。
            return blockedWithoutExplanation()
        }

        do {
            _ = try AIFinalSelectionRunPlanner.makePlan(
                candidateLocalPhotoIDs: candidatePlan.localPhotoIDs,
                targetWinnerCount: remaining,
                category: category
            )
        } catch {
            return blocked(error.localizedDescription)
        }

        return AIFinalSelectionAvailability(
            canStart: true,
            candidatePhotoCount: candidatePlan.candidateCount,
            blockedReason: nil
        )
    }

    var isAIFinalSelectionRunActive: Bool {
        aiFinalSelectionRunContext != nil
    }

    /// 正在评分的照片类型；没有任务时为 nil。
    var activeAIFinalSelectionCategory: PhotoCurationCategory? {
        aiFinalSelectionRunContext?.category
    }

    /// 一轮 AI评分只锁定它自己那一类。
    ///
    /// 人物和风景本来就有各自独立的目标、候选池和结果，用一个全局开关把整个界面锁住，
    /// 会让用户以为 App 卡住了——实际上另一类的浏览、决定和目标调整都完全安全。
    func isLockedByActiveAIFinalSelectionRun(
        _ category: PhotoCurationCategory?
    ) -> Bool {
        AIFinalSelectionRunLock.isLocked(
            category: category,
            runningCategory: activeAIFinalSelectionCategory
        )
    }

    /// 单张照片是否被当前这一轮评分锁定：属于正在评分的类型，或本身就在候选池里。
    func isPhotoLockedByActiveAIFinalSelectionRun(_ photoID: String) -> Bool {
        guard let context = aiFinalSelectionRunContext else { return false }
        if context.plan.coveredPhotoIDs.contains(photoID) { return true }
        guard let index = photoIndex(for: photoID) else { return true }
        return isLockedByActiveAIFinalSelectionRun(photos[index].curationCategory)
    }

    /// 当前选中照片能否被标记；底部决定按钮和菜单快捷键共用它。
    ///
    /// 除了"没有被正在跑的评分锁住"，还必须"在当前网格里看得见"——
    /// 否则用户会在看不见照片的情况下改掉它的保留/淘汰。
    var canDecideSelectedPhoto: Bool {
        guard let selectedPhotoID, isSelectionVisible else { return false }
        return !isPhotoLockedByActiveAIFinalSelectionRun(selectedPhotoID)
    }

    /// 选中项是否属于当前可见集合。
    var isSelectionVisible: Bool {
        guard let selectedPhotoID else { return false }
        return visiblePhotoIDSet.contains(selectedPhotoID)
    }

    /// 界面在筛选、照片类型或照片集合变化后推送当前网格里可见的照片顺序。
    ///
    /// 可见集合是界面概念，但检查条、决定命令、菜单快捷键和大图预览都要以它为准，
    /// 所以它必须有一个各处共享的唯一来源，而不是每个视图各算一遍。
    func updateVisiblePhotos(_ photoIDs: [String]) {
        guard photoIDs != visiblePhotoIDs else { return }
        visiblePhotoIDs = photoIDs
        visiblePhotoIDSet = Set(photoIDs)
        reconcileSelection()
    }

    /// 把选中项拉回可见集合：不在集合里就改选第一张，集合为空就清空。
    ///
    /// 空集合时必须真的清空——早期实现在这里直接 return，
    /// 于是切到一个空筛选后，底部仍然显示并可操作上一个类型里的那张照片。
    func reconcileSelection() {
        guard let first = visiblePhotoIDs.first else {
            if selectedPhotoID != nil { selectedPhotoID = nil }
            return
        }
        if let selectedPhotoID, visiblePhotoIDSet.contains(selectedPhotoID) {
            return
        }
        selectedPhotoID = first
    }

    func dismissCompletionNotice() {
        completionNotice = nil
    }

    var pendingAIFinalSelectionModel: AIModelDescriptor {
        pendingAIFinalSelectionModelSnapshot ?? selectedAIModel
    }

    /// 确认弹窗要显示这一轮锁定的类型；未锁定时回退到当前作用域。
    var pendingAIFinalSelectionCategory: PhotoCurationCategory {
        pendingAIFinalSelectionCategorySnapshot ?? curationScope.category ?? .people
    }

    var pendingAIFinalSelectionPreviewSize: AIReviewPreviewSize {
        pendingAIFinalSelectionPreviewSizeSnapshot ?? selectedAIPreviewSize
    }

    var remainingAestheticReviewCooldown: Int {
        guard let lastAestheticReviewAt else { return 0 }
        let remaining = adaptiveReviewInterval - Date().timeIntervalSince(lastAestheticReviewAt)
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
        firstCurationGuideStep = .analyzePhotos
        demoModeSession = session
        isRunningDemoAIScoring = false
        demoAIScoringCompletedBatchCount = 0
        demoAIScoringCompletedPhotoCount = 0
        isAIModelKeyConfigured = false
        selectedFolder = session.resourceDirectory
        replacePhotos(session.startingPhotos)
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
        completionNotice = nil
        undoStack = []
        isScanning = false
        isGroupingCandidates = false
        isAnalyzing = true
        analysisCompleted = 0
        analysisTotal = session.startingPhotos.count
        startDemoAnalysisPacing()
        statusMessage = String(
            localized:
                "正在本地分析示例照片；完成后就能开始筛选。"
        )
    }

    private func advanceDemoForCurationScope() {
        guard isDemoModeActive else { return }
        if firstCurationGuideStep == .choosePeople,
           curationScope == .people {
            selectedPhotoID = photos.first {
                $0.curationCategory == .people
            }?.id
            firstCurationGuideStep = .runPeopleAIScoring
            statusMessage = String(
                localized:
                    "人物照片已单独显示。现在在左侧点击“开始人物 AI评分”。"
            )
        } else if firstCurationGuideStep == .switchSceneryAndScore,
                  curationScope == .scenery {
            selectedPhotoID = photos.first {
                $0.curationCategory == .scenery
            }?.id
            // 不在这里推进步骤：切换类型本身不产出任何结果。第 5 步要等风景
            // 那一轮评分跑完才算完成——真实流程就是每个类型各评一次。
            statusMessage = String(
                localized:
                    "风景照片已单独显示。现在在左侧点击“开始风景 AI评分”。"
            )
        }
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
        firstCurationGuideStep = .acceptPeopleResults
        statusMessage = String(localized: "评分只提供解释和排序。点底部的“采纳”，被采纳的照片就成为保留。")
    }

    /// 示例的本地分析进度按教学节奏走完，不是算力开销。
    ///
    /// 演示结果必须是确定的——相似分组和内置评分结果的 scope 是按烘焙分组编号的，
    /// 真跑一遍分析管线重算就可能对不上，所以这里不重算。
    /// 但真实用户第一次导入文件夹后，最先看到、也停留最久的就是这条进度条；
    /// 教学整段跳过它，用户第一次面对真实图库那几十秒时会不知道发生了什么。
    /// 8 张 × 850ms ≈ 6.8 秒是刻意选的教学时长。
    private func startDemoAnalysisPacing() {
        demoAnalysisTask?.cancel()
        let total = max(analysisTotal, 1)
        demoAnalysisTask = Task { @MainActor [weak self] in
            for completed in 1...total {
                try? await Task.sleep(for: .milliseconds(850))
                if Task.isCancelled { return }
                guard let self, self.isDemoModeActive,
                      self.firstCurationGuideStep == .analyzePhotos else { return }
                self.analysisCompleted = completed
            }
            guard let self, self.isDemoModeActive,
                  self.firstCurationGuideStep == .analyzePhotos else { return }
            self.finishDemoAnalysis()
        }
    }

    /// 测试与自动审核用：跳过教学节奏，直接落到分析完成态。
    func completeDemoAnalysisImmediately() {
        guard isDemoModeActive, firstCurationGuideStep == .analyzePhotos else { return }
        demoAnalysisTask?.cancel()
        demoAnalysisTask = nil
        analysisCompleted = analysisTotal
        finishDemoAnalysis()
    }

    private func finishDemoAnalysis() {
        demoAnalysisTask = nil
        isAnalyzing = false
        analysisCompleted = analysisTotal
        firstCurationGuideStep = .choosePeople
        statusMessage = String(
            localized:
                "本地分析完成：4 张人物、4 张风景，各保留 2 张。现在在“照片类型”中选择“人物”。"
        )
    }

    /// 教学进行中不显示完成回执。
    ///
    /// 任务条本身就在讲"下一步做什么"，回执再讲一遍另一个下一步——
    /// 同一屏上出现两条互相竞争的指令。而且回执是浮层，会盖住网格顶排照片。
    /// 回执仍然照常产生：它负责把网格带到该类型的"已AI评分"，只是不渲染。
    var visibleCompletionNotice: CurationCompletionNotice? {
        firstCurationGuideStep == nil ? completionNotice : nil
    }

    /// 教学此刻是否该指向"照片类型"分段控件。
    ///
    /// 第 6 步分两段：先指分段控件让用户切到风景，切过去之后指针转到侧栏的
    /// "开始风景 AI评分"。
    var isCurationScopeGuideTarget: Bool {
        if firstCurationGuideStep == .choosePeople { return true }
        return firstCurationGuideStep == .switchSceneryAndScore
            && curationScope.category != .scenery
    }

    /// 教学此刻是否停在"采纳"这一步（人物或风景）。
    ///
    /// 放在这里而不是视图里：ContentView 那个大 VStack 再多几个布尔运算，
    /// 类型检查就会超时。
    var isAcceptGuideStep: Bool {
        firstCurationGuideStep == .acceptPeopleResults
            || firstCurationGuideStep == .acceptSceneryResults
    }

    /// 教学此刻允许评分的类型。
    ///
    /// 真实流程是人物、风景各评一次；教学如果一次把两类都评完，用户学到的就是
    /// 一个不存在的流程。第 4 步评人物，第 5 步切到风景后再评风景。
    var demoScorableCategory: PhotoCurationCategory? {
        guard isDemoModeActive, demoModeSession != nil else { return nil }
        // 真实流程里 AI评分 不要求先手动保留任何照片，分析完就能直接评。
        // 旧教学把"先保留一张"写成了评分的前置条件，教出来的因果是反的。
        switch firstCurationGuideStep {
        case .runPeopleAIScoring:
            return .people
        case .switchSceneryAndScore:
            return curationScope.category == .scenery ? .scenery : nil
        default:
            return nil
        }
    }

    func demoCandidatePhotoCount(for category: PhotoCurationCategory) -> Int {
        photos.filter { $0.curationCategory == category }.count
    }

    /// 该类型在内置结果里对应的请求批次序号（从 1 开始）。
    private func demoBatchNumbers(
        for category: PhotoCurationCategory,
        in session: DemoModeSession
    ) -> [Int] {
        session.scoreScopes.enumerated().compactMap { index, scope in
            scope.category == category ? index + 1 : nil
        }
    }

    func startDemoAIScoring(for category: PhotoCurationCategory) {
        guard demoScorableCategory == category,
              !isRunningDemoAIScoring,
              let session = demoModeSession else {
            return
        }
        let batchNumbers = demoBatchNumbers(for: category, in: session)
        guard !batchNumbers.isEmpty else { return }
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
                for batchNumber in batchNumbers {
                    try await Task.sleep(for: .milliseconds(450))
                    try Task.checkCancellation()
                    self.applyDemoAIScoringBatch(
                        batchNumber,
                        category: category,
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
        for category in PhotoCurationCategory.allCases {
            for batchNumber in demoBatchNumbers(for: category, in: session) {
                applyDemoAIScoringBatch(
                    batchNumber,
                    category: category,
                    session: session
                )
            }
        }
    }

    private func applyDemoAIScoringBatch(
        _ batchNumber: Int,
        category: PhotoCurationCategory,
        session: DemoModeSession
    ) {
        guard (1...session.runProgress.totalBatchCount).contains(batchNumber) else {
            return
        }
        // 必须比整个 scope，不能只比 groupID：两个类型的计划各自从
        // ai-score-window-001 开始编号，groupID 跨类型是重复的。只比 groupID
        // 会让"评人物"这一批把风景的推荐也一并套上。
        let scope = session.scoreScopes[batchNumber - 1]
        let scoredPhotoByID = Dictionary(
            uniqueKeysWithValues: session.photos.map { ($0.id, $0) }
        )
        for index in photos.indices {
            guard let scoredPhoto = scoredPhotoByID[photos[index].id],
                  let recommendation = scoredPhoto.aestheticRecommendations.first(
                      where: { $0.scope == scope }
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

        // 按类型判断是否跑完，不依赖批次编号：真实流程就是一类评完算一轮。
        let categoryPhotoIDs = Set(
            photos.filter { $0.curationCategory == category }.map(\.id)
        )
        let scoredInCategory = photos.filter {
            categoryPhotoIDs.contains($0.id)
                && !$0.aestheticRecommendations.isEmpty
        }.count

        guard scoredInCategory == categoryPhotoIDs.count else {
            statusMessage = String(
                localized: "离线 AI评分：已评估 \(demoAIScoringCompletedPhotoCount) / \(session.runProgress.candidatePhotoCount) 张。"
            )
            return
        }

        isRunningDemoAIScoring = false
        demoAIScoringTask = nil
        aiFinalSelectionPhotoIDsByCategory[category] =
            demoFinalSelectionPhotoIDsByCategory(for: session)[category] ?? []
        let categoryProgress = AIFinalSelectionRunProgress(
            phase: .completed,
            completedPhotoCount: categoryPhotoIDs.count,
            candidatePhotoCount: categoryPhotoIDs.count,
            targetWinnerCount: session.selectionTargets[category]
        )
        aiFinalSelectionRunProgressByCategory[category] = categoryProgress
        aiFinalSelectionRunProgress = categoryProgress
        // 和真实流程完全一致：切到该类型，给出完成回执。回执会把网格带到
        // "已AI评分"，用户不需要自己回想该切哪个筛选。
        curationScope = PhotoCurationScope(category)
        completionNotice = CurationCompletionNotice(
            id: UUID(),
            kind: .aiScoring(category),
            title: String(localized: "\(category.title) AI评分完成"),
            message: String(
                localized:
                    "\(categoryPhotoIDs.count) 张已按分数排序，AI 推荐保留其中 \((aiFinalSelectionPhotoIDsByCategory[category] ?? []).count) 张。逐张看过后，用底部的“采纳”确认。"
            )
        )
        if category == .people {
            firstCurationGuideStep = .viewScore
            statusMessage = String(localized: "人物离线评分完成。打开任意一张照片，用底部的“查看评分”看它为什么得这个分。")
        } else {
            firstCurationGuideStep = .acceptSceneryResults
            statusMessage = String(localized: "风景离线评分完成。点底部的“采纳”，把风景结果也变成保留。")
        }
    }

    /// 离线结果不得覆盖人工已保留的照片。
    ///
    /// 教学不再强制"先保留一张"，但用户随时可以自己保留；真实评分靠
    /// `AIFinalSelectionRunContext.lockedKeeperPhotoIDs` 做同一件事，
    /// 示例必须保持一致，否则教学会演示出一个"AI 会覆盖你的决定"的假象。
    private func demoFinalSelectionPhotoIDsByCategory(
        for session: DemoModeSession
    ) -> [PhotoCurationCategory: Set<String>] {
        var result = session.finalSelectionPhotoIDsByCategory
        for category in PhotoCurationCategory.allCases {
            let manualKeeperIDs = photos
                .filter {
                    $0.curationCategory == category && $0.decision == .keep
                }
                .map(\.id)
            guard !manualKeeperIDs.isEmpty else { continue }
            let target = session.selectionTargets[category]
            let remainingIDs = session
                .rankedPhotoIDsByCategory[category, default: []]
                .filter { !manualKeeperIDs.contains($0) }
            result[category] = Set(
                manualKeeperIDs.prefix(target)
                    + remainingIDs.prefix(
                        max(0, target - manualKeeperIDs.count)
                    )
            )
        }
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

        presentPanel(panel, purpose: .source) { [weak self] folder in
            self?.openProject(folder: folder)
        }
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
            demoAnalysisTask?.cancel()
            demoAnalysisTask = nil
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
        completionNotice = nil
        // 刚扫描出来的照片还没有人物/风景分类。若沿用上一个项目的"人物"或"风景"，
        // 网格会在整个分析期间一张不显示，而界面上没有任何解释。
        curationScope = .all
        selectedFolder = folder.standardizedFileURL
        replacePhotos([])
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
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) { () -> [PhotoItem] in
                let urls = PhotoAnalysisPipeline.imageURLs(in: folder, supportedExtensions: extensions)
                return urls.map { url in
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
            }.value

            guard let self, !Task.isCancelled, self.analysisSessionID == sessionID else { return }
            do {
                self.replacePhotos(items)
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
                    self.statusMessage = String(localized: "没有找到 JPG、JPEG、PNG、WebP、HEIC 或 TIFF 图片。")
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
        guard !isPhotoLockedByActiveAIFinalSelectionRun(photoID),
              !isLockedByActiveAIFinalSelectionRun(category),
              let index = photoIndex(for: photoID) else {
            return
        }
        guard photos[index].curationCategory != category else {
            if !photos[index].isCurationCategoryUserAssigned {
                photos[index].isCurationCategoryUserAssigned = true
                persistActiveProjectState()
            }
            return
        }
        // 文案必须先于清除计算：清完之后就分不清"本来就没有"和"刚被我清掉"了。
        // 失效范围仍然覆盖源类别和目标类别（分数不能跨类别复用），只是不再无条件宣称结果被重置。
        let previousCategory = photos[index].curationCategory
        let affectedCategories = Set([previousCategory, category].compactMap { $0 })
        let hadScores = affectedCategories.contains { affected in
            !(aiFinalSelectionPhotoIDsByCategory[affected] ?? []).isEmpty
                || photos.contains {
                    $0.curationCategory == affected && !$0.aestheticRecommendations.isEmpty
                }
        }

        photos[index].curationCategory = category
        photos[index].isCurationCategoryUserAssigned = true
        photos[index].aestheticRecommendations = []
        aiFinalSelectionPhotoIDsByCategory = [:]
        aiFinalSelectionRunProgressByCategory = [:]
        persistActiveProjectState()
        statusMessage = hadScores
            ? String(
                localized:
                    "已将 \(photos[index].filename) 归为\(category.title)。相关的 AI评分结果已清除，需要重新评分。"
            )
            : String(localized: "已将 \(photos[index].filename) 归为\(category.title)。")
    }

    func setSelectedCurationCategory(
        _ category: PhotoCurationCategory
    ) {
        guard let selectedPhotoID else { return }
        setCurationCategory(category, for: selectedPhotoID)
    }

    func markSelected(as decision: PhotoDecision) {
        // 这里不再加可见性守卫：命令静默失败恰恰是要消灭的那种"点了没反应"。
        // 不可见的选中项由 `reconcileSelection()` 在源头消除，
        // 按钮和菜单则由 `canDecideSelectedPhoto` 提前置灰。
        guard let selectedPhotoID else { return }
        mark(photoID: selectedPhotoID, as: decision)
    }

    func mark(photoID: String, as decision: PhotoDecision) {
        if let category = activeAIFinalSelectionCategory,
           isPhotoLockedByActiveAIFinalSelectionRun(photoID) {
            statusMessage = String(
                localized: "这张照片属于正在评分的\(category.title)；请先停止本轮任务，或先处理另一类照片。"
            )
            return
        }
        if isDemoModeActive {
            if firstCurationGuideStep == .choosePeople {
                statusMessage = String(
                    localized: "请先在照片类型中选择“人物”。"
                )
                return
            }
        }
        guard let index = photoIndex(for: photoID), photos[index].decision != decision else {
            return
        }
        storeUndoState(previousDecisionsByPhotoID: [photoID: photos[index].decision])
        photos[index].decision = decision
        // 淘汰是对 AI 结果的明确否决：这张照片必须同时退出 AI 推荐名单，
        // 否则"采纳"仍会把它算进去，用户会以为自己那一下没生效。
        if decision == .reject,
           let category = photos[index].curationCategory,
           aiFinalSelectionPhotoIDsByCategory[category]?.contains(photoID) == true {
            aiFinalSelectionPhotoIDsByCategory[category]?.remove(photoID)
        }
        invalidateCandidatePlans()
        persistActiveProjectState()
        statusMessage = String(
            localized:
                "已将 \(photos[index].filename) 标记为\(decision.title)。\(selectionProgressMessage)"
        )
    }

    func undo() {
        guard let previous = undoStack.last else {
            statusMessage = String(localized: "没有可以撤销的操作。")
            return
        }
        if let category = activeAIFinalSelectionCategory,
           previous.previousDecisionsByPhotoID.keys.contains(
               where: isPhotoLockedByActiveAIFinalSelectionRun
           ) {
            statusMessage = String(
                localized: "上一步改动的是正在评分的\(category.title)照片；请先停止本轮任务再撤销。"
            )
            return
        }
        undoStack.removeLast()
        for (photoID, decision) in previous.previousDecisionsByPhotoID {
            guard let index = photoIndex(for: photoID) else { continue }
            photos[index].decision = decision
        }
        invalidateCandidatePlans()
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
        invalidateCandidatePlans()
        persistActiveProjectState()
        completionNotice = nil
        statusMessage = String(
            localized:
                "已采纳 \(pendingIDs.count) 张 AI评分结果。人物 \(keepers(in: .people).count)/\(selectionTargets.people)，风景 \(keepers(in: .scenery).count)/\(selectionTargets.scenery)。"
        )
        if isDemoModeActive {
            if firstCurationGuideStep == .acceptPeopleResults {
                firstCurationGuideStep = .switchSceneryAndScore
            } else if firstCurationGuideStep == .acceptSceneryResults {
                firstCurationGuideStep = .exportCopies
            }
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
        replacePhotos(updated)
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
    func prepareAIFinalSelectionRun(for requestedCategory: PhotoCurationCategory? = nil) {
        if isDemoModeActive {
            prepareDemoAIFinalSelectionRun(for: requestedCategory)
            return
        }
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
        guard let category = requestedCategory ?? curationScope.category else {
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
        guard let plan = aiFinalSelectionRunPlan(for: category) else {
            statusMessage = String(localized: "当前待评分照片无法安全收敛到目标张数；请调整保留目标。")
            return
        }
        pendingAIFinalSelectionRunPlan = plan
        pendingAIFinalSelectionModelSnapshot = selectedAIModel
        pendingAIFinalSelectionPreviewSizeSnapshot = selectedAIPreviewSize
        pendingAIFinalSelectionCategorySnapshot = category
        showAIFinalSelectionRunConfirmation = true
    }

    /// 示例教学也走一遍真实的发送确认框。
    ///
    /// 第一次真实评分是要花钱的，用户不该到那一刻才第一次见到这个弹窗。
    /// 内容用示例数值，文案写明不联网、不读取 Keychain、不消耗额度。
    private func prepareDemoAIFinalSelectionRun(
        for requestedCategory: PhotoCurationCategory?
    ) {
        guard let category = requestedCategory ?? curationScope.category,
              demoScorableCategory == category,
              !isRunningDemoAIScoring else {
            return
        }
        let candidatePhotoIDs = photos
            .filter { $0.curationCategory == category }
            .map(\.id)
        guard let plan = try? AIFinalSelectionRunPlanner.makePlan(
            candidateLocalPhotoIDs: candidatePhotoIDs,
            targetWinnerCount: selectionTargets[category],
            category: category
        ) else {
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
        if isDemoModeActive {
            startDemoAIScoring(for: category)
            return
        }
        guard !isAIFinalSelectionRunActive else { return }
        guard let apiKey = readAPIKeyForReview(model: model) else { return }

        completionNotice = nil
        // 用量文案说的是"本轮"。不在这里清掉的话，新任务 0/N 期间会继续显示
        // 上一类的数字，等第一批返回再被本轮小计覆盖——看上去像是用量倒退了。
        latestAIUsageMessage = nil
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
                "\(category.title) AI评分已开始：共 \(plan.candidatePhotoCount) 张；限流或网络中断会自动退避重试，仍失败则停在当前进度。"
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
            // 失败时保留 context：已经评过（已经付过钱）的照片留在 scoredCandidates 里，
            // 用户可以从失败的那一批继续，而不是从头再跑一遍。
            aiFinalSelectionRunProgress.phase = .failed
            aiFinalSelectionRunProgress.waitingSeconds = 0
            aiFinalSelectionRunProgress.failureMessage = error.localizedDescription
            aiFinalSelectionRunProgressByCategory[context.category] =
                aiFinalSelectionRunProgress
            if context.nextBatchIndex > 0 {
                statusMessage = String(localized: "AI评分已中断：\(error.localizedDescription) 已完成 \(aiFinalSelectionRunProgress.completedPhotoCount) 张的评分已保留，可以从中断处继续。")
            } else {
                statusMessage = String(localized: "AI评分失败并停止：\(error.localizedDescription)")
            }
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
                guard let delay = AIFinalSelectionRetryPolicy.retryDelay(
                    for: error,
                    completedRetryCount: completedRetryCount
                ) else {
                    throw error
                }
                completedRetryCount += 1
                // 被限流时同时抬高后续请求的基础间隔，避免下一批立刻再撞上同一堵墙。
                if case .requestRejected(429, _, _) = error as? AestheticReviewClientError {
                    adaptiveReviewInterval = min(
                        AIReviewConfiguration.maximumReviewInterval,
                        max(adaptiveReviewInterval * 2, delay)
                    )
                }
                let rangeLabel = photoRangeLabel(photoRange)
                statusMessage = String(localized: "第 \(rangeLabel) 张评分失败：\(error.localizedDescription) 将在 \(Int(delay.rounded(.up))) 秒后自动重试（\(completedRetryCount)/\(AIFinalSelectionRetryPolicy.maximumAutomaticRetryCount)）。")
                aiFinalSelectionRunProgress.waitingSeconds = Int(delay.rounded(.up))
                try await Task.sleep(for: .seconds(delay))
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
        // 计划阶段已经保证每个相似家族只出一个代表，走到这里还冲突说明是内部错误。
        // 即便如此也不能作废整轮（用户已经为全部请求付过费）：保留名次靠前的一张，其余顺延。
        let conflicts = CandidateFamilyIndex(photos: photos).conflicts(in: finalSelectionPhotoIDs)
        var acceptedPhotoIDs = finalSelectionPhotoIDs
        if !conflicts.isEmpty {
            assertionFailure("最终结果出现同一相似家族的多张照片：\(conflicts)")
            acceptedPhotoIDs = resolvingFamilyConflicts(
                in: finalSelectionPhotoIDs,
                rankedCandidatePhotoIDs: rankedCandidatePhotoIDs,
                lockedKeeperPhotoIDs: context.lockedKeeperPhotoIDs
            )
        }
        aiFinalSelectionPhotoIDsByCategory[context.category] =
            acceptedPhotoIDs
        aiFinalSelectionRunProgress.phase = .completed
        aiFinalSelectionRunProgress.completedPhotoCount =
            context.plan.candidatePhotoCount
        aiFinalSelectionRunProgress.waitingSeconds = 0
        aiFinalSelectionRunProgressByCategory[context.category] =
            aiFinalSelectionRunProgress
        aiFinalSelectionRunContext = nil
        // 主链路的下一步是"看结果并采纳"。评分结束时把用户直接带到这一类的结果视图，
        // 而不是让他自己回想该切回哪个类型、该选哪个筛选。
        curationScope = PhotoCurationScope(context.category)
        completionNotice = CurationCompletionNotice(
            id: UUID(),
            kind: .aiScoring(context.category),
            title: String(localized: "\(context.category.title) AI评分完成"),
            message: String(
                localized:
                    "\(context.plan.candidatePhotoCount) 张已按分数排序，AI 推荐保留其中 \(acceptedPhotoIDs.count) 张。逐张看过后，用底部的“采纳”确认。"
            )
        )
        statusMessage = conflicts.isEmpty
            ? String(
                localized:
                    "\(context.category.title) AI评分完成：AI 推荐保留 \(acceptedPhotoIDs.count) 张。请逐张查看后用底部的“采纳”确认。"
            )
            : String(
                localized:
                    "\(context.category.title) AI评分完成：AI 推荐保留 \(acceptedPhotoIDs.count) 张；\(conflicts.count) 张同场景重复已顺延。请逐张查看后用底部的“采纳”确认。"
            )
    }

    /// 同一家族只保留名次最高的一张（人工保留的照片优先级最高），冲突的其余照片让位给后面的候选。
    private func resolvingFamilyConflicts(
        in finalSelectionPhotoIDs: Set<String>,
        rankedCandidatePhotoIDs: [String],
        lockedKeeperPhotoIDs: [String]
    ) -> Set<String> {
        let lockedIDs = Set(lockedKeeperPhotoIDs)
        let rankByPhotoID = Dictionary(
            uniqueKeysWithValues: rankedCandidatePhotoIDs.enumerated().map { ($0.element, $0.offset) }
        )
        let familyIndex = CandidateFamilyIndex(photos: photos)
        let orderedSelection = finalSelectionPhotoIDs.sorted { lhs, rhs in
            if lockedIDs.contains(lhs) != lockedIDs.contains(rhs) {
                return lockedIDs.contains(lhs)
            }
            let lhsRank = rankByPhotoID[lhs] ?? Int.max
            let rhsRank = rankByPhotoID[rhs] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs < rhs
        }

        var acceptedIDs: Set<String> = []
        var usedFamilyIDs: Set<String> = []
        var droppedCount = 0
        for photoID in orderedSelection {
            if let familyID = familyIndex.familyID(for: photoID) {
                guard !usedFamilyIDs.contains(familyID) else {
                    droppedCount += 1
                    continue
                }
                usedFamilyIDs.insert(familyID)
            }
            acceptedIDs.insert(photoID)
        }

        guard droppedCount > 0 else { return acceptedIDs }
        // 被顺延的名额用没有家族冲突的后备候选补上，尽量仍然凑满目标数量。
        for photoID in rankedCandidatePhotoIDs where acceptedIDs.count < finalSelectionPhotoIDs.count {
            guard !acceptedIDs.contains(photoID) else { continue }
            if let familyID = familyIndex.familyID(for: photoID) {
                guard !usedFamilyIDs.contains(familyID) else { continue }
                usedFamilyIDs.insert(familyID)
            }
            acceptedIDs.insert(photoID)
        }
        return acceptedIDs
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

    /// 文件面板的用途。
    ///
    /// AppKit 的所有 `NSOpenPanel` 共用同一个 `NSOSPLastRootDirectory`：导出到某个
    /// 目录之后再点"新建筛选项目"，来源面板就停在那个导出目录里。两个用途各记
    /// 各的最后位置，展示前显式覆盖 `directoryURL`，彼此不再串。
    enum PanelPurpose {
        case source
        case export
    }

    /// 只留在内存里：绝对路径既不在隐私页披露的项目字段之内，
    /// 也会在文件夹被搬走后变成一条失效路径。
    private var lastSourceDirectory: URL?
    private var lastExportDirectory: URL?

    func defaultDirectory(for purpose: PanelPurpose) -> URL? {
        switch purpose {
        case .source:
            if let lastSourceDirectory { return lastSourceDirectory }
            // 每个日期文件夹是一项独立任务，所以下一个来源通常是当前项目的兄弟目录。
            // 这里不用 .picturesDirectory：App 处于沙箱且只有 user-selected 权限，
            // 那个 API 会解析到容器内部的空 Pictures，面板会停在一个什么都没有的地方。
            if let selectedFolder {
                return selectedFolder.deletingLastPathComponent()
            }
            return projects.compactMap(\.folderURL).first?.deletingLastPathComponent()
        case .export:
            return lastExportDirectory
        }
    }

    func rememberDirectory(_ url: URL, for purpose: PanelPurpose) {
        switch purpose {
        case .source:
            // 选中的是照片文件夹本身，记它的上一级，下次才能看到同级的其他日期文件夹。
            lastSourceDirectory = url.deletingLastPathComponent()
        case .export:
            lastExportDirectory = url
        }
    }

    /// 以 sheet 方式展示文件面板。
    ///
    /// 不能用 `runModal()`：它会在 SwiftUI 的更新过程中嵌套一个 run loop，
    /// 面板关闭后窗口的标题栏 inset 与命中测试可能停在错误状态——
    /// 表现就是"导出之后整个界面错位、按钮点不动"。
    ///
    /// `purpose` 是必填的：默认目录的隔离必须发生在这个统一入口里。放到调用方
    /// 各自设置的话，第三个调用点（重新授权）迟早又会漏掉。
    private func presentPanel(
        _ panel: NSOpenPanel,
        purpose: PanelPurpose,
        onSelect: @escaping (URL) -> Void
    ) {
        panel.directoryURL = defaultDirectory(for: purpose)
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.rememberDirectory(url, for: purpose)
            onSelect(url)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            panel.begin(completionHandler: handle)
        }
    }

    func requestExport() {
        guard canExport else {
            statusMessage = String(localized: "还没有保留任何照片，先保留至少一张再导出。")
            return
        }

        let panel = NSOpenPanel()
        panel.title = String(localized: "选择精选照片的导出位置")
        panel.message = String(
            localized:
                "App 将复制人物 \(keepers(in: .people).count) 张、风景 \(keepers(in: .scenery).count) 张，并分别放入两个子目录；不会移动或删除原图。"
        )
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        presentPanel(panel, purpose: .export) { [weak self] directory in
            guard let self else { return }
            guard !self.isInsideActiveProjectFolder(directory) else {
                self.statusMessage = String(
                    localized: "导出目录不能选在原照片文件夹内部；请选择项目目录之外的位置。"
                )
                return
            }
            self.pendingExportDirectory = directory
            self.showExportConfirmation = true
        }
    }

    /// 导出目录不能落在项目目录内部。
    ///
    /// 一是原图目录必须保持只读；二是导出的副本会在下一次扫描时被递归枚举成"新照片"，
    /// 把同一张照片变成两张。
    func isInsideActiveProjectFolder(_ url: URL) -> Bool {
        guard let folder = activeProject?.folderURL else { return false }
        let root = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let target = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard target.count >= root.count else { return false }
        return Array(target.prefix(root.count)) == root
    }

    func exportKeepers() {
        guard let destinationParent = pendingExportDirectory, canExport else {
            pendingExportDirectory = nil
            showExportConfirmation = false
            statusMessage = String(localized: "还没有保留任何照片，先保留至少一张再导出。")
            return
        }
        let exportPhotos = keepers
        pendingExportDirectory = nil
        showExportConfirmation = false
        statusMessage = String(localized: "正在安全复制 \(exportPhotos.count) 张精选照片…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let exportURL = try ExportService.copyCategorized(
                    photos: exportPhotos,
                    to: destinationParent
                )
                DispatchQueue.main.async {
                    self?.statusMessage = String(localized: "导出完成：\(exportURL.lastPathComponent)。原图未被修改。")
                    self?.completionNotice = CurationCompletionNotice(
                        id: UUID(),
                        kind: .export(exportURL),
                        title: String(localized: "导出完成"),
                        message: String(
                            localized:
                                "已复制 \(exportPhotos.count) 张到“\(exportURL.lastPathComponent)”。原图没有被移动、删除或修改。"
                        )
                    )
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
        flushPendingProjectState()
        guard let activeProjectID, !photos.isEmpty else { return }
        projectSnapshots[activeProjectID] = PhotoProjectSnapshot(
            photos: photos,
            selectedPhotoID: selectedPhotoID,
            curationScope: curationScope,
            selectionTargets: selectionTargets,
            statusMessage: statusMessage,
            latestAIUsageMessage: latestAIUsageMessage,
            completionNotice: completionNotice,
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
        replacePhotos(snapshot.photos)
        selectedPhotoID = snapshot.selectedPhotoID ?? snapshot.photos.first?.id
        curationScope = snapshot.curationScope
        selectionTargets = snapshot.selectionTargets
        statusMessage = snapshot.statusMessage
        latestAIUsageMessage = snapshot.latestAIUsageMessage
        completionNotice = snapshot.completionNotice
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
        scanTask?.cancel()
        analysisTask?.cancel()
        groupingTask?.cancel()
        scanTask = nil
        analysisTask = nil
        groupingTask = nil
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
        replacePhotos([])
        selectedPhotoID = nil
        curationScope = .all
        selectionTargets = .default
        aiFinalSelectionPhotoIDsByCategory = [:]
        aiFinalSelectionRunProgress = AIFinalSelectionRunProgress()
        aiFinalSelectionRunProgressByCategory = [:]
        firstCurationGuideStep = nil
        demoModeSession = nil
        isRunningDemoAIScoring = false
        demoAIScoringCompletedBatchCount = 0
        demoAIScoringCompletedPhotoCount = 0
        latestAIUsageMessage = nil
        completionNotice = nil
        undoStack = []
        isScanning = false
        isAnalyzing = false
        isGroupingCandidates = false
        analysisCompleted = 0
        analysisTotal = 0
    }

    func prepareForTermination() {
        flushPendingProjectState()
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

        presentPanel(panel, purpose: .source) { [weak self] folder in
            self?.completeReauthorization(of: projectID, with: folder)
        }
    }

    private func completeReauthorization(of projectID: UUID, with folder: URL) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
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

    /// 选片按键是最高频的操作，不能在每次按键上做全量快照和写盘。
    /// 这里只登记“有改动”，由去抖任务合并成一次落盘；需要立刻可见的时机调用 `flushPendingProjectState()`。
    private func persistActiveProjectState() {
        guard !isRestoringPersistedState else { return }
        hasPendingProjectStateChanges = true
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.flushPendingProjectState()
        }
    }

    /// 立即把当前项目状态写入磁盘。项目切换、删除、导出和退出前必须调用。
    func flushPendingProjectState() {
        persistDebounceTask?.cancel()
        persistDebounceTask = nil
        guard hasPendingProjectStateChanges else { return }
        hasPendingProjectStateChanges = false
        writeActiveProjectState()
    }

    private func writeActiveProjectState() {
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
            if relativePathByPhotoID.isEmpty {
                rebuildRelativePathIndex(folderURL: folderURL)
            }
            persisted.decisionsByRelativePath = Dictionary(uniqueKeysWithValues: photos.compactMap { photo in
                guard photo.decision != .undecided,
                      let relativePath = relativePathByPhotoID[photo.id] else {
                    return nil
                }
                return (relativePath, photo.decision)
            })
            persisted.selectedRelativePath = selectedPhoto.flatMap {
                relativePathByPhotoID[$0.id]
            }
            persisted.categoryOverridesByRelativePath = Dictionary(
                uniqueKeysWithValues: photos.compactMap { photo in
                    guard photo.isCurationCategoryUserAssigned,
                          let category = photo.curationCategory,
                          let relativePath = relativePathByPhotoID[photo.id] else {
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

    /// 后台并行分析。每完成一批就回到主 actor 合并结果，取消后台任务会真正停止解码工作。
    private func startAnalysis(of items: [PhotoItem], sessionID: UUID) {
        let urls = items.map(\.url)
        let batchSize = analysisBatchSize
        guard !urls.isEmpty else { return }

        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await PhotoAnalysisPipeline.analyze(
                urls: urls,
                batchSize: batchSize
            ) { results in
                await MainActor.run {
                    guard let self, self.analysisSessionID == sessionID else { return }
                    self.replacePhotos(PhotoAnalysisMerger.applying(results, to: self.photos))
                    self.analysisCompleted = min(self.analysisCompleted + results.count, self.analysisTotal)
                    self.invalidateCandidatePlans()
                }
            }

            guard let self, !Task.isCancelled, self.analysisSessionID == sessionID else { return }
            self.isGroupingCandidates = true
            self.finishCandidateGrouping(for: self.photos, sessionID: sessionID)
        }
    }

    private func finishCandidateGrouping(for snapshot: [PhotoItem], sessionID: UUID) {
        groupingTask?.cancel()
        groupingTask = Task { [weak self] in
            let grouped = await Task.detached(priority: .userInitiated) {
                () -> (
                    groups: [String: SimilarityGroupMembership?],
                    recommendations: [String: [GroupRecommendation]],
                    quality: [String: TechnicalQuality?]
                ) in
                let visualInput = snapshot.map { photo in
                    var updated = photo
                    updated.burstGroup = nil
                    return updated
                }
                let groupedPhotos = SimilarityGrouper.assigningGroups(to: visualInput)
                // 清晰度风险要等家族建立后才能判断：参考值来自同一家族，其次才是整库。
                let scoredPhotos = TechnicalQualityAnalyzer.assigningSharpnessRisks(to: groupedPhotos)
                let recommendedPhotos = LocalCandidateRanker.assigningRecommendations(to: scoredPhotos)
                return (
                    Dictionary(uniqueKeysWithValues: recommendedPhotos.map { ($0.id, $0.similarityGroup) }),
                    Dictionary(uniqueKeysWithValues: recommendedPhotos.map { ($0.id, $0.localRecommendations) }),
                    Dictionary(uniqueKeysWithValues: recommendedPhotos.map { ($0.id, $0.technicalQuality) })
                )
            }.value
            let similarityGroups = grouped.groups
            let recommendations = grouped.recommendations
            let refreshedQuality = grouped.quality

            do {
                guard let self, !Task.isCancelled, self.analysisSessionID == sessionID else { return }
                for index in self.photos.indices {
                    let photoID = self.photos[index].id
                    self.photos[index].burstGroup = nil
                    self.photos[index].similarityGroup = similarityGroups[photoID] ?? nil
                    self.photos[index].localRecommendations = recommendations[photoID] ?? []
                    if let quality = refreshedQuality[photoID] {
                        self.photos[index].technicalQuality = quality
                    }
                }
                self.isGroupingCandidates = false
                self.isAnalyzing = false
                // 相似家族、清晰度风险和本地排序都是候选池的输入，而且这里是就地改写
                // `photos`（没有走 `replacePhotos`）。不作废缓存的话，
                // 界面会一直沿用分析期间读到的空候选池，"待评分"筛选和徽标全是 0。
                self.invalidateCandidatePlans()
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
}
