import CoreVideo
import Foundation
import Vision

struct PeopleSubjectRegion: Equatable {
    let boundingBox: CGRect
    let confidence: Float

    var area: CGFloat {
        max(0, boundingBox.width) * max(0, boundingBox.height)
    }
}

struct PeopleFaceEvidence: Equatable {
    let boundingBox: CGRect
    let captureQuality: Float?
    let yawRadians: Double?

    var area: CGFloat {
        max(0, boundingBox.width) * max(0, boundingBox.height)
    }
}

struct PeopleSubjectEvidence: Equatable {
    var humanRegions: [PeopleSubjectRegion]
    var faces: [PeopleFaceEvidence]
    var personMaskCoverage: Double
    var personMaskBoundingBox: CGRect?
    var personInstanceCount: Int
    var salientRegions: [CGRect]

    init(
        humanRegions: [PeopleSubjectRegion] = [],
        faces: [PeopleFaceEvidence] = [],
        personMaskCoverage: Double = 0,
        personMaskBoundingBox: CGRect? = nil,
        personInstanceCount: Int = 0,
        salientRegions: [CGRect] = []
    ) {
        self.humanRegions = humanRegions
        self.faces = faces
        self.personMaskCoverage = personMaskCoverage
        self.personMaskBoundingBox = personMaskBoundingBox
        self.personInstanceCount = personInstanceCount
        self.salientRegions = salientRegions
    }
}

enum PeopleSubjectReason: Equatable {
    case clearPortrait
    case dominantPerson
    case personInLandscape
    case incidentalPeople
    case noPerson
}

struct PeopleSubjectClassification: Equatable {
    let category: PhotoCurationCategory
    let reason: PeopleSubjectReason
    let confidence: Double
}

enum PeopleSubjectEvaluator {
    private static let minimumFaceArea: CGFloat = 0.008
    private static let strongFaceArea: CGFloat = 0.018
    private static let minimumFaceQuality: Float = 0.25
    private static let minimumFaceDominance: CGFloat = 0.42
    private static let maximumFaceYaw = 1.45

    private static let dominantHumanArea: CGFloat = 0.10
    private static let minimumHumanConfidence: Float = 0.55
    private static let minimumHumanDominance: CGFloat = 0.52

    private static let minimumLandscapePersonArea: CGFloat = 0.018
    private static let minimumMaskCoverage = 0.006
    private static let minimumPersonSaliencyCoverage: CGFloat = 0.50
    private static let minimumSalientRegionConcentration: CGFloat = 0.10
    private static let maximumLandscapePeopleCount = 3
    private static let minimumSilhouetteAspectRatio: CGFloat = 1.35

    static func classify(
        _ evidence: PeopleSubjectEvidence
    ) -> PeopleSubjectClassification {
        let humans = evidence.humanRegions
            .filter { $0.confidence >= minimumHumanConfidence }
            .sorted { $0.area > $1.area }
        let faces = evidence.faces.sorted { $0.area > $1.area }

        if let face = faces.first,
           isClearPortrait(
               face,
               allFaces: faces,
               humans: humans
           ) {
            return PeopleSubjectClassification(
                category: .people,
                reason: .clearPortrait,
                confidence: confidence(
                    base: 0.72,
                    area: face.area,
                    quality: face.captureQuality
                )
            )
        }

        if let human = humans.first,
           human.area >= dominantHumanArea,
           dominance(of: human, among: humans)
                >= minimumHumanDominance,
           maskSupports(
               human.boundingBox,
               evidence: evidence
           ) {
            return PeopleSubjectClassification(
                category: .people,
                reason: .dominantPerson,
                confidence: min(
                    0.96,
                    0.68 + Double(human.area)
                )
            )
        }

        let effectiveHumans = effectiveHumanRegions(
            humans: humans,
            maskBoundingBox: evidence.personMaskBoundingBox
        )
        if let human = effectiveHumans.first,
           isPersonInLandscape(
               human,
               allHumans: effectiveHumans,
               evidence: evidence
           ) {
            return PeopleSubjectClassification(
                category: .people,
                reason: .personInLandscape,
                confidence: min(
                    0.90,
                    0.60
                        + evidence.personMaskCoverage
                        + Double(
                            saliencySupport(
                                human.boundingBox,
                                evidence.salientRegions
                            ).personCoverage
                        ) * 0.20
                )
            )
        }

        let hasPersonSignal = !humans.isEmpty
            || !faces.isEmpty
            || evidence.personMaskCoverage
                >= minimumMaskCoverage
        return PeopleSubjectClassification(
            category: .scenery,
            reason: hasPersonSignal
                ? .incidentalPeople
                : .noPerson,
            confidence: hasPersonSignal ? 0.72 : 0.92
        )
    }

