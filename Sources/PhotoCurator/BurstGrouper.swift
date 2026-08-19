import Foundation

enum BurstGrouper {
    /// 旧版时间分组实现，仅保留兼容测试；生产分析不再调用。
    /// 时间接近不能单独证明画面相似。
    static func assigningGroups(
        to photos: [PhotoItem],
        maximumGap: TimeInterval = 3
    ) -> [PhotoItem] {
        var groupedPhotos = photos
        for index in groupedPhotos.indices {
            groupedPhotos[index].burstGroup = nil
        }

        let datedIndices = groupedPhotos.indices
            .filter { groupedPhotos[$0].captureDate != nil }
            .sorted { lhs, rhs in
                let lhsPhoto = groupedPhotos[lhs]
                let rhsPhoto = groupedPhotos[rhs]
                guard let lhsDate = lhsPhoto.captureDate, let rhsDate = rhsPhoto.captureDate else {
                    return lhsPhoto.filename.localizedStandardCompare(rhsPhoto.filename) == .orderedAscending
                }
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhsPhoto.filename.localizedStandardCompare(rhsPhoto.filename) == .orderedAscending
            }

        var candidateIndices: [Int] = []
        var previousDate: Date?
        var groupNumber = 0

        func commitCandidateGroup() {
            guard candidateIndices.count > 1 else {
                candidateIndices.removeAll(keepingCapacity: true)
                return
            }

            groupNumber += 1
            let groupID = "burst-\(groupNumber)"
            for (offset, photoIndex) in candidateIndices.enumerated() {
                groupedPhotos[photoIndex].burstGroup = BurstGroupMembership(
                    id: groupID,
                    position: offset + 1,
                    count: candidateIndices.count
                )
            }
            candidateIndices.removeAll(keepingCapacity: true)
        }

        for index in datedIndices {
            guard let captureDate = groupedPhotos[index].captureDate else { continue }

            if let previousDate,
               captureDate.timeIntervalSince(previousDate) > maximumGap {
                commitCandidateGroup()
            }

            candidateIndices.append(index)
            previousDate = captureDate
        }
        commitCandidateGroup()

        return groupedPhotos
    }

    static func groupCount(in photos: [PhotoItem]) -> Int {
        Set(photos.compactMap { $0.burstGroup?.id }).count
    }

    static func groupedPhotoCount(in photos: [PhotoItem]) -> Int {
        photos.filter { $0.burstGroup != nil }.count
    }
}
