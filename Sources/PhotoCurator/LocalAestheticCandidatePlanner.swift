import Foundation

/// 本地漏斗为 AI评分准备待评分池。它只保存运行时照片 ID，不改变人工决定，也不读取或上传图片。
struct LocalAestheticCandidatePlan: Equatable {
    let localPhotoIDs: [String]
    let totalPhotoCount: Int
    let eligiblePhotoCount: Int
    let remainingSelectionCount: Int
    let requestedCandidateCount: Int
    let groupedRepresentativeCount: Int
    let standaloneEligibleCount: Int
    let standaloneSelectedCount: Int
    let collapsedSiblingCount: Int
    let excludedByLockedKeeperCount: Int

    var candidateCount: Int {
        localPhotoIDs.count
    }

    var localPhotoIDSet: Set<String> {
        Set(localPhotoIDs)
    }
}

/// 将大照片集压缩成一个有时间跨度的本地待评分池。
///
/// 规则：
/// - 人工保留项不需要再次竞争，人工淘汰项不会进入待评分池；
/// - 候选规模按剩余目标的 2–3 倍弹性收敛，上限随目标数量增长（默认目标下仍是 48 张），不为凑满 4 倍加入弱候选；
/// - 优先纳入画面相似照片中的本地技术优等生；
/// - 空余名额从时间线上补齐，避免候选只集中在旅途的某一个片段。
enum LocalAestheticCandidatePlanner {
    static let maximumCandidateCount = 48
    /// 目标数量很大时，固定 48 的上限会让 AI 永远凑不满目标。
    /// 因此上限随剩余目标线性放宽，同时保留一个总量封顶避免请求数失控。
    static let absoluteMaximumCandidateCount = 240
    static let minimumCandidateMultiplier = 2
    static let preferredCandidateMultiplier = 3

    static func candidateCapacity(remainingSelectionCount: Int) -> Int {
        min(
            absoluteMaximumCandidateCount,
            max(
                maximumCandidateCount,
                remainingSelectionCount * preferredCandidateMultiplier
            )
        )
    }

