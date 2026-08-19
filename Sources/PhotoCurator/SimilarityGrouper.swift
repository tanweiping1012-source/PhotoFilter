import Foundation

enum SimilarityGrouper {
    /// 利用 64 位灰度感知哈希识别画面相似照片。
    /// 严格视觉相似不依赖时间；时间只允许中等视觉相似使用更宽松的阈值。
    /// 为避免单色或过曝画面误合并，低对比度图片不自动分组。
    static func assigningGroups(
        to photos: [PhotoItem],
        maximumHammingDistance: Int = 4,
        maximumAverageLuminanceDelta: Int = 40,
        maximumSceneHammingDistance: Int = 14,
        maximumSceneLuminanceDelta: Int = 55,
        maximumSceneTimeInterval: TimeInterval = 120,
        minimumDynamicRange: UInt8 = 12
    ) -> [PhotoItem] {
        var groupedPhotos = photos
        for index in groupedPhotos.indices {
            groupedPhotos[index].similarityGroup = nil
        }

        let hashableIndices = groupedPhotos.indices.filter {
            guard let hash = groupedPhotos[$0].perceptualHash else { return false }
            return hash.dynamicRange >= minimumDynamicRange
        }
        guard hashableIndices.count > 1 else { return groupedPhotos }

        struct Cluster {
            let representativeIndex: Int
            var memberIndices: [Int]
        }

        var clusters: [Cluster] = []

        for photoIndex in hashableIndices {
            guard let hash = groupedPhotos[photoIndex].perceptualHash else { continue }

            // 图库规模通常只有几百到几千张。直接比较所有簇代表能避免 LSH 分带在
            // 少量差异分散到多个 band 时漏掉真正近重复照片。
            let bestClusterID = clusters.indices.compactMap { clusterID -> (Int, Int)? in
                let representativeIndex = clusters[clusterID].representativeIndex
                guard let candidateHash = groupedPhotos[representativeIndex].perceptualHash else {
                    return nil
                }
                let isStrictNearDuplicate = hash.isNearDuplicate(
                        of: candidateHash,
                        maximumHammingDistance: maximumHammingDistance,
                        maximumAverageLuminanceDelta: maximumAverageLuminanceDelta
                    )
                let isTemporallyCloseScene = sameSceneWithinTimeWindow(
                    groupedPhotos[photoIndex],
                    groupedPhotos[representativeIndex],
                    maximumTimeInterval: maximumSceneTimeInterval
                ) && hash.isNearDuplicate(
                    of: candidateHash,
                    maximumHammingDistance: maximumSceneHammingDistance,
                    maximumAverageLuminanceDelta: maximumSceneLuminanceDelta
                )
                guard isStrictNearDuplicate || isTemporallyCloseScene else {
                    return nil
                }
                return (clusterID, hash.hammingDistance(to: candidateHash))
            }.min { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }

            if let bestClusterID {
                clusters[bestClusterID.0].memberIndices.append(photoIndex)
            } else {
                clusters.append(Cluster(representativeIndex: photoIndex, memberIndices: [photoIndex]))
            }
        }

        let groups = clusters.map(\.memberIndices)
            .filter { $0.count > 1 }
            .sorted { ($0.min() ?? .max) < ($1.min() ?? .max) }

        for (groupOffset, indices) in groups.enumerated() {
            let orderedIndices = indices.sorted()
            let groupID = "similar-\(groupOffset + 1)"
            for (position, photoIndex) in orderedIndices.enumerated() {
                groupedPhotos[photoIndex].similarityGroup = SimilarityGroupMembership(
                    id: groupID,
                    position: position + 1,
                    count: orderedIndices.count
                )
            }
        }

        return groupedPhotos
    }

    static func groupCount(in photos: [PhotoItem]) -> Int {
        Set(photos.compactMap { $0.similarityGroup?.id }).count
    }

    static func groupedPhotoCount(in photos: [PhotoItem]) -> Int {
        photos.filter { $0.similarityGroup != nil }.count
    }

    private static func sameSceneWithinTimeWindow(
        _ lhs: PhotoItem,
        _ rhs: PhotoItem,
        maximumTimeInterval: TimeInterval
    ) -> Bool {
        guard let lhsDate = lhs.captureDate, let rhsDate = rhs.captureDate else { return false }
        return abs(lhsDate.timeIntervalSince(rhsDate)) <= maximumTimeInterval
    }
}
