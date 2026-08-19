import CoreGraphics
import Foundation
import ImageIO

enum AIReviewPreviewEncodingError: LocalizedError {
    case cannotReadImage
    case cannotEncodePreview

    var errorDescription: String? {
        switch self {
        case .cannotReadImage:
            String(localized: "无法读取其中一张候选照片，未发送任何照片。")
        case .cannotEncodePreview:
            String(localized: "无法生成 AI评分图片，未发送任何照片。")
        }
    }
}

/// 仅在内存内把本地原图重编码为无元数据 JPEG；绝不写入文件或上传原始文件。
enum AIReviewPreviewEncoder {
    static func jpegData(
        for url: URL,
        maximumPixelSize: Int = AIReviewPreviewSize.small.maximumPixelSize
    ) throws -> Data {
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AIReviewPreviewEncodingError.cannotReadImage
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw AIReviewPreviewEncodingError.cannotReadImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            throw AIReviewPreviewEncodingError.cannotEncodePreview
        }

        // 只把像素写入新 JPEG，不复制 EXIF、GPS、文件名或源文件属性。
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw AIReviewPreviewEncodingError.cannotEncodePreview
        }
        return output as Data
    }
}
