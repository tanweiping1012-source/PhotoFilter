import Foundation

/// 只根据画面相似集合建立候选家族。拍摄时间本身不能形成家族。
/// 家族只约束候选与最终结果，绝不改变人工决定。
struct CandidateFamilyIndex: Equatable {
    private(set) var familyIDByPhotoID: [String: String] = [:]
    private(set) var membersByFamilyID: [String: [String]] = [:]

    init(photos: [PhotoItem]) {
        guard photos.count > 1 else { return }

        var disjointSet = CandidateFamilyDisjointSet(count: photos.count)
        var firstIndexByGroupKey: [String: Int] = [:]

        for (index, photo) in photos.enumerated() {
            guard let group = photo.similarityGroup else { continue }
            let groupKey = "similarity:\(group.id)"
            if let firstIndex = firstIndexByGroupKey[groupKey] {
                disjointSet.union(index, firstIndex)
            } else {
                firstIndexByGroupKey[groupKey] = index
            }
        }

        var indicesByRoot: [Int: [Int]] = [:]
        for index in photos.indices {
            guard photos[index].similarityGroup != nil else { continue }
            indicesByRoot[disjointSet.find(index), default: []].append(index)
        }

        let families = indicesByRoot.values
            .filter { $0.count > 1 }
            .sorted {
                let lhs = $0.map { photos[$0].id }.min() ?? ""
                let rhs = $1.map { photos[$0].id }.min() ?? ""
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        for (offset, indices) in families.enumerated() {
            let familyID = "candidate-family-\(offset + 1)"
            let memberIDs = indices.map { photos[$0].id }.sorted()
            membersByFamilyID[familyID] = memberIDs
            for photoID in memberIDs {
                familyIDByPhotoID[photoID] = familyID
            }
        }
    }

    func familyID(for photoID: String) -> String? {
        familyIDByPhotoID[photoID]
    }

    func conflicts(in photoIDs: Set<String>) -> [[String]] {
        membersByFamilyID.values
            .map { $0.filter(photoIDs.contains) }
            .filter { $0.count > 1 }
            .sorted { ($0.first ?? "") < ($1.first ?? "") }
    }
}

private struct CandidateFamilyDisjointSet {
    private var parents: [Int]
    private var ranks: [Int]

    init(count: Int) {
        parents = Array(0..<count)
        ranks = Array(repeating: 0, count: count)
    }

    mutating func find(_ index: Int) -> Int {
        guard parents[index] != index else { return index }
        let root = find(parents[index])
        parents[index] = root
        return root
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let lhsRoot = find(lhs)
        let rhsRoot = find(rhs)
        guard lhsRoot != rhsRoot else { return }

        if ranks[lhsRoot] < ranks[rhsRoot] {
            parents[lhsRoot] = rhsRoot
        } else if ranks[lhsRoot] > ranks[rhsRoot] {
            parents[rhsRoot] = lhsRoot
        } else {
            parents[rhsRoot] = lhsRoot
            ranks[lhsRoot] += 1
        }
    }
}
