import Foundation

struct DemoModeSession {
    let resourceDirectory: URL
    let startingPhotos: [PhotoItem]
    let photos: [PhotoItem]
    let selectionTargets: PhotoSelectionTargets
    let rankedPhotoIDsByCategory:
        [PhotoCurationCategory: [String]]
    let finalSelectionPhotoIDsByCategory:
        [PhotoCurationCategory: Set<String>]
    let scoreScopes: [AestheticReviewScope]
    let runProgress: AIFinalSelectionRunProgress

    var rankedPhotoIDs: [String] {
        PhotoCurationCategory.allCases.flatMap {
            rankedPhotoIDsByCategory[$0] ?? []
        }
    }

    var finalSelectionPhotoIDs: Set<String> {
        finalSelectionPhotoIDsByCategory.values.reduce(into: []) {
            $0.formUnion($1)
        }
    }
}

enum DemoModeError: LocalizedError, Equatable {
    case resourcesUnavailable
    case incompleteFixture

    var errorDescription: String? {
        switch self {
        case .resourcesUnavailable:
            String(localized: "内置样例资源不可用。")
        case .incompleteFixture:
            String(localized: "内置样例结果不完整。")
        }
    }
}

enum DemoModeLibrary {
    static let projectID = UUID(uuidString: "50484F54-4F43-5552-4154-4F5244454D4F")!
    static let selectionTargets = PhotoSelectionTargets(
        people: 2,
        scenery: 2
    )
    static let targetSelectionCount = selectionTargets.total
    static let filenames = [
        "demo-01-coastal-road.jpg",
        "demo-02-lighthouse.jpg",
        "demo-03-forest-trail.jpg",
        "demo-04-harbor.jpg",
        "demo-05-ocean-overlook.jpg",
        "demo-06-hillside-village.jpg",
        "demo-07-mountain-lake.jpg",
        "demo-08-sunset-beach.jpg",
    ]

    static func resourceDirectory(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("DemoPhotos", isDirectory: true),
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Resources/DemoPhotos", isDirectory: true),
        ].compactMap { $0 }

