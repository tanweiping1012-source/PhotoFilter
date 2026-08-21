import Foundation

enum AestheticReviewContract {
    static let version = "v4"
}

/// 发送给视觉模型的照片批次标识。不包含本地绝对路径，也不包含原始文件名。
struct AestheticReviewScope: Codable, Equatable {
    let kind: CandidateGroupKind
    let groupID: String
    let category: PhotoCurationCategory?

    init(
        kind: CandidateGroupKind,
        groupID: String,
        category: PhotoCurationCategory? = nil
    ) {
        self.kind = kind
        self.groupID = groupID
        self.category = category
    }
}

/// 一个仅在一次 AI评分请求内有效的匿名照片 ID。
/// 模型永远不会看到 PhotoItem.id（本地路径）或原始文件名。
struct AestheticReviewInput: Codable, Equatable {
    let photoID: String
    let position: Int
}

/// 视觉模型的输入元数据。缩略图字节由未来的网络适配器另行附带，不能使用原图 URL。
struct AestheticReviewRequest: Codable, Equatable {
    let version: String
    let requestID: String
    let scope: AestheticReviewScope
    let photos: [AestheticReviewInput]

    init(requestID: String, scope: AestheticReviewScope, photos: [AestheticReviewInput]) {
        self.version = AestheticReviewContract.version
        self.requestID = requestID
        self.scope = scope
        self.photos = photos
    }
}

/// 模型必须独立评估本次请求中的每一张图片；请求边界不代表比较组。
struct AestheticReviewResponse: Codable, Equatable {
    let version: String
    let requestID: String
    let scope: AestheticReviewScope
    let reviews: [AestheticReviewEntry]
}

/// 模型只返回五个维度分。总分由 `AestheticScoreTotal` 在本地按用户权重算出，
/// 不再是模型独立采样的第六个数字——那是同一张照片每次评分都得到不同总分的主要来源。
struct AestheticReviewEntry: Codable, Equatable {
    let photoID: String
    let dimensions: AestheticScoreDimensions
    let reasons: [String]
    let summary: String

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case dimensions
        case reasons
        case summary
    }

    func total(with weights: AestheticScoreWeights) -> Int {
        AestheticScoreTotal.total(dimensions: dimensions, weights: weights)
    }
}

struct AestheticScoreDimensions: Codable, Equatable {
    let moment: Int
    let composition: Int
    let subject: Int
    let lighting: Int
    let storytelling: Int

    var scores: [Int] {
        [moment, composition, subject, lighting, storytelling]
    }
}

enum AestheticScoreDimension: String, CaseIterable, Identifiable {
    case moment
    case composition
    case subject
    case lighting
    case storytelling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moment: String(localized: "瞬间")
        case .composition: String(localized: "构图")
        case .subject: String(localized: "主体")
        case .lighting: String(localized: "光线")
        case .storytelling: String(localized: "叙事表现")
        }
    }

    func score(in dimensions: AestheticScoreDimensions) -> Int {
        switch self {
        case .moment: dimensions.moment
        case .composition: dimensions.composition
        case .subject: dimensions.subject
        case .lighting: dimensions.lighting
        case .storytelling: dimensions.storytelling
        }
    }
}

/// 已通过契约校验、可以呈现在某一张照片上的 AI评分记录。
struct AestheticRecommendation: Equatable, Identifiable {
    let scope: AestheticReviewScope
    let dimensions: AestheticScoreDimensions
    let reasons: [String]
    let summary: String

    var id: String {
        "\(scope.kind.rawValue)-\(scope.groupID)"
    }

    /// 总分是视图，不是数据。权重变了同一条记录就该给出不同的总分，所以不能存成属性。
    func total(with weights: AestheticScoreWeights) -> Int {
        AestheticScoreTotal.total(dimensions: dimensions, weights: weights)
    }

    var reasonsSummary: String {
        reasons.formatted(.list(type: .and))
    }
}

enum AestheticReviewValidationError: LocalizedError, Equatable {
    case unsupportedVersion
    case requestIDMismatch
    case scopeMismatch
    case emptyRequest
    case duplicatePhotoID
    case photoIDMismatch
    case invalidDimensions
    case invalidReasons
    case invalidSummary
    case relativeComparison

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: String(localized: "AI评分结果版本不受支持。")
        case .requestIDMismatch: String(localized: "AI评分结果不属于当前请求。")
        case .scopeMismatch: String(localized: "AI评分结果不属于当前这些照片。")
        case .emptyRequest: String(localized: "AI评分请求中没有候选照片。")
        case .duplicatePhotoID: String(localized: "AI评分结果包含重复照片。")
        case .photoIDMismatch: String(localized: "AI评分结果与当前候选照片不一致。")
        case .invalidDimensions: String(localized: "AI评分结果包含不合法的维度分数。")
        case .invalidReasons: String(localized: "AI评分结果缺少可读的具体评价。")
        case .invalidSummary: String(localized: "AI评分结果缺少可读的总结。")
        case .relativeComparison: String(localized: "AI评分包含照片间的相对比较，已要求模型重新独立评分。")
        }
    }
}

