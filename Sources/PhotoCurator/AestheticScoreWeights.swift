import Foundation

/// 五个维度的相对权重。
///
/// 模型只返回五个维度分，总分完全在本地由权重算出。这有两个后果，都是刻意的：
/// 1. 总分不再是模型独立采样的第六个数字，同样的维度分永远得到同样的总分；
/// 2. 改权重只是换一种看法，不重新调用模型、不产生任何费用，排序立刻更新。
///
/// 权重不会发送给模型，模型也不知道权重存在。
struct AestheticScoreWeights: Codable, Equatable {
    static let minimumWeight = 0
    static let maximumWeight = 5

    private(set) var moment: Int
    private(set) var composition: Int
    private(set) var subject: Int
    private(set) var lighting: Int
    private(set) var storytelling: Int

    /// 默认五维等权。没有证据说明哪一维对所有人更重要，等权是唯一不替用户做决定的起点。
    static let balanced = AestheticScoreWeights(
        moment: 3,
        composition: 3,
        subject: 3,
        lighting: 3,
        storytelling: 3
    )

    init(
        moment: Int,
        composition: Int,
        subject: Int,
        lighting: Int,
        storytelling: Int
    ) {
        self.moment = Self.clamped(moment)
        self.composition = Self.clamped(composition)
        self.subject = Self.clamped(subject)
        self.lighting = Self.clamped(lighting)
        self.storytelling = Self.clamped(storytelling)
    }

    /// 磁盘上的值可能来自旧版本或被手工改过，解码时同样要收敛到合法区间。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            moment: try container.decode(Int.self, forKey: .moment),
            composition: try container.decode(Int.self, forKey: .composition),
            subject: try container.decode(Int.self, forKey: .subject),
            lighting: try container.decode(Int.self, forKey: .lighting),
            storytelling: try container.decode(Int.self, forKey: .storytelling)
        )
    }

    private static func clamped(_ value: Int) -> Int {
        min(maximumWeight, max(minimumWeight, value))
    }

    /// 顺序必须与 `AestheticScoreDimensions.scores` 一致。
    var values: [Int] {
        [moment, composition, subject, lighting, storytelling]
    }

    /// 五维全部为 0 时没有任何维度参与，加权总分无意义。
    var isDegenerate: Bool {
        values.allSatisfy { $0 == 0 }
    }

    func weight(for dimension: AestheticScoreDimension) -> Int {
        switch dimension {
        case .moment: moment
        case .composition: composition
        case .subject: subject
        case .lighting: lighting
        case .storytelling: storytelling
        }
    }

    func setting(_ weight: Int, for dimension: AestheticScoreDimension) -> AestheticScoreWeights {
        var updated = self
        let clampedWeight = Self.clamped(weight)
        switch dimension {
        case .moment: updated.moment = clampedWeight
        case .composition: updated.composition = clampedWeight
        case .subject: updated.subject = clampedWeight
        case .lighting: updated.lighting = clampedWeight
        case .storytelling: updated.storytelling = clampedWeight
        }
        return updated
    }
}

enum AestheticScoreTotal {
    /// 用整数运算完成四舍五入，全程不经过浮点，因此同样的输入在任何机器上都得到同样的总分。
    /// `(2 * 加权和 + 权重和) / (2 * 权重和)` 等价于 floor(加权平均 + 0.5)。
    static func total(
        dimensions: AestheticScoreDimensions,
        weights: AestheticScoreWeights
    ) -> Int {
        // 权重被全部拉到 0 时退回等权，而不是除以 0，也不是把所有照片都显示成 0 分。
        let effectiveWeights = weights.isDegenerate ? AestheticScoreWeights.balanced : weights
        let weightSum = effectiveWeights.values.reduce(0, +)
        let weightedSum = zip(dimensions.scores, effectiveWeights.values)
            .reduce(0) { $0 + $1.0 * $1.1 }
        return (2 * weightedSum + weightSum) / (2 * weightSum)
    }
}

enum AestheticScoreWeightsStore {
    private static let weightsKey = "aesthetic-score-weights-v1"

    static func load(defaults: UserDefaults = .standard) -> AestheticScoreWeights {
        guard let data = defaults.data(forKey: weightsKey),
              let weights = try? JSONDecoder().decode(AestheticScoreWeights.self, from: data) else {
            return .balanced
        }
        return weights
    }

    static func save(
        _ weights: AestheticScoreWeights,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(weights) else { return }
        defaults.set(data, forKey: weightsKey)
    }
}
