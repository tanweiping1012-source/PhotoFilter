import CoreVideo
import ImageIO
import Vision
import XCTest
@testable import PhotoCurator

/// 真实照片性能基准。默认跳过；只有显式提供照片目录时才运行：
///
///     PHOTO_BENCH_DIR=/path/to/photos PHOTO_BENCH_COUNT=24 swift test --filter Benchmark
///
/// 基准只读取照片并在内存中分析，不写入、移动或上传任何文件。
final class AnalysisPipelineBenchmarkTests: XCTestCase {
    private var photoURLs: [URL] = []

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["PHOTO_BENCH_DIR"] else {
            throw XCTSkip("未设置 PHOTO_BENCH_DIR，跳过真实照片基准。")
        }
        let count = environment["PHOTO_BENCH_COUNT"].flatMap(Int.init) ?? 24
        let supported: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif"]
        let all = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { supported.contains($0.pathExtension.lowercased()) }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        photoURLs = Array(all.prefix(count))
        try XCTSkipIf(photoURLs.isEmpty, "目录中没有受支持的图片。")
    }

    /// 修复前的调用序列：每张照片重新打开原图 3–5 次，Vision 按全分辨率分多次 perform。
    func testLegacySerialAnalysisThroughput() throws {
        let start = Date()
        for url in photoURLs {
            _ = LegacyAnalysisReference.analyze(url)
        }
        let total = Date().timeIntervalSince(start)
        print(
            """
            [BENCH legacy-serial] photos=\(photoURLs.count) \
            total=\(String(format: "%.2f", total))s \
            perPhoto=\(String(format: "%.3f", total / Double(photoURLs.count)))s
            """
        )
    }

    /// 修复后的流水线：一次解码 + 一个 Vision handler，先量单线程成本。
    func testPipelineSerialAnalysisThroughput() throws {
        let start = Date()
        for url in photoURLs {
            _ = PhotoAnalysisPipeline.analyze(url)
        }
        let total = Date().timeIntervalSince(start)
        print(
            """
            [BENCH pipeline-serial] photos=\(photoURLs.count) \
            total=\(String(format: "%.2f", total))s \
            perPhoto=\(String(format: "%.3f", total / Double(photoURLs.count)))s
            """
        )
    }

    /// 实际扫描路径：并行分析 + 分批回调。
    func testPipelineParallelAnalysisThroughput() async throws {
        let start = Date()
        let counter = ResultCounter()
        await PhotoAnalysisPipeline.analyze(urls: photoURLs, batchSize: 32) { results in
            await counter.add(results.count)
        }
        let total = Date().timeIntervalSince(start)
        let analyzed = await counter.total
        XCTAssertEqual(analyzed, photoURLs.count)
        print(
            """
            [BENCH pipeline-parallel] photos=\(photoURLs.count) \
            lanes=\(PhotoAnalysisPipeline.defaultLaneCount) \
            total=\(String(format: "%.2f", total))s \
            perPhoto=\(String(format: "%.3f", total / Double(photoURLs.count)))s
            """
        )
    }

    /// 打印真实照片的清晰度分布，用于校准“清晰度风险”的相对阈值。
    func testSharpnessDistributionOnRealPhotos() throws {
        let values = photoURLs.compactMap { PhotoAnalysisPipeline.analyze($0).technicalQuality?.sharpness }
        let sorted = values.sorted()
        guard let reference = TechnicalQualityAnalyzer.referenceSharpness(in: values) else {
            return XCTFail("没有得到清晰度数据")
        }
        let flagged = values.filter { $0 < reference * TechnicalQualityAnalyzer.lowSharpnessLibraryRatio }
        print(
            """
            [BENCH sharpness] photos=\(values.count) \
            min=\(String(format: "%.2f", sorted.first ?? 0)) \
            median=\(String(format: "%.2f", reference)) \
            max=\(String(format: "%.2f", sorted.last ?? 0)) \
            flaggedByLibraryReference=\(flagged.count)
            """
        )
    }

    /// 降采样到 1024px 后的人物/风景判断，是否仍与原始分辨率一致。
    func testDownscaledClassificationAgreesWithFullResolution() throws {
        var agreed = 0
        var disagreements: [String] = []
        for url in photoURLs {
            let downscaled = PhotoCategoryClassifier.classifyWithEvidence(url)
            let fullResolution = FullResolutionClassifierReference.classify(url)
            if downscaled.category == fullResolution {
                agreed += 1
            } else {
                disagreements.append("\(url.lastPathComponent): 1024px=\(downscaled.category.rawValue) 原图=\(fullResolution.rawValue)")
            }
        }
        let rate = Double(agreed) / Double(photoURLs.count)
        print("[BENCH classification-agreement] photos=\(photoURLs.count) agreement=\(String(format: "%.1f%%", rate * 100))")
        for line in disagreements.prefix(12) { print("  ↳ \(line)") }
        XCTAssertGreaterThan(rate, 0.85, "降采样后的分类与原图差异过大")
    }
}

private actor ResultCounter {
    private(set) var total = 0
    func add(_ count: Int) { total += count }
}

