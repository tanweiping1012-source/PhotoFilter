import Foundation

enum PhotoGridFilter: String, CaseIterable, Identifiable {
    case all
    case aiCandidates
    case aiScored
    case aiSelected
    case keep
    case reject
    case undecided

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "全部照片")
        case .aiCandidates: String(localized: "待AI评分")
        case .aiScored: String(localized: "已AI评分")
        case .aiSelected: String(localized: "评分优先")
        case .keep: String(localized: "保留")
        case .reject: String(localized: "淘汰")
        case .undecided: String(localized: "待定")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "photo.stack"
        case .aiCandidates: "line.3.horizontal.decrease.circle.fill"
        case .aiScored: "chart.bar.xaxis"
        case .aiSelected: "wand.and.stars.inverse"
        case .keep: "checkmark.circle.fill"
        case .reject: "xmark.circle.fill"
        case .undecided: "circle"
        }
    }

    func photos(
        from photos: [PhotoItem],
        localAICandidateIDs: Set<String>,
        aiFinalSelectionIDs: Set<String> = []
    ) -> [PhotoItem] {
        switch self {
        case .all:
            photos
        case .aiCandidates:
            photos.filter { localAICandidateIDs.contains($0.id) }
        case .aiScored:
            scoreOrdered(
                photos.filter { !$0.aestheticRecommendations.isEmpty }
            )
        case .aiSelected:
            scoreOrdered(
                photos.filter { aiFinalSelectionIDs.contains($0.id) }
            )
        case .keep:
            photos.filter { $0.decision == .keep }
        case .reject:
            photos.filter { $0.decision == .reject }
        case .undecided:
            photos.filter { $0.decision == .undecided }
        }
    }

    private func scoreOrdered(_ photos: [PhotoItem]) -> [PhotoItem] {
        photos.sorted { lhs, rhs in
            guard let lhsScore = lhs.primaryAestheticRecommendation else {
                return false
            }
            guard let rhsScore = rhs.primaryAestheticRecommendation else {
                return true
            }
            return AestheticScoreRanking.precedes(
                lhsScore,
                photoID: lhs.id,
                rhsScore,
                photoID: rhs.id
            )
        }
    }
}