    static func makePlan(
        for photos: [PhotoItem],
        targetSelectionCount: Int
    ) -> LocalAestheticCandidatePlan {
        let keepCount = photos.filter { $0.decision == .keep }.count
        let remainingSelectionCount = max(0, targetSelectionCount - keepCount)
        let rawEligible = photos
            .filter { $0.decision == .undecided }
            .sorted(by: chronologicalOrder)
        // 清晰度是相对量：以候选池自身的中位数为参考，避免用固定刻度把整批低细节场景一起压低。
        let referenceSharpness = TechnicalQualityAnalyzer.referenceSharpness(
            in: rawEligible.compactMap { $0.technicalQuality?.sharpness }
        ) ?? 0

        guard remainingSelectionCount > 0, !rawEligible.isEmpty else {
            return LocalAestheticCandidatePlan(
                localPhotoIDs: [],
                totalPhotoCount: photos.count,
                eligiblePhotoCount: rawEligible.count,
                remainingSelectionCount: remainingSelectionCount,
                requestedCandidateCount: 0,
                groupedRepresentativeCount: 0,
                standaloneEligibleCount: 0,
                standaloneSelectedCount: 0,
                collapsedSiblingCount: 0,
                excludedByLockedKeeperCount: 0
            )
        }

        let familyIndex = CandidateFamilyIndex(photos: photos)
        let lockedFamilyIDs = Set(photos.compactMap { photo in
            photo.decision == .keep ? familyIndex.familyID(for: photo.id) : nil
        })
        let eligible = rawEligible.filter { photo in
            guard let familyID = familyIndex.familyID(for: photo.id) else { return true }
            return !lockedFamilyIDs.contains(familyID)
        }
        let excludedByLockedKeeperCount = rawEligible.count - eligible.count

        let groupedByFamily = Dictionary(grouping: eligible.compactMap { photo -> (String, PhotoItem)? in
            guard let familyID = familyIndex.familyID(for: photo.id) else { return nil }
            return (familyID, photo)
        }, by: { $0.0 })
        let groupedRepresentatives = groupedByFamily.values.compactMap { members in
            members.map(\.1).max { lhs, rhs in
                let lhsPriority = localPriority(for: lhs, referenceSharpness: referenceSharpness)
                let rhsPriority = localPriority(for: rhs, referenceSharpness: referenceSharpness)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return chronologicalOrder(lhs, rhs)
            }
        }.sorted(by: chronologicalOrder)
        let standalone = eligible.filter { familyIndex.familyID(for: $0.id) == nil }
        let collapsedEligible = (groupedRepresentatives + standalone).sorted(by: chronologicalOrder)
        let collapsedSiblingCount = max(0, eligible.count - collapsedEligible.count)

        guard !collapsedEligible.isEmpty else {
            return LocalAestheticCandidatePlan(
                localPhotoIDs: [],
                totalPhotoCount: photos.count,
                eligiblePhotoCount: rawEligible.count,
                remainingSelectionCount: remainingSelectionCount,
                requestedCandidateCount: 0,
                groupedRepresentativeCount: groupedRepresentatives.count,
                standaloneEligibleCount: standalone.count,
                standaloneSelectedCount: 0,
                collapsedSiblingCount: collapsedSiblingCount,
                excludedByLockedKeeperCount: excludedByLockedKeeperCount
            )
        }

        let minimumComparisonCount = min(
            collapsedEligible.count,
            remainingSelectionCount * minimumCandidateMultiplier
        )
        let preferredUpperBound = min(
            collapsedEligible.count,
            remainingSelectionCount * preferredCandidateMultiplier
        )
        let strongCandidateCount = collapsedEligible.filter(isStrongCandidate).count
        let desiredCount = max(
            minimumComparisonCount,
            min(preferredUpperBound, strongCandidateCount)
        )
        let requestedCandidateCount = min(
            collapsedEligible.count,
            candidateCapacity(remainingSelectionCount: remainingSelectionCount),
            remainingSelectionCount * AIReviewConfiguration.candidatePoolMultiplier,
            desiredCount
        )

        var selectedIDs = Set<String>()

        var groupedQuota = 0
        var standaloneQuota = 0
        if groupedRepresentatives.isEmpty {
            standaloneQuota = requestedCandidateCount
        } else if standalone.isEmpty {
            groupedQuota = requestedCandidateCount
        } else if requestedCandidateCount == 1 {
            standaloneQuota = 1
        } else {
            let proportionalStandalone = Int(
                (Double(requestedCandidateCount) * Double(standalone.count) / Double(collapsedEligible.count)).rounded()
            )
            standaloneQuota = min(standalone.count, max(1, proportionalStandalone))
            groupedQuota = min(groupedRepresentatives.count, max(1, requestedCandidateCount - standaloneQuota))

            while groupedQuota + standaloneQuota < requestedCandidateCount {
                if standaloneQuota < standalone.count {
                    standaloneQuota += 1
                } else if groupedQuota < groupedRepresentatives.count {
                    groupedQuota += 1
                } else {
                    break
                }
            }
        }

        selectedIDs.formUnion(
            preferredDiverseSelection(
                from: groupedRepresentatives,
                count: groupedQuota,
                referenceSharpness: referenceSharpness
            ).map(\.id)
        )
        selectedIDs.formUnion(
            preferredDiverseSelection(
                from: standalone,
                count: standaloneQuota,
                referenceSharpness: referenceSharpness
            ).map(\.id)
        )

        let chronologicalIndex = Dictionary(
            uniqueKeysWithValues: collapsedEligible.enumerated().map { ($0.element.id, $0.offset) }
        )
        while selectedIDs.count < requestedCandidateCount {
            let remaining = collapsedEligible.filter { !selectedIDs.contains($0.id) }
            guard let next = remaining.max(by: { lhs, rhs in
                candidateFillPriority(
                    for: lhs,
                    selectedIDs: selectedIDs,
                    chronologicalIndex: chronologicalIndex,
                    referenceSharpness: referenceSharpness
                ) < candidateFillPriority(
                    for: rhs,
                    selectedIDs: selectedIDs,
                    chronologicalIndex: chronologicalIndex,
                    referenceSharpness: referenceSharpness
                )
            }) else {
                break
            }
            selectedIDs.insert(next.id)
        }

        let selectedPhotoIDs = collapsedEligible
            .filter { selectedIDs.contains($0.id) }
            .map(\.id)
        let standaloneIDs = Set(standalone.map(\.id))
        return LocalAestheticCandidatePlan(
            localPhotoIDs: selectedPhotoIDs,
            totalPhotoCount: photos.count,
            eligiblePhotoCount: rawEligible.count,
            remainingSelectionCount: remainingSelectionCount,
            requestedCandidateCount: requestedCandidateCount,
            groupedRepresentativeCount: groupedRepresentatives.count,
            standaloneEligibleCount: standalone.count,
            standaloneSelectedCount: selectedPhotoIDs.filter(standaloneIDs.contains).count,
            collapsedSiblingCount: collapsedSiblingCount,
            excludedByLockedKeeperCount: excludedByLockedKeeperCount
        )
    }

