import CoreGraphics
import Foundation
import ImageIO

/// 单次解码的本地分析流水线。
///
/// 一张照片只打开一次 `CGImageSource`、只解码一次降采样图，随后的拍摄时间、感知指纹、
/// 技术质量和人物/风景分类全部复用同一份像素。原图仍然只读，像素只存在于运行内存中。
enum PhotoAnalysisPipeline {
    /// Vision 与技术分析共用的降采样边长。分类阈值全部按画面相对面积定义，在该尺度下仍然成立；
    /// 而按原始分辨率反复解码（本机 40MP JPEG 实测每张多花约 0.4 秒）没有换来判断质量。
    static let analysisPixelSize = 1024
    /// 清晰度、反差与曝光在该尺度上评估；64px 缩略图会把对焦信息一并抹掉。
    static let qualityPixelSize = 512
    /// 感知指纹固定使用 64 × 64 灰度栅格。
    static let fingerprintSideLength = 64

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "heic", "heif", "avci", "tif", "tiff",
    ]

    nonisolated static func photoID(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// 分析单张照片。任何一步失败都只降级该步的结果，不会抛错中断整轮扫描。
    nonisolated static func analyze(_ url: URL) -> PhotoAnalysisResult {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return PhotoAnalysisResult(
                photoID: photoID(for: url),
                captureDate: PhotoMetadataReader.captureDate(for: url),
                perceptualHash: nil,
                technicalQuality: nil
            )
        }

        let captureDate = PhotoMetadataReader.captureDate(from: source, url: url)
        guard let image = decodedImage(from: source, maximumPixelSize: analysisPixelSize) else {
            return PhotoAnalysisResult(
                photoID: photoID(for: url),
                captureDate: captureDate,
                perceptualHash: nil,
                technicalQuality: nil
            )
        }

        let fingerprintRaster = LuminanceThumbnailReader.raster(
            from: image,
            sideLength: fingerprintSideLength
        )
        let qualityRaster = LuminanceThumbnailReader.raster(
            from: image,
            sideLength: qualityPixelSize,
            preservingAspectRatio: true
        )

        return PhotoAnalysisResult(
            photoID: photoID(for: url),
            captureDate: captureDate,
            perceptualHash: fingerprintRaster.flatMap { PerceptualHasher.hash(from: $0) },
            technicalQuality: qualityRaster.map { TechnicalQualityAnalyzer.analyze($0) },
            curationCategory: PhotoCategoryClassifier.classify(image)
        )
    }

    nonisolated static func decodedImage(
        from source: CGImageSource,
        maximumPixelSize: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated static func decodedImage(for url: URL, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return decodedImage(from: source, maximumPixelSize: maximumPixelSize)
    }

    /// 并行分析一批照片，按 `batchSize` 分段回调，便于界面渐进显示。
    ///
    /// 并发路数刻意小于核心数：Vision 内部已经会用到 GPU / ANE，路数开满只会互相排队并推高内存。
    /// 每完成一张都会检查取消，因此切换或删除项目时后台工作会真的停下来。
    nonisolated static func analyze(
        urls: [URL],
        batchSize: Int,
        laneCount: Int = defaultLaneCount,
        onBatch: @Sendable @escaping ([PhotoAnalysisResult]) async -> Void
    ) async {
        guard !urls.isEmpty else { return }
        let lanes = max(1, min(laneCount, urls.count))
        var pending: [PhotoAnalysisResult] = []
        pending.reserveCapacity(batchSize)

        await withTaskGroup(of: PhotoAnalysisResult?.self) { group in
            var nextIndex = 0
            func addTask() {
                guard nextIndex < urls.count else { return }
                let url = urls[nextIndex]
                nextIndex += 1
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    return analyze(url)
                }
            }

            for _ in 0..<lanes { addTask() }

            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                if let result {
                    pending.append(result)
                }
                addTask()
                if pending.count >= batchSize {
                    let batch = pending
                    pending = []
                    await onBatch(batch)
                }
            }
        }

        guard !Task.isCancelled, !pending.isEmpty else { return }
        await onBatch(pending)
    }

    static var defaultLaneCount: Int {
        max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    /// 递归收集受支持的图片；跳过隐藏文件与包内容，结果按路径自然序稳定排序。
    nonisolated static func imageURLs(
        in folder: URL,
        supportedExtensions: Set<String> = PhotoAnalysisPipeline.supportedExtensions
    ) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var imageURLs: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isHidden != true,
                  supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }
            imageURLs.append(url)
        }
        return imageURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
