import Foundation

struct AestheticReviewCandidateGroup: Equatable {
    let scope: AestheticReviewScope
    let localPhotoIDs: [String]

    var photoCount: Int {
        localPhotoIDs.count
    }
}

struct AIFinalSelectionRunPlan: Equatable {
    let groups: [AestheticReviewCandidateGroup]
    let candidatePhotoCount: Int
    let targetWinnerCount: Int

    var requestCount: Int { groups.count }

    var transmittedPhotoCount: Int {
        groups.reduce(0) { $0 + $1.photoCount }
    }

    var coveredPhotoIDs: Set<String> {
        Set(groups.flatMap(\.localPhotoIDs))
    }

    var estimatedMinimumDuration: TimeInterval {
        TimeInterval(max(0, requestCount - 1)) * AIReviewConfiguration.minimumReviewInterval
    }

    var estimatedMinimumMinutes: Int {
        Int(ceil(estimatedMinimumDuration / 60))
    }

    func photoRange(forGroupAt index: Int) -> ClosedRange<Int>? {
        guard groups.indices.contains(index) else { return nil }
        let completedBefore = groups[..<index].reduce(0) {
            $0 + $1.photoCount
        }
        let start = completedBefore + 1
        return start...(completedBefore + groups[index].photoCount)
    }
}

enum AIFinalSelectionRunPlanError: LocalizedError, Equatable {
    case emptyTarget
    case emptyCandidatePool
    case duplicateCandidateID

    var errorDescription: String? {
        switch self {
        case .emptyTarget: String(localized: "保留目标必须至少为 1 张。")
        case .emptyCandidatePool: String(localized: "当前没有待评分的照片。")
        case .duplicateCandidateID: String(localized: "待评分照片包含重复项，无法开始评分。")
        }
    }
}

/// 把候选池切成传输窗口。窗口不代表比较组，也不产生局部胜者。
/// 窗口容量为 1 时每张照片单独成为一次请求，彻底消除同一请求内照片互相影响的可能。
enum AIFinalSelectionRunPlanner {
    static func makePlan(
        candidateLocalPhotoIDs: [String],
        targetWinnerCount: Int,
        category: PhotoCurationCategory? = nil,
        maximumPhotosPerReview: Int = AIReviewConfiguration.maximumPhotosPerReview
    ) throws -> AIFinalSelectionRunPlan {
        guard targetWinnerCount > 0 else {
            throw AIFinalSelectionRunPlanError.emptyTarget
        }
        // 候选池为空和"保留目标为 0"是两种完全不同的处境，必须分开报告：
        // 前者要用户去调整决定或目标，后者根本不该出现。共用一句话会把用户指向错误的操作。
        guard !candidateLocalPhotoIDs.isEmpty else {
            throw AIFinalSelectionRunPlanError.emptyCandidatePool
        }
        guard Set(candidateLocalPhotoIDs).count == candidateLocalPhotoIDs.count else {
            throw AIFinalSelectionRunPlanError.duplicateCandidateID
        }
        // 候选多于目标、少于目标都允许开始：
        // 候选多只是让 AI 有更大的挑选空间，候选少则最多只能选出候选那么多张。
        // 用"候选必须达到目标的 2 倍"把用户挡在门外，是把内部偏好当成了硬性前置条件。
        let effectiveWinnerCount = min(targetWinnerCount, candidateLocalPhotoIDs.count)

        // 容量必须至少为 1，否则游标永远不前进。
        let windowCapacity = max(1, maximumPhotosPerReview)
        // "避免最后落单一张"只有在窗口装得下 2 张以上时才有意义。窗口本来就是 1 张时
        // 套用这条规则会算出 windowSize = 0，游标停在原地，整个规划陷入死循环。
        let avoidsTrailingSinglePhoto = windowCapacity >= 2

        var cursor = 0
        var groups: [AestheticReviewCandidateGroup] = []
        while candidateLocalPhotoIDs.count - cursor > windowCapacity {
            let remainingAfterFullWindow =
                candidateLocalPhotoIDs.count - (cursor + windowCapacity)
            let windowSize = (avoidsTrailingSinglePhoto && remainingAfterFullWindow == 1)
                ? windowCapacity - 1
                : windowCapacity
            let ids = Array(
                candidateLocalPhotoIDs[cursor..<(cursor + windowSize)]
            )
            groups.append(
                AestheticReviewCandidateGroup(
                    scope: AestheticReviewScope(
                        kind: .finalSelection,
                        groupID: String(
                            format: "ai-score-window-%03d",
                            groups.count + 1
                        ),
                        category: category
                    ),
                    localPhotoIDs: ids
                )
            )
            cursor += windowSize
        }
        let remainingIDs = Array(candidateLocalPhotoIDs[cursor...])
        if !remainingIDs.isEmpty {
            groups.append(
                AestheticReviewCandidateGroup(
                    scope: AestheticReviewScope(
                        kind: .finalSelection,
                        groupID: String(
                            format: "ai-score-window-%03d",
                            groups.count + 1
                        ),
                        category: category
                    ),
                    localPhotoIDs: remainingIDs
                )
            )
        }

        return AIFinalSelectionRunPlan(
            groups: groups,
            candidatePhotoCount: candidateLocalPhotoIDs.count,
            targetWinnerCount: effectiveWinnerCount
        )
    }
}

