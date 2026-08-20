import Foundation

/// 只根据本地清晰度、反差和极端曝光风险，给每批相似照片排出优先查看顺序。
/// 它不评价构图、情绪或人物状态，不能替代后续的视觉 AI / 人工审美选择。
enum LocalCandidateRanker {
    static func assigningRecommendations(to photos: [PhotoItem]) -> [PhotoItem] {
        var updatedPhotos = photos
        for index in updatedPhotos.indices {
            updatedPhotos[index].localRecommendations = []
        }

        assignRecommendations(kind: .similarity, to: &updatedPhotos) { photo in
            guard let group = photo.similarityGroup else { return nil }
            return (id: group.id, position: group.position, count: group.count)
        }
        return updatedPhotos
    }

    private static func assignRecommendations(
        kind: CandidateGroupKind,
        to photos: inout [PhotoItem],
        membership: (PhotoItem) -> (id: String, position: Int, count: Int)?
    ) {
        var indicesByGroup: [String: [Int]] = [:]
        for index in photos.indices {
            guard let group = membership(photos[index]) else { continue }
            indicesByGroup[group.id, default: []].append(index)
        }

        for (groupID, indices) in indicesByGroup where indices.count > 1 {
            // 清晰度只在家族内部比较：家族里最锐的一张作为参考值。
            let reference = indices
                .compactMap { photos[$0].technicalQuality?.sharpness }
                .max() ?? 0
            let ranked = indices.sorted { lhs, rhs in
                let lhsScore = technicalScore(for: photos[lhs], referenceSharpness: reference)
                let rhsScore = technicalScore(for: photos[rhs], referenceSharpness: reference)
                if lhsScore != rhsScore { return lhsScore > rhsScore }

                let lhsDate = photos[lhs].captureDate ?? .distantFuture
                let rhsDate = photos[rhs].captureDate ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return photos[lhs].filename.localizedStandardCompare(photos[rhs].filename) == .orderedAscending
            }

            for (offset, photoIndex) in ranked.enumerated() {
                let photo = photos[photoIndex]
                let recommendation = GroupRecommendation(
                    kind: kind,
                    groupID: groupID,
                    rank: offset + 1,
                    groupSize: ranked.count,
                    explanation: explanation(for: photo)
                )
                photos[photoIndex].localRecommendations.append(recommendation)
            }
        }
    }

    static func technicalScore(
        for photo: PhotoItem,
        referenceSharpness: Double
    ) -> Double {
        guard let quality = photo.technicalQuality else { return 0 }
        let sharpness = referenceSharpness > 0
            ? min(quality.sharpness / referenceSharpness, 1) * 0.40
            : 0
        let range = Double(quality.dynamicRange) / 255 * 0.25
        let clipping = max(0, 1 - min(1, quality.shadowClippingRatio + quality.highlightClippingRatio)) * 0.25
        let riskBonus = quality.risks.isEmpty ? 0.10 : 0
        return sharpness + range + clipping + riskBonus
    }

    private static func explanation(for photo: PhotoItem) -> String {
        guard let quality = photo.technicalQuality else {
            return String(localized: "缺少本地技术分析，按拍摄顺序显示")
        }
        guard quality.risks.isEmpty else {
            let risks = quality.risks.map(\.title).formatted(.list(type: .and))
            return String(localized: "存在\(risks)，排在技术更稳妥的候选之后")
        }
        return String(localized: "本地清晰度、反差与曝光风险相对更稳妥")
    }
}