/// 即使服务端启用 JSON Schema，也要在 App 侧重做业务校验。
/// 这样错误、过期或串组的结果永远不能影响候选排序。
enum AestheticReviewValidator {
    static func validate(
        _ response: AestheticReviewResponse,
        for request: AestheticReviewRequest
    ) throws {
        guard request.version == AestheticReviewContract.version,
              response.version == AestheticReviewContract.version else {
            throw AestheticReviewValidationError.unsupportedVersion
        }
        guard !request.photos.isEmpty else {
            throw AestheticReviewValidationError.emptyRequest
        }
        guard response.requestID == request.requestID else {
            throw AestheticReviewValidationError.requestIDMismatch
        }
        guard response.scope == request.scope else {
            throw AestheticReviewValidationError.scopeMismatch
        }

        let expectedPhotoIDs = request.photos.map(\.photoID)
        guard Set(expectedPhotoIDs).count == expectedPhotoIDs.count else {
            throw AestheticReviewValidationError.duplicatePhotoID
        }

        let returnedPhotoIDs = response.reviews.map(\.photoID)
        guard Set(returnedPhotoIDs).count == returnedPhotoIDs.count else {
            throw AestheticReviewValidationError.duplicatePhotoID
        }
        guard Set(returnedPhotoIDs) == Set(expectedPhotoIDs), returnedPhotoIDs.count == expectedPhotoIDs.count else {
            throw AestheticReviewValidationError.photoIDMismatch
        }

        guard response.reviews.allSatisfy({
            $0.dimensions.scores.allSatisfy { (0...100).contains($0) }
        }) else {
            throw AestheticReviewValidationError.invalidDimensions
        }
        guard response.reviews.allSatisfy({ entry in
            (1...3).contains(entry.reasons.count) && entry.reasons.allSatisfy { reason in
                let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                return (2...80).contains(trimmed.count)
            }
        }) else {
            throw AestheticReviewValidationError.invalidReasons
        }
        guard response.reviews.allSatisfy({ entry in
            let trimmed = entry.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return (4...120).contains(trimmed.count)
        }) else {
            throw AestheticReviewValidationError.invalidSummary
        }
        guard response.reviews.allSatisfy({ entry in
            let commentary = entry.reasons + [entry.summary]
            return commentary.allSatisfy {
                !containsRelativeComparison($0)
            }
        }) else {
            throw AestheticReviewValidationError.relativeComparison
        }
    }

    private static func containsRelativeComparison(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return [
            "本组",
            "同组",
            "相比",
            "首选",
            "优先",
            "候补",
            "更好",
            "更差",
            "弱于",
            "胜出",
            "排名",
            "名次",
            "in this group",
            "compared with",
            "compared to",
            "better than",
            "worse than",
            "top-ranked",
        ].contains { normalized.contains($0) }
    }
}

enum AestheticReviewRequestBuilder {
    static func make(
        scope: AestheticReviewScope,
        localPhotoIDs: [String],
        requestID: String = UUID().uuidString
    ) -> AestheticReviewRequest {
        let photos = localPhotoIDs.enumerated().map { offset, _ in
            AestheticReviewInput(photoID: String(format: "photo_%03d", offset + 1), position: offset + 1)
        }
        return AestheticReviewRequest(requestID: requestID, scope: scope, photos: photos)
    }
}

enum AestheticReviewApplier {
    /// 只有通过全部校验的结果才会写入运行时内存；不会改变 keep/reject 决定。
    static func applying(
        _ response: AestheticReviewResponse,
        for request: AestheticReviewRequest,
        localPhotoIDs: [String],
        to photos: [PhotoItem]
    ) throws -> [PhotoItem] {
        try AestheticReviewValidator.validate(response, for: request)
        guard localPhotoIDs.count == request.photos.count else {
            throw AestheticReviewValidationError.photoIDMismatch
        }

        let localIDByOpaqueID = Dictionary(uniqueKeysWithValues: zip(request.photos.map(\.photoID), localPhotoIDs))
        var updatedPhotos = photos

        for entry in response.reviews {
            guard let localPhotoID = localIDByOpaqueID[entry.photoID],
                  let index = updatedPhotos.firstIndex(where: { $0.id == localPhotoID }) else {
                throw AestheticReviewValidationError.photoIDMismatch
            }
            let recommendation = AestheticRecommendation(
                scope: response.scope,
                dimensions: entry.dimensions,
                reasons: entry.reasons,
                summary: entry.summary
            )
            updatedPhotos[index].aestheticRecommendations.removeAll { $0.scope == response.scope }
            updatedPhotos[index].aestheticRecommendations.append(recommendation)
        }
        return updatedPhotos
    }
}
