import Foundation

enum ExportService {
    /// 导出保留照片。数量由用户决定：这里只保证"有东西可导"且"每张都有类型"，
    /// 不再要求人物与风景恰好等于各自目标——目标是筛选过程中的参考值，不是导出闸门。
    static func copyCategorized(
        photos: [PhotoItem],
        to destinationParent: URL,
        now: Date = Date()
    ) throws -> URL {
        let photosByCategory = Dictionary(
            grouping: photos.compactMap {
                photo -> (PhotoCurationCategory, PhotoItem)? in
                guard let category = photo.curationCategory else {
                    return nil
                }
                return (category, photo)
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

        guard !photos.isEmpty else {
            throw ExportError.emptySelection
        }
        guard photosByCategory.values.reduce(0, {
            $0 + $1.count
        }) == photos.count else {
            throw ExportError.missingCategory
        }

        let exportURL = destinationParent.appendingPathComponent(
            "旅行照片筛选器-导出-\(exportTimestamp(from: now))",
            isDirectory: true
        )
        let manager = FileManager.default
        try manager.createDirectory(
            at: exportURL,
            withIntermediateDirectories: false
        )

        do {
            var manifestGroups: [CategorizedExportManifest.Group] = []
            var csvRows = ["category,path,filename"]
            for category in PhotoCurationCategory.allCases {
                let categoryDirectory = exportURL.appendingPathComponent(
                    category.title,
                    isDirectory: true
                )
                try manager.createDirectory(
                    at: categoryDirectory,
                    withIntermediateDirectories: false
                )
                var exportedNames: [String] = []
                for photo in photosByCategory[category, default: []] {
                    let destination = uniqueDestination(
                        for: photo.url,
                        in: categoryDirectory,
                        fileManager: manager
                    )
                    try manager.copyItem(at: photo.url, to: destination)
                    exportedNames.append(destination.lastPathComponent)
                    csvRows.append(
                        [
                            csvEscaped(category.rawValue),
                            csvEscaped(
                                "\(category.title)/\(destination.lastPathComponent)"
                            ),
                            csvEscaped(destination.lastPathComponent),
                        ].joined(separator: ",")
                    )
                }
                manifestGroups.append(
                    CategorizedExportManifest.Group(
                        category: category,
                        directory: category.title,
                        exportedCount: exportedNames.count,
                        filenames: exportedNames
                    )
                )
            }

            let manifest = CategorizedExportManifest(
                createdAt: now,
                exportedCount: photos.count,
                groups: manifestGroups
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: exportURL.appendingPathComponent("selection.json"),
                options: .atomic
            )
            // 清单里的类别目录名是中文（人物 / 风景）。不带 BOM 的 UTF-8 CSV 在 Excel 里会变成乱码，
            // 而这份文件正是给用户在表格软件里看的。
            let csv = "\u{FEFF}" + csvRows.joined(separator: "\n") + "\n"
            try csv.write(
                to: exportURL.appendingPathComponent("selection.csv"),
                atomically: true,
                encoding: .utf8
            )
            return exportURL
        } catch {
            try? manager.removeItem(at: exportURL)
            throw error
        }
    }

    /// 导出目录名必须与系统日历无关：使用日语和历、佛历等非公历时，默认 DateFormatter 会写出完全不同的年份。
    static func exportTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func uniqueDestination(for source: URL, in directory: URL, fileManager: FileManager) -> URL {
        let original = directory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base)-\(index).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private static func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum ExportError: LocalizedError, Equatable {
    case emptySelection
    case missingCategory

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            String(localized: "还没有保留任何照片，先保留至少一张再导出。")
        case .missingCategory:
            String(localized: "仍有照片未完成人物或风景分类，无法导出。")
        }
    }
}

struct CategorizedExportManifest: Codable, Equatable {
    struct Group: Codable, Equatable {
        let category: PhotoCurationCategory
        let directory: String
        let exportedCount: Int
        let filenames: [String]
    }

    let createdAt: Date
    let exportedCount: Int
    let groups: [Group]
}