        return candidates.first { directory in
            filenames.allSatisfy {
                fileManager.fileExists(
                    atPath: directory.appendingPathComponent($0, isDirectory: false).path
                )
            }
        }
    }

    static func makeSession(
        resourceDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> DemoModeSession {
        let urls = filenames.map {
            resourceDirectory.appendingPathComponent($0, isDirectory: false)
        }
        guard urls.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw DemoModeError.resourcesUnavailable
        }

        let firstCaptureDate = Date(timeIntervalSince1970: 1_720_000_000)
        let startingPhotos = urls.enumerated().map { index, url in
            PhotoItem(
                url: url,
                captureDate: firstCaptureDate.addingTimeInterval(
                    TimeInterval(index * 1_800)
                ),
                curationCategory: index < 4 ? .people : .scenery
            )
        }
        let plansByCategory = try Dictionary(
            uniqueKeysWithValues:
                PhotoCurationCategory.allCases.map { category in
                    let categoryPhotoIDs = startingPhotos.filter {
                        $0.curationCategory == category
                    }.map(\.id)
                    return (
                        category,
                        try AIFinalSelectionRunPlanner.makePlan(
                            candidateLocalPhotoIDs:
                                categoryPhotoIDs,
                            targetWinnerCount:
                                selectionTargets[category],
                            category: category
                        )
                    )
                }
        )
        let plans = PhotoCurationCategory.allCases.compactMap {
            plansByCategory[$0]
        }
        guard plans.allSatisfy({ !$0.groups.isEmpty }) else {
            throw DemoModeError.incompleteFixture
        }

        let scores = [92, 80, 78, 90, 88, 76, 82, 86]
        var photos = startingPhotos
        let groups = plans.flatMap(\.groups)
        for (groupIndex, group) in groups.enumerated() {
            let request = AestheticReviewRequestBuilder.make(
                scope: group.scope,
                localPhotoIDs: group.localPhotoIDs,
                requestID: String(format: "demo-request-%03d", groupIndex + 1)
            )
            let response = AestheticReviewResponse(
                version: AestheticReviewContract.version,
                requestID: request.requestID,
                scope: request.scope,
                reviews: request.photos.enumerated().map { offset, input in
                    let photoID = group.localPhotoIDs[offset]
                    guard let photoIndex = startingPhotos.firstIndex(
                        where: { $0.id == photoID }
                    ) else {
                        preconditionFailure("Demo plan contains an unknown photo")
                    }
                    let score = scores[photoIndex]
                    return AestheticReviewEntry(
                        photoID: input.photoID,
                        score: score,
                        dimensions: AestheticScoreDimensions(
                            moment: min(100, score + 2),
                            composition: max(0, score - 1),
                            subject: min(100, score + 1),
                            lighting: max(0, score - 2),
                            storytelling: score
                        ),
                        reasons: score >= 85
                            ? [
                                String(localized: "主体清楚，层次关系完整"),
                                String(localized: "瞬间与旅途节奏自然"),
                            ]
                            : [
                                String(localized: "构图稳定，画面信息清楚"),
                                String(localized: "叙事表达仍可加强"),
                            ],
                        summary: score >= 85
                            ? String(localized: "主体、层次和旅途氛围均衡，画面完成度高。")
                            : String(localized: "画面技术表现可用，但瞬间和叙事张力仍可加强。")
                    )
                }
            )
            photos = try AestheticReviewApplier.applying(
                response,
                for: request,
                localPhotoIDs: group.localPhotoIDs,
                to: photos
            )
        }

        var rankedPhotoIDsByCategory:
            [PhotoCurationCategory: [String]] = [:]
        var finalSelectionPhotoIDsByCategory:
            [PhotoCurationCategory: Set<String>] = [:]
        for category in PhotoCurationCategory.allCases {
            guard let plan = plansByCategory[category] else {
                throw DemoModeError.incompleteFixture
            }
            let scoredPhotos = photos.compactMap {
                photo -> AIFinalSelectionScore? in
                guard photo.curationCategory == category,
                      let recommendation =
                        photo.aestheticRecommendations.last(
                            where: {
                                $0.scope.kind == .finalSelection
                                    && $0.scope.category == category
                            }
                        ) else {
                    return nil
                }
                return AIFinalSelectionScore(
                    photoID: photo.id,
                    score: recommendation.score,
                    dimensions: recommendation.dimensions
                )
            }
            let rankedPhotoIDs =
                try AIFinalSelectionRunValidator
                    .rankedCandidatePhotoIDs(
                        scores: scoredPhotos,
                        candidatePhotoIDs: plan.coveredPhotoIDs
                    )
            rankedPhotoIDsByCategory[category] = rankedPhotoIDs
            finalSelectionPhotoIDsByCategory[category] =
                try AIFinalSelectionRunValidator
                    .finalSelectionIDs(
                        rankedCandidatePhotoIDs: rankedPhotoIDs,
                        lockedKeeperPhotoIDs: [],
                        candidatePhotoIDs: plan.coveredPhotoIDs,
                        targetSelectionCount:
                            selectionTargets[category]
                    )
        }
        guard finalSelectionPhotoIDsByCategory.values.reduce(
            0,
            { $0 + $1.count }
        ) == targetSelectionCount else {
            throw DemoModeError.incompleteFixture
        }

        return DemoModeSession(
            resourceDirectory: resourceDirectory,
            startingPhotos: startingPhotos,
            photos: photos,
            selectionTargets: selectionTargets,
            rankedPhotoIDsByCategory: rankedPhotoIDsByCategory,
            finalSelectionPhotoIDsByCategory:
                finalSelectionPhotoIDsByCategory,
            scoreScopes: groups.map(\.scope),
            runProgress: AIFinalSelectionRunProgress(
                phase: .completed,
                completedBatchCount: plans.reduce(0) {
                    $0 + $1.requestCount
                },
                totalBatchCount: plans.reduce(0) {
                    $0 + $1.requestCount
                },
                completedPhotoCount: plans.reduce(0) {
                    $0 + $1.candidatePhotoCount
                },
                candidatePhotoCount: plans.reduce(0) {
                    $0 + $1.candidatePhotoCount
                },
                targetWinnerCount: selectionTargets.total
            )
        )
    }
}