    private static func preferredDiverseSelection(
        from photos: [PhotoItem],
        count: Int,
        referenceSharpness: Double
    ) -> [PhotoItem] {
        guard count > 0, !photos.isEmpty else { return [] }
        let preferred = photos.filter { $0.localRecommendations.contains(where: \.isTopCandidate) }
        if preferred.count >= count {
            return diverseSegmentSelection(
                from: preferred,
                count: count,
                referenceSharpness: referenceSharpness
            )
        }
        let remainingCount = count - preferred.count
        let remaining = photos.filter { photo in !preferred.contains(where: { $0.id == photo.id }) }
        return (preferred + diverseSegmentSelection(
            from: remaining,
            count: remainingCount,
            referenceSharpness: referenceSharpness
        ))
            .sorted(by: chronologicalOrder)
    }

    /// 当本地组冠军多于容量时，按时间线分段，并在每段内选择技术优先级最高的一张。
    private static func diverseSegmentSelection(
        from photos: [PhotoItem],
        count: Int,
        referenceSharpness: Double
    ) -> [PhotoItem] {
        guard count > 0, photos.count > count else { return Array(photos.prefix(count)) }
        return (0..<count).compactMap { segment in
            let start = segment * photos.count / count
            let end = (segment + 1) * photos.count / count
            guard start < end else { return nil }
            return photos[start..<end].max { lhs, rhs in
                localPriority(for: lhs, referenceSharpness: referenceSharpness)
                    < localPriority(for: rhs, referenceSharpness: referenceSharpness)
            }
        }
    }

    private static func candidateFillPriority(
        for photo: PhotoItem,
        selectedIDs: Set<String>,
        chronologicalIndex: [String: Int],
        referenceSharpness: Double
    ) -> (Int, Double, String) {
        let index = chronologicalIndex[photo.id] ?? 0
        let temporalDistance = selectedIDs
            .compactMap { chronologicalIndex[$0] }
            .map { abs($0 - index) }
            .min() ?? Int.max
        return (
            temporalDistance,
            localPriority(for: photo, referenceSharpness: referenceSharpness),
            photo.id
        )
    }

    private static func localPriority(
        for photo: PhotoItem,
        referenceSharpness: Double
    ) -> Double {
        let localWinnerCount = photo.localRecommendations.filter(\.isTopCandidate).count
        guard let quality = photo.technicalQuality else {
            return Double(localWinnerCount) * 10
        }
        let sharpness = referenceSharpness > 0
            ? min(quality.sharpness / referenceSharpness, 1) * 0.40
            : 0
        let range = Double(quality.dynamicRange) / 255 * 0.25
        let clipping = max(
            0,
            1 - min(1, quality.shadowClippingRatio + quality.highlightClippingRatio)
        ) * 0.25
        let riskBonus = quality.risks.isEmpty ? 0.10 : 0
        return Double(localWinnerCount) * 10 + sharpness + range + clipping + riskBonus
    }

    private static func isStrongCandidate(_ photo: PhotoItem) -> Bool {
        if photo.localRecommendations.contains(where: \.isTopCandidate) {
            return true
        }
        guard let quality = photo.technicalQuality else { return false }
        return quality.risks.isEmpty
    }

    private static func chronologicalOrder(_ lhs: PhotoItem, _ rhs: PhotoItem) -> Bool {
        let leftDate = lhs.captureDate ?? .distantFuture
        let rightDate = rhs.captureDate ?? .distantFuture
        if leftDate != rightDate { return leftDate < rightDate }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }
}