struct AIFinalSelectionScore: Equatable {
    let photoID: String
    let dimensions: AestheticScoreDimensions
}

/// 产生某一类候选分数的模型与预览尺寸。
///
/// "停止后继续"复用的是已经付过费的旧分数，前提是它们和新分数出自同一套标准。
/// 换过模型或预览尺寸就不能再复用：把两套标准的分数排进同一个名次里，
/// 省下的钱会变成一个错误的排序。这时整池重评才是对的。
struct AIFinalSelectionScoreOrigin: Equatable {
    let modelID: AIModelID
    let previewSize: AIReviewPreviewSize
}

enum AestheticScoreRanking {
    static func precedes(
        dimensions lhs: AestheticScoreDimensions,
        photoID lhsID: String,
        dimensions rhs: AestheticScoreDimensions,
        photoID rhsID: String,
        weights: AestheticScoreWeights
    ) -> Bool {
        let lhsTotal = AestheticScoreTotal.total(dimensions: lhs, weights: weights)
        let rhsTotal = AestheticScoreTotal.total(dimensions: rhs, weights: weights)
        if lhsTotal != rhsTotal { return lhsTotal > rhsTotal }

        // 加权总分打平时依次用未加权总和、固定的维度顺序、照片 ID 决胜。
        // 这几步与权重无关，保证任何权重下的排序都是全序且可复现。
        let lhsDimensionTotal = lhs.scores.reduce(0, +)
        let rhsDimensionTotal = rhs.scores.reduce(0, +)
        if lhsDimensionTotal != rhsDimensionTotal {
            return lhsDimensionTotal > rhsDimensionTotal
        }

        let lhsTieBreak = [
            lhs.storytelling,
            lhs.moment,
            lhs.composition,
            lhs.subject,
            lhs.lighting,
        ]
        let rhsTieBreak = [
            rhs.storytelling,
            rhs.moment,
            rhs.composition,
            rhs.subject,
            rhs.lighting,
        ]
        for (left, right) in zip(lhsTieBreak, rhsTieBreak) where left != right {
            return left > right
        }
        return lhsID.localizedStandardCompare(rhsID) == .orderedAscending
    }

    static func precedes(
        _ lhs: AestheticRecommendation,
        photoID lhsID: String,
        _ rhs: AestheticRecommendation,
        photoID rhsID: String,
        weights: AestheticScoreWeights
    ) -> Bool {
        precedes(
            dimensions: lhs.dimensions,
            photoID: lhsID,
            dimensions: rhs.dimensions,
            photoID: rhsID,
            weights: weights
        )
    }
}

enum AIFinalSelectionRunValidationError: LocalizedError, Equatable {
    case duplicateScore
    case scoreOutsideCandidatePool
    case incompleteCandidateScores
    case finalCountMismatch
    case duplicateCandidateFamily

