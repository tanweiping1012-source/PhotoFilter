import Foundation
import Vision

enum PhotoCurationCategory: String, CaseIterable, Codable, Identifiable {
    case people
    case scenery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .people: String(localized: "人物")
        case .scenery: String(localized: "风景")
        }
    }

    var systemImage: String {
        switch self {
        case .people: "person.2.fill"
        case .scenery: "mountain.2.fill"
        }
    }

    var scoringInstruction: String {
        switch self {
        case .people:
            String(
                localized:
                    "本次全部为人物照片。重点观察人物表情、姿态、互动、遮挡、人物清晰度和人物与环境的关系；风景只作为人物叙事背景。不得推断身份或敏感属性。"
            )
        case .scenery:
            String(
                localized:
                    "本次全部为风景照片。重点观察空间层次、构图、光线、氛围和地点叙事；不得因为画面中没有人物而降低分数。"
            )
        }
    }
}

enum PhotoCurationScope: String, CaseIterable, Identifiable {
    case all
    case people
    case scenery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "全部")
        case .people: PhotoCurationCategory.people.title
        case .scenery: PhotoCurationCategory.scenery.title
        }
    }

    var systemImage: String {
        switch self {
        case .all: "photo.stack"
        case .people: PhotoCurationCategory.people.systemImage
        case .scenery: PhotoCurationCategory.scenery.systemImage
        }
    }

    init(_ category: PhotoCurationCategory) {
        switch category {
        case .people: self = .people
        case .scenery: self = .scenery
        }
    }

    var category: PhotoCurationCategory? {
        switch self {
        case .all: nil
        case .people: .people
        case .scenery: .scenery
        }
    }

    func includes(_ category: PhotoCurationCategory?) -> Bool {
        guard self != .all else { return true }
        return self.category == category
    }
}

struct PhotoSelectionTargets: Codable, Equatable {
    var people: Int
    var scenery: Int

    static let `default` = PhotoSelectionTargets(people: 6, scenery: 6)

    init(people: Int, scenery: Int) {
        self.people = max(0, people)
        self.scenery = max(0, scenery)
    }

    init(legacyTotal: Int) {
        let total = max(0, legacyTotal)
        people = (total + 1) / 2
        scenery = total / 2
    }

    var total: Int {
        people + scenery
    }

    subscript(category: PhotoCurationCategory) -> Int {
        get {
            switch category {
            case .people: people
            case .scenery: scenery
            }
        }
        set {
            switch category {
            case .people: people = max(0, newValue)
            case .scenery: scenery = max(0, newValue)
            }
        }
    }
}

enum PhotoDecision: String, CaseIterable, Codable {
    case undecided
    case keep
    case reject

    var title: String {
        switch self {
        case .undecided: String(localized: "待定")
        case .keep: String(localized: "保留")
        case .reject: String(localized: "淘汰")
        }
    }

    var symbolName: String {
        switch self {
        case .undecided: "circle"
        case .keep: "checkmark.circle.fill"
        case .reject: "xmark.circle.fill"
        }
    }
}

struct PhotoItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let filename: String
    var captureDate: Date?
    var perceptualHash: PerceptualHash?
    var technicalQuality: TechnicalQuality?
    var curationCategory: PhotoCurationCategory?
    var isCurationCategoryUserAssigned: Bool
    var decision: PhotoDecision
    var burstGroup: BurstGroupMembership?
    var similarityGroup: SimilarityGroupMembership?
    var localRecommendations: [GroupRecommendation]
    var aestheticRecommendations: [AestheticRecommendation]

    init(
        url: URL,
        decision: PhotoDecision = .undecided,
        captureDate: Date? = nil,
        perceptualHash: PerceptualHash? = nil,
        technicalQuality: TechnicalQuality? = nil,
        curationCategory: PhotoCurationCategory? = nil,
        isCurationCategoryUserAssigned: Bool = false,
        burstGroup: BurstGroupMembership? = nil,
        similarityGroup: SimilarityGroupMembership? = nil,
        localRecommendations: [GroupRecommendation] = [],
        aestheticRecommendations: [AestheticRecommendation] = []
    ) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.filename = url.lastPathComponent
        self.captureDate = captureDate
        self.perceptualHash = perceptualHash
        self.technicalQuality = technicalQuality
        self.curationCategory = curationCategory
        self.isCurationCategoryUserAssigned =
            isCurationCategoryUserAssigned
        self.decision = decision
        self.burstGroup = burstGroup
        self.similarityGroup = similarityGroup
        self.localRecommendations = localRecommendations
        self.aestheticRecommendations = aestheticRecommendations
    }

    var primaryAestheticRecommendation: AestheticRecommendation? {
        if let curationCategory,
           let matchingFinal = aestheticRecommendations.last(where: {
               $0.scope.kind == .finalSelection
                   && $0.scope.category == curationCategory
           }) {
            return matchingFinal
        }
        return aestheticRecommendations.last {
            $0.scope.kind == .finalSelection
        } ?? aestheticRecommendations.last
    }
}

/// 连续拍摄的一组候选照片中的位置。它只帮助浏览和比较，绝不会改变用户的选片决定。
struct BurstGroupMembership: Equatable {
    let id: String
    let position: Int
    let count: Int
}

/// 画面相似照片集合中的位置。仅供用户展开比较，不会自动改变选片结果。
struct SimilarityGroupMembership: Equatable {
    let id: String
    let position: Int
    let count: Int
}

enum CandidateGroupKind: String, Codable, Equatable {
    case burst
    case similarity
    /// 只用于 AI 的第一轮覆盖：将没有画面相似关系的相邻旅行照片组成传输窗口。
    /// 它不会写入 PhotoItem 的本地分组标记。
    case curation
    /// 完整 AI评分流程的独立评分窗口；最终结果由全部照片全局排序产生。
    case finalSelection

    var title: String {
        switch self {
        case .burst, .similarity: String(localized: "相似照片")
        case .curation: String(localized: "AI评分")
        case .finalSelection: String(localized: "AI评分")
        }
    }
}

/// 一项由本地技术信号生成的组内浏览顺序，不是 AI评分，也不会改变人工选择。
struct GroupRecommendation: Equatable {
    let kind: CandidateGroupKind
    let groupID: String
    let rank: Int
    let groupSize: Int
    let explanation: String

    var isTopCandidate: Bool {
        rank == 1
    }
}


enum SelectionRules {
    static func keepers(in photos: [PhotoItem]) -> [PhotoItem] {
        photos.filter { $0.decision == .keep }
    }
}
