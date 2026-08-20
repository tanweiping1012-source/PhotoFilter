import Foundation
import ImageIO

enum PhotoMetadataReader {
    /// 优先读取相机写入的 EXIF 原始拍摄时间；没有时才回退到文件创建/修改时间。
    static func captureDate(for url: URL) -> Date? {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        return captureDate(from: source, url: url)
    }

    /// 复用调用方已经建立的 `CGImageSource`，避免为了读时间再打开一次原图。
    static func captureDate(from source: CGImageSource?, url: URL) -> Date? {
        if let source,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
                ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
                ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
            // 跨时区旅行时，相机写入的本地时间必须配合 EXIF 时区偏移才能还原成正确的绝对时间。
            let offsetString = exif?["OffsetTimeOriginal" as CFString] as? String
                ?? exif?["OffsetTimeDigitized" as CFString] as? String

            if let dateString, let date = parseEXIFDate(dateString, offset: offsetString) {
                return date
            }
        }

        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    static func parseEXIFDate(_ value: String, offset: String? = nil) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = offset.flatMap(timeZone(fromEXIFOffset:)) ?? .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }

    /// EXIF 偏移格式为 `+08:00` / `-05:00`；无法解析时返回 nil 并回退到本机时区。
    static func timeZone(fromEXIFOffset offset: String) -> TimeZone? {
        let trimmed = offset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6,
              let signCharacter = trimmed.first,
              signCharacter == "+" || signCharacter == "-" else {
            return nil
        }
        let components = trimmed.dropFirst().split(separator: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              (0...14).contains(hours),
              (0...59).contains(minutes) else {
            return nil
        }
        let sign = signCharacter == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }
}