    var errorDescription: String? {
        switch self {
        case .duplicateScore: String(localized: "AI评分结果包含重复照片，已停止应用结果。")
        case .scoreOutsideCandidatePool: String(localized: "AI评分结果包含待评分范围外的照片，已停止应用结果。")
        case .incompleteCandidateScores: String(localized: "AI评分结果未覆盖全部候选照片，已停止应用结果。")
        case .finalCountMismatch: String(localized: "AI评分结果数量与保留目标不一致，已停止应用结果。")
        case .duplicateCandidateFamily: String(localized: "AI评分结果仍包含多张画面相似照片，结果未生效。")
        }
    }
}

/// 一轮 AI评分该锁住什么。
///
/// 人物和风景各有独立的目标、候选池、运行状态和结果，所以一轮任务只锁它自己那一类。
/// 用一个全局开关把整个界面（照片类型、决定、撤销、目标）一起锁住，
/// 用户会以为 App 卡死了——而实际上另一类的所有操作都是安全的。
enum AIFinalSelectionRunLock {
    static func isLocked(
        category: PhotoCurationCategory?,
        runningCategory: PhotoCurationCategory?
    ) -> Bool {
        guard let runningCategory else { return false }
        // 还没分类的照片按锁定处理：它随时可能被归到正在评分的那一类。
        return category == nil || category == runningCategory
    }
}

enum AIFinalSelectionRetryPolicy {
    /// 限流和网络抖动是 BYOK 场景的常态，不能让整轮评分（以及已经付过的 token）为一次 429 作废。
    static let maximumAutomaticRetryCount = 4
    static let maximumBackoff: TimeInterval = 60

    /// 返回下一次重试前应等待的秒数；返回 nil 表示这个错误不该重试。
    static func retryDelay(
        for error: Error,
        completedRetryCount: Int,
        jitter: Double = Double.random(in: 0.8...1.2)
    ) -> TimeInterval? {
        guard completedRetryCount < maximumAutomaticRetryCount else { return nil }
        let backoff = min(maximumBackoff, pow(2, Double(completedRetryCount)) * 2) * jitter

        if let clientError = error as? AestheticReviewClientError {
            switch clientError {
            case .invalidResponse:
                // 模型偶发地把 JSON 写坏；短暂冷却后重试通常就能拿到合法结果。
                return min(backoff, 5)
            case let .requestRejected(statusCode, _, retryAfter):
                guard statusCode == 429 || (500...599).contains(statusCode) else { return nil }
                return retryAfter ?? backoff
            case .invalidConfiguration, .incompletePreviewSet:
                return nil
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .secureConnectionFailed:
                return backoff
            default:
                return nil
            }
        }

        guard let validationError = error as? AestheticReviewValidationError else {
            return nil
        }
        switch validationError {
        case .duplicatePhotoID,
             .photoIDMismatch,
             .invalidDimensions,
             .invalidReasons,
             .invalidSummary,
             .relativeComparison:
            return min(backoff, 5)
        case .unsupportedVersion, .requestIDMismatch, .scopeMismatch, .emptyRequest:
            return nil
        }
    }

    static func shouldRetry(_ error: Error, completedRetryCount: Int) -> Bool {
        retryDelay(for: error, completedRetryCount: completedRetryCount, jitter: 1) != nil
    }
}

enum AIFinalSelectionRunValidator {
    static func scoredPhotos(
        from response: AestheticReviewResponse,
        request: AestheticReviewRequest,
        localPhotoIDs: [String]
    ) throws -> [AIFinalSelectionScore] {
        try AestheticReviewValidator.validate(response, for: request)
        guard localPhotoIDs.count == request.photos.count else {
            throw AIFinalSelectionRunValidationError.incompleteCandidateScores
        }

        let entryByOpaqueID = Dictionary(
            uniqueKeysWithValues: response.reviews.map { ($0.photoID, $0) }
        )
        return try zip(request.photos, localPhotoIDs).map { input, localID in
            guard let entry = entryByOpaqueID[input.photoID] else {
                throw AIFinalSelectionRunValidationError.incompleteCandidateScores
            }
            return AIFinalSelectionScore(
                photoID: localID,
                dimensions: entry.dimensions
            )
        }
    }