/// 只在基准里使用：按原始分辨率跑一遍 Vision，作为降采样结果的对照组。
private enum FullResolutionClassifierReference {
    static func classify(_ url: URL) -> PhotoCurationCategory {
        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = false
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        faceRequest.revision = VNDetectFaceCaptureQualityRequestRevision3
        let segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .fast
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let instanceRequest = VNGeneratePersonInstanceMaskRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        saliencyRequest.revision = VNGenerateAttentionBasedSaliencyImageRequestRevision2
        do {
            try VNImageRequestHandler(url: url).perform([
                humanRequest, faceRequest, segmentationRequest, instanceRequest, saliencyRequest,
            ])
        } catch {
            return .scenery
        }
        var evidence = PeopleSubjectEvidence(
            humanRegions: (humanRequest.results ?? []).map {
                PeopleSubjectRegion(boundingBox: $0.boundingBox, confidence: $0.confidence)
            },
            faces: (faceRequest.results ?? []).map {
                PeopleFaceEvidence(
                    boundingBox: $0.boundingBox,
                    captureQuality: $0.faceCaptureQuality,
                    yawRadians: $0.yaw?.doubleValue
                )
            }
        )
        evidence.personInstanceCount = instanceRequest.results?.first?.allInstances.count ?? 0
        evidence.salientRegions = saliencyRequest.results?.first?.salientObjects?.map(\.boundingBox) ?? []
        if let buffer = segmentationRequest.results?.first?.pixelBuffer {
            evidence.personMaskCoverage = MaskCoverageReference.coverage(buffer)
            evidence.personMaskBoundingBox = MaskCoverageReference.boundingBox(buffer)
        }
        return PeopleSubjectEvaluator.classify(evidence).category
    }
}

/// 对照组用的掩码统计，与生产实现保持同一口径。
private enum MaskCoverageReference {
    static func coverage(_ buffer: CVPixelBuffer) -> Double {
        statistics(buffer).coverage
    }

    static func boundingBox(_ buffer: CVPixelBuffer) -> CGRect? {
        statistics(buffer).boundingBox
    }

    private static func statistics(_ buffer: CVPixelBuffer) -> (coverage: Double, boundingBox: CGRect?) {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else {
            return (0, nil)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return (0, nil) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return (0, nil) }

        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        var weightedForeground = 0.0
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = pixels.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let value = row[x]
                weightedForeground += Double(value) / 255
                if value >= 64 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        let coverage = weightedForeground / Double(width * height)
        guard maxX >= minX, maxY >= minY else { return (coverage, nil) }
        return (
            coverage,
            CGRect(
                x: CGFloat(minX) / CGFloat(width),
                y: CGFloat(height - 1 - maxY) / CGFloat(height),
                width: CGFloat(maxX - minX + 1) / CGFloat(width),
                height: CGFloat(maxY - minY + 1) / CGFloat(height)
            )
        )
    }
}

/// 修复前流水线的忠实复刻，只在基准里用于同一轮、同一缓存状态下的对照。
private enum LegacyAnalysisReference {
    static func analyze(_ url: URL) -> PhotoCurationCategory {
        _ = legacyRaster(for: url)                       // 第 1 次打开原图：64px 灰度栅格
        _ = legacyCaptureDate(for: url)                  // 第 2 次打开原图：EXIF
        return legacyClassify(url)                       // 第 3–5 次打开原图：Vision
    }

    private static func legacyRaster(for url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func legacyCaptureDate(for url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        return (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap {
            PhotoMetadataReader.parseEXIFDate($0)
        }
    }

    private static func legacyClassify(_ url: URL) -> PhotoCurationCategory {
        do {
            let humanRequest = VNDetectHumanRectanglesRequest()
            humanRequest.upperBodyOnly = false
            let faceRequest = VNDetectFaceCaptureQualityRequest()
            faceRequest.revision = VNDetectFaceCaptureQualityRequestRevision3
            try VNImageRequestHandler(url: url).perform([humanRequest, faceRequest])
            var evidence = PeopleSubjectEvidence(
                humanRegions: (humanRequest.results ?? []).map {
                    PeopleSubjectRegion(boundingBox: $0.boundingBox, confidence: $0.confidence)
                },
                faces: (faceRequest.results ?? []).map {
                    PeopleFaceEvidence(
                        boundingBox: $0.boundingBox,
                        captureQuality: $0.faceCaptureQuality,
                        yawRadians: $0.yaw?.doubleValue
                    )
                }
            )
            if PeopleSubjectEvaluator.classify(evidence).category == .people {
                return .people
            }

            let segmentationRequest = VNGeneratePersonSegmentationRequest()
            segmentationRequest.qualityLevel = .fast
            segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let instanceRequest = VNGeneratePersonInstanceMaskRequest()
            try VNImageRequestHandler(url: url).perform([segmentationRequest, instanceRequest])
            evidence.personInstanceCount = instanceRequest.results?.first?.allInstances.count ?? 0
            if let buffer = segmentationRequest.results?.first?.pixelBuffer {
                evidence.personMaskCoverage = MaskCoverageReference.coverage(buffer)
                evidence.personMaskBoundingBox = MaskCoverageReference.boundingBox(buffer)
            }
            guard evidence.personMaskCoverage >= 0.006 else {
                return PeopleSubjectEvaluator.classify(evidence).category
            }

            let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
            saliencyRequest.revision = VNGenerateAttentionBasedSaliencyImageRequestRevision2
            try VNImageRequestHandler(url: url).perform([saliencyRequest])
            evidence.salientRegions = saliencyRequest.results?.first?.salientObjects?.map(\.boundingBox) ?? []
            return PeopleSubjectEvaluator.classify(evidence).category
        } catch {
            return .scenery
        }
    }
}
