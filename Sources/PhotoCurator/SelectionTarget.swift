import Foundation

enum SelectionTargetStatus: Equatable {
    case needsMore(Int)
    case exact
    case tooMany(Int)

    var message: String {
        switch self {
        case .needsMore(let count): String(localized: "还需保留 \(count) 张")
        case .exact: String(localized: "已达到目标，可安全导出")
        case .tooMany(let count): String(localized: "需再淘汰 \(count) 张")
        }
    }

    var isExact: Bool {
        if case .exact = self { return true }
        return false
    }
}

enum SelectionTarget {
    static func status(keptCount: Int, targetCount: Int) -> SelectionTargetStatus {
        let target = max(targetCount, 0)
        if keptCount < target {
            return .needsMore(target - keptCount)
        }
        if keptCount > target {
            return .tooMany(keptCount - target)
        }
        return .exact
    }
}