    static func rankedCandidatePhotoIDs(
        scores: [AIFinalSelectionScore],
        candidatePhotoIDs: Set<String>,
        weights: AestheticScoreWeights
    ) throws -> [String] {
        let returnedPhotoIDs = scores.map(\.photoID)
        guard Set(returnedPhotoIDs).count == returnedPhotoIDs.count else {
            throw AIFinalSelectionRunValidationError.duplicateScore
        }
        guard Set(returnedPhotoIDs).isSubset(of: candidatePhotoIDs) else {
            throw AIFinalSelectionRunValidationError.scoreOutsideCandidatePool
        }
        guard Set(returnedPhotoIDs) == candidatePhotoIDs else {
            throw AIFinalSelectionRunValidationError.incompleteCandidateScores
        }

        return scores.sorted { lhs, rhs in
            AestheticScoreRanking.precedes(
                dimensions: lhs.dimensions,
                photoID: lhs.photoID,
                dimensions: rhs.dimensions,
                photoID: rhs.photoID,
                weights: weights
            )
        }.map(\.photoID)
    }

    static func finalSelectionIDs(
        rankedCandidatePhotoIDs: [String],
        lockedKeeperPhotoIDs: [String],
        candidatePhotoIDs: Set<String>,
        targetSelectionCount: Int
    ) throws -> Set<String> {
        guard Set(rankedCandidatePhotoIDs).count
                == rankedCandidatePhotoIDs.count else {
            throw AIFinalSelectionRunValidationError.duplicateScore
        }
        guard Set(rankedCandidatePhotoIDs) == candidatePhotoIDs else {
            throw AIFinalSelectionRunValidationError.incompleteCandidateScores
        }

        let lockedKeeperIDs = Set(lockedKeeperPhotoIDs)
        let remainingSelectionCount = max(0, targetSelectionCount - lockedKeeperIDs.count)
        // 候选少于剩余目标时取实际可得数量，而不是在跑完（并付过费）之后判定整轮失败。
        let achievableCount = min(remainingSelectionCount, rankedCandidatePhotoIDs.count)
        let selectedCandidateIDs = Set(
            rankedCandidatePhotoIDs.prefix(achievableCount)
        )
        let finalIDs = selectedCandidateIDs.union(lockedKeeperIDs)
        // 人工保留项与候选池必须互斥；重叠说明上游状态不一致。
        guard finalIDs.count == lockedKeeperIDs.count + achievableCount else {
            throw AIFinalSelectionRunValidationError.finalCountMismatch
        }
        return finalIDs
    }
}

enum AIFinalSelectionRunPhase: Equatable {
    case idle
    case running
    case paused
    case failed
    case stopped
    case completed

    var title: String {
        switch self {
        case .idle: String(localized: "尚未开始")
        case .running: String(localized: "正在评估")
        case .paused: String(localized: "已暂停")
        case .failed: String(localized: "失败并停止")
        case .stopped: String(localized: "已停止")
        case .completed: String(localized: "已完成")
        }
    }
}

struct AIFinalSelectionRunProgress: Equatable {
    var phase: AIFinalSelectionRunPhase = .idle
    var completedBatchCount = 0
    var totalBatchCount = 0
    var completedPhotoCount = 0
    var candidatePhotoCount = 0
    var targetWinnerCount = 0
    var inputTokens = 0
    var outputTokens = 0
    var waitingSeconds = 0
    /// 本轮此刻正在做什么，例如"正在生成大图预览"。
    ///
    /// 它必须紧挨着进度条显示，而不是写进顶部的项目状态行——那行离进度条隔了大半个窗口，
    /// 用户要在两处之间来回找，才能把"1/18 张"和"正在评估第 2 张"对上。
    var activity: String?
    var failureMessage: String?

    var fractionCompleted: Double {
        guard candidatePhotoCount > 0 else { return 0 }
        return Double(completedPhotoCount) / Double(candidatePhotoCount)
    }

    var usageSummary: String? {
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return String(localized: "本轮：输入 \(inputTokens) tokens，输出 \(outputTokens) tokens。费用以所选供应商账单为准。")
    }
}

/// 一次待确认的照片类型改动。
///
/// 改类型会清空人物和风景两边全部 AI评分结果，而且不进撤销栈——用户为这些结果
/// 付过费。所以有结果可清时必须先问，而不是事后在某处补一句"已清除"。
struct PendingCurationCategoryChange: Equatable {
    let photoID: String
    let filename: String
    let category: PhotoCurationCategory
}