    private static func isClearPortrait(
        _ face: PeopleFaceEvidence,
        allFaces: [PeopleFaceEvidence],
        humans: [PeopleSubjectRegion]
    ) -> Bool {
        guard face.area >= minimumFaceArea,
              abs(face.yawRadians ?? 0) <= maximumFaceYaw,
              dominance(of: face, among: allFaces)
                >= minimumFaceDominance else {
            return false
        }

        let qualityIsUsable =
            face.captureQuality.map {
                $0 >= minimumFaceQuality
            } ?? true
        if face.area >= strongFaceArea {
            return qualityIsUsable
                || face.captureQuality == nil
        }
        guard qualityIsUsable else { return false }

        return humans.contains { human in
            human.area >= 0.05
                && human.boundingBox
                    .insetBy(dx: -0.03, dy: -0.03)
                    .intersects(face.boundingBox)
        }
    }

    private static func isPersonInLandscape(
        _ human: PeopleSubjectRegion,
        allHumans: [PeopleSubjectRegion],
        evidence: PeopleSubjectEvidence
    ) -> Bool {
        guard human.area >= minimumLandscapePersonArea,
              dominance(of: human, among: allHumans)
                >= minimumHumanDominance,
              max(
                  allHumans.count,
                  evidence.personInstanceCount
              ) <= maximumLandscapePeopleCount,
              maskSupports(
                  human.boundingBox,
                  evidence: evidence
              ),
              hasSaliencySupport(
                  human.boundingBox,
                  evidence.salientRegions
              ) else {
            return false
        }

        if evidence.humanRegions.isEmpty,
           !isPlausibleSegmentationOnlySilhouette(
               human.boundingBox,
               instanceCount: evidence.personInstanceCount
           ) {
            return false
        }

        let center = CGPoint(
            x: human.boundingBox.midX,
            y: human.boundingBox.midY
        )
        return (0.06...0.94).contains(center.x)
            && (0.05...0.95).contains(center.y)
    }

    private static func effectiveHumanRegions(
        humans: [PeopleSubjectRegion],
        maskBoundingBox: CGRect?
    ) -> [PeopleSubjectRegion] {
        guard humans.isEmpty,
              let maskBoundingBox,
              maskBoundingBox.width > 0,
              maskBoundingBox.height > 0 else {
            return humans
        }
        return [
            PeopleSubjectRegion(
                boundingBox: maskBoundingBox,
                confidence: 0.65
            ),
        ]
    }

    private static func dominance(
        of region: PeopleSubjectRegion,
        among regions: [PeopleSubjectRegion]
    ) -> CGFloat {
        let total = regions.reduce(0) { $0 + $1.area }
        guard total > 0 else { return 0 }
        return region.area / total
    }

    private static func dominance(
        of face: PeopleFaceEvidence,
        among faces: [PeopleFaceEvidence]
    ) -> CGFloat {
        let total = faces.reduce(0) { $0 + $1.area }
        guard total > 0 else { return 0 }
        return face.area / total
    }

    private static func maskSupports(
        _ person: CGRect,
        evidence: PeopleSubjectEvidence
    ) -> Bool {
        guard evidence.personMaskCoverage >= minimumMaskCoverage,
              let mask = evidence.personMaskBoundingBox else {
            return false
        }
        let intersection = person.intersection(mask)
        guard !intersection.isNull else { return false }
        let personArea = person.width * person.height
        let maskArea = mask.width * mask.height
        guard personArea > 0, maskArea > 0 else { return false }
        let intersectionArea =
            intersection.width * intersection.height
        return intersectionArea / min(personArea, maskArea)
            >= 0.20
    }

    private static func isPlausibleSegmentationOnlySilhouette(
        _ mask: CGRect,
        instanceCount: Int
    ) -> Bool {
        guard (1...maximumLandscapePeopleCount)
                .contains(instanceCount),
              mask.width > 0,
              mask.height / mask.width
                >= minimumSilhouetteAspectRatio else {
            return false
        }
        return mask.minX >= 0.04 && mask.maxX <= 0.96
    }

    private static func hasSaliencySupport(
        _ person: CGRect,
        _ salientRegions: [CGRect]
    ) -> Bool {
        let support = saliencySupport(
            person,
            salientRegions
        )
        return support.personCoverage
                >= minimumPersonSaliencyCoverage
            && support.salientConcentration
                >= minimumSalientRegionConcentration
    }

    private static func saliencySupport(
        _ person: CGRect,
        _ salientRegions: [CGRect]
    ) -> (
        personCoverage: CGFloat,
        salientConcentration: CGFloat
    ) {
        salientRegions.reduce(
            (personCoverage: 0, salientConcentration: 0)
        ) { best, salient in
            let intersection = person.intersection(salient)
            guard !intersection.isNull else { return best }
            let intersectionArea =
                intersection.width * intersection.height
            let personArea = person.width * person.height
            let salientArea = salient.width * salient.height
            guard personArea > 0, salientArea > 0 else {
                return best
            }
            let candidate = (
                personCoverage: intersectionArea / personArea,
                salientConcentration:
                    intersectionArea / salientArea
            )
            if candidate.personCoverage
                * candidate.salientConcentration
                > best.personCoverage
                    * best.salientConcentration {
                return candidate
            }
            return best
        }
    }

    private static func confidence(
        base: Double,
        area: CGFloat,
        quality: Float?
    ) -> Double {
        min(
            0.98,
            base
                + min(0.16, Double(area) * 2)
                + Double(quality ?? 0) * 0.10
        )
    }
}

enum PhotoCategoryClassifier {
    static func classify(_ url: URL) -> PhotoCurationCategory {
        classifyWithEvidence(url).category
    }

    static func diagnosticEvidence(
        _ url: URL
    ) throws -> PeopleSubjectEvidence {
        var evidence = try primaryEvidence(for: url)
        let mask = try personMaskEvidence(for: url)
        evidence.personMaskCoverage = mask.coverage
        evidence.personMaskBoundingBox = mask.boundingBox
        evidence.personInstanceCount = mask.instanceCount
        if mask.coverage >= 0.006 {
            evidence.salientRegions = try salientRegions(for: url)
        }
        return evidence
    }

    static func classifyWithEvidence(
        _ url: URL
    ) -> PeopleSubjectClassification {
        do {
            var evidence = try primaryEvidence(for: url)
            let primary = PeopleSubjectEvaluator.classify(evidence)
            if primary.category == .people {
                return primary
            }

            let mask = try personMaskEvidence(for: url)
            evidence.personMaskCoverage = mask.coverage
            evidence.personMaskBoundingBox = mask.boundingBox
            evidence.personInstanceCount = mask.instanceCount
            guard mask.coverage >= 0.006 else {
                return PeopleSubjectEvaluator.classify(evidence)
            }

            evidence.salientRegions = try salientRegions(for: url)
            return PeopleSubjectEvaluator.classify(evidence)
        } catch {
            return PeopleSubjectClassification(
                category: .scenery,
                reason: .noPerson,
                confidence: 0
            )
        }
    }

    private static func primaryEvidence(
        for url: URL
    ) throws -> PeopleSubjectEvidence {
        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = false
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        faceRequest.revision =
            VNDetectFaceCaptureQualityRequestRevision3

        try VNImageRequestHandler(url: url).perform(
            [humanRequest, faceRequest]
        )
        let humans = (humanRequest.results ?? []).map {
            PeopleSubjectRegion(
                boundingBox: $0.boundingBox,
                confidence: $0.confidence
            )
        }
        let faceObservations: [VNFaceObservation] =
            faceRequest.results ?? []
        let faces = faceObservations.map {
            PeopleFaceEvidence(
                boundingBox: $0.boundingBox,
                captureQuality: $0.faceCaptureQuality,
                yawRadians: $0.yaw?.doubleValue
            )
        }
        return PeopleSubjectEvidence(
            humanRegions: humans,
            faces: faces
        )
    }

    private static func personMaskEvidence(
        for url: URL
    ) throws -> (
        coverage: Double,
        boundingBox: CGRect?,
        instanceCount: Int
    ) {
        let segmentationRequest =
            VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .fast
        segmentationRequest.outputPixelFormat =
            kCVPixelFormatType_OneComponent8
        let instanceRequest =
            VNGeneratePersonInstanceMaskRequest()
        try VNImageRequestHandler(url: url).perform(
            [segmentationRequest, instanceRequest]
        )
        guard let buffer =
                segmentationRequest.results?.first?.pixelBuffer else {
            return (
                0,
                nil,
                instanceRequest.results?.first?
                    .allInstances.count ?? 0
            )
        }
        let statistics = maskStatistics(buffer)
        return (
            statistics.coverage,
            statistics.boundingBox,
            instanceRequest.results?.first?
                .allInstances.count ?? 0
        )
    }

    private static func salientRegions(
        for url: URL
    ) throws -> [CGRect] {
        let request =
            VNGenerateAttentionBasedSaliencyImageRequest()
        request.revision =
            VNGenerateAttentionBasedSaliencyImageRequestRevision2
        try VNImageRequestHandler(url: url).perform([request])
        return request.results?.first?.salientObjects?
            .map(\.boundingBox) ?? []
    }

    private static func maskStatistics(
        _ buffer: CVPixelBuffer
    ) -> (coverage: Double, boundingBox: CGRect?) {
        guard CVPixelBufferGetPixelFormatType(buffer)
                == kCVPixelFormatType_OneComponent8 else {
            return (0, nil)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        guard let baseAddress =
                CVPixelBufferGetBaseAddress(buffer) else {
            return (0, nil)
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return (0, nil) }

        let pixels = baseAddress.assumingMemoryBound(
            to: UInt8.self
        )
        var weightedForeground = 0.0
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            let row = pixels.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let value = row[x]
                weightedForeground += Double(value) / 255
                if value >= 64 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        let coverage = weightedForeground
            / Double(width * height)
        guard maxX >= minX, maxY >= minY else {
            return (coverage, nil)
        }
        let boundingBox = CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(height - 1 - maxY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1)
                / CGFloat(height)
        )
        return (coverage, boundingBox)
    }
}
